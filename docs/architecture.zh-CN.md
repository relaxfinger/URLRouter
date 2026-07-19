# URLRouter 架构与路由契约

[English](architecture.md) · [文档目录](README.zh-CN.md)

这篇说明解释项目变大后，如何仍让路由边界保持清楚、容易维护。

## 四个职责

| 部分 | 负责什么 |
| --- | --- |
| URL 契约 | 目标页面稳定、公开的地址，以及它的展示方式 |
| Feature Package | URL 解析和目标 View 的创建 |
| App 壳层 | 已链接模块的注册、可信 host、策略和场景导航状态 |
| URLRouter | URL 校验、路由解析和 SwiftUI 导航状态更新 |

还有一个可选的第五部分：`URLRouterPolicyProvider`。它把远程策略刷新到内存
Store 中，不负责任何页面跳转，核心库也不依赖它。

## 推荐的 Package 依赖方向

```text
App target
  ├── ArticleFeature package ──> URLRouter
  ├── SettingsFeature package ─> URLRouter
  └── URLRouterPolicyProvider（可选，仅 App target）
```

Feature 不应为了展示对方页面而互相 import。App 依赖各 Feature Package，并
注册它们公开的 `RouteModule`。Feature 可以公开一个很小的 URL builder API；依赖
边界特别严格时，也可以由一个共享 contracts package 提供 builder。不要把另一个
Feature 的 View 类型当成导航 API 暴露出去。

## 把 URL 当作公开契约来设计

让网页、推送和另一个 Feature 都能理解同一条 URL：

```text
https://example.com/articles/42?presentation=push&version=1
```

从第一版开始坚持这些规则：

- 只使用 HTTPS 和团队控制的 host。
- 只放稳定 ID；不放凭据、token、联系方式或完整 JSON。
- `presentation` 必填：`push`、`tab`、`sheet` 或 `fullScreenCover`。
- 对外或长期存在的链接带契约 `version`。
- 由拥有它的 Feature 用 `URLComponents` 文档化和构造 URL。

一旦发布，URL 的兼容成本和公开 Swift API 一样高。迁移时优先新增路径或版本；
不要悄悄改变或删除一条已有路径的含义。

## 让 Feature 就地解析

一个 module 可以拥有多条链接。固定路径要写在带参数的路径前面：

```swift
switch link.pathComponents {
case ["articles"]:
    return ModuleRoute(moduleID: "articles", routeID: "list")
case ["articles", "saved"]:
    return ModuleRoute(moduleID: "articles", routeID: "saved")
case ["articles", let id] where !id.isEmpty:
    return ModuleRoute(moduleID: "articles", routeID: "detail", parameters: ["id": id])
default:
    return nil
}
```

契约没有定义的路径后缀不要接受。严格解析会让不合法的外部链接安全失败，而不是
打开意外页面。

`ModuleRoute` 只包含 module ID、route ID 和字符串参数。不要把业务对象塞进去；
目标页面应通过 ViewModel 或 Use Case 加载最新数据。这样恢复状态、测试和跨 Package
边界都会更简单。

## 让 App 壳层保持很小

`AppRoutes.swift` 只注册已链接进 App 的模块：

```swift
enum AppRoutes {
    static let registry = ModuleRouteRegistry(modules: [
        ArticleFeature.module,
        SettingsFeature.module
    ])
}
```

它不应变成一个解析全 App 所有路径的大 `switch`。registry 会校验重复 module ID、
错误的模块归属，以及需要展示却缺少 destination 的路由。

壳层适合放全局规则：可信 host、支持的 URL 版本、Feature 开关、权限决定和埋点
适配器；不适合写死 App 的登录实现。登录怎么做由 App 决定，路由策略只回答“当前
这条路由是否允许进入”。

## 有意识地处理 Tab

`RouterHost` 管理 push 和模态目标。收到 tab 路由时，它会写入
`router.selectedTab`。将这个状态绑定到根部 `TabView` 的 selection，并让 URL 的
route ID 与 tab tag 完全一致。这样路由不会出现“已处理但界面没有切换 tab”的问题。

## 发布或修改一条路由

每次修改公开路由，都在同一个 PR 中更新：

1. Feature 的解析器和 URL builder。
2. `RouteContracts.json`。
3. 测试和调用方文档。
4. 旧 URL 已存在于邮件、网页、推送或已发布 App 时的迁移说明。

仓库 CI 会阻止目录结构错误和破坏性契约变化，但它不会替你决定产品迁移策略。
删除或改变已有 URL 的含义，应按破坏性变更处理并提前规划。

关于灰度、远程策略、并发与可观测性，请继续阅读
[生产治理](production-governance.zh-CN.md)。
