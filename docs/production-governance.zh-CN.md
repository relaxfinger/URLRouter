# 生产环境路由治理

[English](production-governance.md) · [文档目录](README.zh-CN.md)

先使用直接路由 modifier。只有真实产品需求出现时，才按需加入以下能力；它们不
绑定后端、登录 SDK、埋点服务或远程配置厂商。

## 远程策略与紧急熔断

远程策略就是路由的“小控制台”。等 App Store 发版太慢时，它可以禁用出现故障的
支付 Feature、收紧展示方式，或在严重事故时停止所有模块路由。后台不替 App 决定
跳转；它只下发 App 在本地执行的限制。

`ModuleRoutePolicy` 是 App 不能被远程放宽的本地底线。远程策略只能收紧它，不能
绕过本地授权，也不能重新允许不支持的 URL 版本。

```swift
let localPolicy = ModuleRoutePolicy(
    acceptedContractVersions: ["1"],
    allowsUnversionedLinks: false,
    isModuleEnabled: { featureFlags.isEnabled($0) },
    isAuthorized: { route, _ in
        permissions.canOpen(moduleID: route.moduleID, routeID: route.routeID)
    }
)
```

受保护的 HTTPS 接口可以返回：

```json
{
  "isCircuitBreakerOpen": false,
  "disabledModuleIDs": ["checkout"],
  "allowedPresentationStyles": ["push", "tab"],
  "acceptedContractVersions": ["1"]
}
```

鉴权由 App 负责；熔断等高影响控制建议使用带签名的响应，校验通过后才应用。

## 可选 Provider：先读缓存，再后台刷新

`URLRouterPolicyProvider` 不是“每次跳转前都请求后台”。它独立维护
`ModuleRoutePolicyStore`，每次路由只同步读取内存中的 store。

```text
冷启动：       立即恢复最后一次已验证缓存
首屏之后：     后台拉取最新策略
App 回到前台： 超过刷新间隔才拉取
拉取失败：     继续使用最后一次可信策略
缓存太旧：     回退到 App 内置的安全本地策略
```

只有 App 壳层导入该可选 product：

```swift
import URLRouter
import URLRouterPolicyProvider

@MainActor
final class AppRoutePolicySession {
    let store: ModuleRoutePolicyStore
    let provider: RoutePolicyProvider

    init(localPolicy: ModuleRoutePolicy, cacheURL: URL) {
        store = ModuleRoutePolicyStore(localPolicy: localPolicy)
        provider = RoutePolicyProvider(
            store: store,
            source: CompanyPolicySource(),
            cache: FileRoutePolicyCache(url: cacheURL),
            strategy: .standard
        )
    }

    func start() async {
        _ = await provider.bootstrap() // 恢复可信缓存，不等待网络
        _ = await provider.refresh()   // 后台刷新
    }

    func appBecameActive() async {
        _ = await provider.refreshIfNeeded()
    }
}
```

缓存放在 Application Support。使用 Provider 时，把 `policySession.store` 交给
直接 modifier 或 coordinator；只使用本地策略时传 `policy: localPolicy`，两者
不要同时传。

## 协调同时到达的路由请求

推送、Universal Link 和 App 内操作可能同时到达时，每个场景使用一个
`ModuleRouteCoordinator`。它给导航加了一条小队列：

- 完全相同的 URL 会合并。
- 优先级是 `critical`、`external`、`userInitiated`、`background`。
- 同优先级按到达顺序处理。
- 默认最多等待 10 条，等待 30 秒后过期。
- 真正跳转前会再次检查策略；等待期间熔断打开仍会生效。

```swift
let coordinator = ModuleRouteCoordinator(
    router: router,
    registry: AppRoutes.registry,
    allowedHosts: ["example.com"],
    policyStore: policySession.store,
    configuration: ModuleRouteCoordinatorConfiguration(
        maximumPendingRequests: 10,
        defaultTimeToLive: 30,
        transitionDelay: .milliseconds(350)
    )
)
```

用 `.moduleLinkRouting(coordinator: coordinator)` 安装它。不要每个按钮各建一个
coordinator。App 主动请求可调用 `route(_:priority:expiresAt:)`；`openURL` 和
Universal Link 默认使用 `.external`。

## 记录路由，但不要收集敏感 URL

`ModuleRouteEvent` 是排障“面包屑”：它说明请求成功、URL 不合法、被策略拒绝，
还是从队列丢弃。它包含 trace ID、host、module ID、route ID、展示方式、结果和稳定
错误码，但不包含 query value。

```swift
@MainActor
final class AppRouteObserver: ModuleRouteObserving {
    func record(_ event: ModuleRouteEvent) {
        logger.info("route=\(event.outcome.rawValue) code=\(event.failureCode ?? "handled")")
        metrics.increment("route.\(event.failureCode ?? "handled")")
    }
}
```

`logger` 和 `metrics` 是 App 自己的适配器。不要把完整 URL、文章 ID、token 或个人
信息作为指标标签。先看成功率、失败原因排行、队列满和过期次数即可。

## 用契约 CI 保护已发布 URL

`RouteContracts.json` 是 App 根目录唯一、受版本控制的公开路由目录，而不是每个
Feature Package 都复制一份。修改公开路由时，同一个 PR 还要修改 Feature 解析器和
URL builder、重新生成目录、更新测试，以及必要的迁移说明。

CI 会校验目录并与 PR 基线比较，拒绝意外删除或不兼容修改路径、展示方式、必填参数
和支持的协议版本。确实要破坏兼容性时，按主版本变更处理并提供迁移方案。

```bash
swift Scripts/update_route_contracts.swift --check
swift Scripts/validate_route_contract.swift RouteContracts.json
```

URLRouter 是远程依赖时，在 App target 的 **Build Phases → Run Build Tool Plug-ins** 启用
`URLRouterRouteBuildPlugin`。Xcode 会把它当作 Package Product 自行解析，因此不需要
checkout 路径或自定义 Run Script。每次构建都会校验目录，并在 Derived Data 的插件工作目录
生成可检查的 HTML 网页。

开发者明确要更新受版本控制文件时，在 Xcode 的 **File → Packages** 运行
`URLRouterRouteCommandPlugin`。对于 Swift Package App，等价命令是：

```bash
swift package plugin generate-urlrouter-contracts --allow-writing-to-package-directory
```

该命令会明确请求写入授权，再更新 `RouteContracts.json` 和
`docs/route-catalog.html`。CI 仍应执行上面的两条校验命令；Build Plugin 有意不改写
受版本控制的文件。

## 一个实际的接入顺序

1. 发布一条带版本 URL 和对应 Feature 解析器。
2. 加入 Universal Link 和测试。
3. 其他团队依赖 URL 前，在 App 根目录生成 `RouteContracts.json`。
4. 客服需要排障时加入可观测性。
5. 运营需要安全的远程限制时加入 Provider。
6. 多个路由来源真的会竞争时加入 coordinator。
