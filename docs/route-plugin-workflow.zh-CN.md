# URLRouter 路由插件工作流

本说明适用于 App 通过远程或本地 Swift Package 引用 URLRouter 的场景；不需要、也不应当
写死 SwiftPM checkout 的路径。

## 两个插件分别做什么

| Plugin Product | 执行时机 | 输出 | 是否会修改 Git 跟踪的文件 |
| --- | --- | --- | --- |
| `URLRouterRouteBuildPlugin` | 每次 Xcode 编译 | Derived Data 中临时的 `route-catalog.html` | 否 |
| `URLRouterRouteCommandPlugin` | 开发者明确执行时 | App 根目录的 `RouteContracts.json` 与 `docs/route-catalog.html` | 会，且必须先授权写入 |

一个 App 根目录只保留一份 `RouteContracts.json`。它汇总所有 Feature Package 和 App 自身
Swift 源码中的公开路由，而不是每个 Feature Package 各维护一份。网页目录会把 App 自身的
路由放在独立的 `App` 分区。路由变更时，应把此文件和 `docs/route-catalog.html` 一起提交。

## 在 Xcode 配置 Build Plugin

开始前，确保 App target **直接**添加了 URLRouter Package Dependency：在 Xcode 选择
**File → Add Package Dependencies…**，输入 URLRouter 仓库地址，选择 `2.5.1` 或更高版本，
并将 `URLRouter` library product 添加给该 App target。若 URLRouter 只是其他 Package 的
间接依赖，插件不会出现在可选列表中。

1. 在 Project navigator 选中蓝色的工程文件。
2. 在 **TARGETS** 中选中拥有这些 Feature Package 的 App target。
3. 打开 **Build Phases**。
4. 展开 **Run Build Tool Plug-ins**。如果没有这一项，在 Build Phases 中点 **+**，添加
   *Run Build Tool Plug-ins* phase。
5. 点击该 phase 中的 **+**，从 URLRouter 的 products 中选择
   `URLRouterRouteBuildPlugin`。
6. 编译一次 App。Xcode 会执行名为 **Verify URLRouter route contracts** 的任务。

首次成功编译表示 App 根目录的 `RouteContracts.json` 与各 Feature Package 中可可靠推导的
路由一致。插件还会在 Derived Data 的插件工作目录中生成
`RouteCatalog/route-catalog.html`，供本地查看。它只是构建产物，不应提交。

若列表中没有插件，依次检查：在 **File → Packages → Resolve Package Versions** 解析版本；
确认 URLRouter 为 2.5.1 或更高版本；确认 App target 直接依赖 `URLRouter` Package。若
Xcode 尚未刷新 package products，关闭再重新打开工程。

## 在 Xcode 执行 Command Plugin，生成需提交的文件

新增、删除或修改公开路由、必填参数、目标页面或展示方式后，按以下步骤执行：

1. 保存 Feature Package 的源码改动。
2. 选择 **File → Packages → URLRouterRouteCommandPlugin**。
3. Xcode 询问是否允许写入 package/project 目录时，选择允许。这是预期操作：该命令会
   更新受版本控制、需要审查的文件。
4. 检查 App 根目录的 `RouteContracts.json` 和 `docs/route-catalog.html` 的改动。
5. 再编译一次 App，确认 Build Plugin 能通过。
6. 在同一个 PR 中提交 Feature 源码、两个生成文件和相应测试。

如果命令无法可靠推导 URL 或参数，它会失败而不会猜测。请补全 Feature 中标准的
`RouteModule` resolver 或 URL builder 声明，再重新执行。

## Swift Package App 的等价命令

在 App 的 package 根目录执行：

```bash
swift package plugin generate-urlrouter-contracts --allow-writing-to-package-directory
```

它与 Xcode Command Plugin 的效果相同。必须在 App package 中执行，不能在 URLRouter
自身的 checkout 中执行，否则扫描的将不是目标 App 及其 Feature Packages。

## CI 与审查清单

生成后，CI 仍应保留以下校验：

```bash
swift Scripts/update_route_contracts.swift --check
swift Scripts/validate_route_contract.swift RouteContracts.json
```

若 CI 使用远程依赖而未执行 Xcode Build Plugin，请从已解析的 URLRouter package 调用等价
脚本。Build Plugin 被刻意设计为不改写仓库文件，让生成的契约改动始终可在 PR 中审查。
