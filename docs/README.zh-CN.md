# URLRouter 文档

[English](README.md) · [仓库 README](../README.zh-CN.md) · [新手完整教程](https://zhangjipeng.com/post-urlrouter.html)

按你当前要完成的工作选择文档：

| 文档 | 适合什么场景 |
| --- | --- |
| [接入指南](getting-started.zh-CN.md) | 安装 Package、创建 Feature 路由、接入 SwiftUI 和 Universal Link |
| [架构说明](architecture.zh-CN.md) | 设计 Package 边界、URL 形状、公开契约和 App 壳层职责 |
| [路由插件工作流](route-plugin-workflow.zh-CN.md) | 配置 Xcode Build Plugin，并生成需要审查的契约与网页目录 |
| [生产治理](production-governance.zh-CN.md) | 接入远程限制、紧急熔断、并发协调、遥测和契约检查 |
| [ADR 0001](adr/0001-public-compatibility-gates.md) | 了解 PR 中的公开 API 与路由契约兼容性门禁 |

## 推荐阅读顺序

1. 先完成仓库 README 的 5 分钟示例。
2. 接第一个真实 Feature 时阅读**接入指南**。
3. 第二个团队或 Feature 要发布路由前阅读**架构说明**。
4. 只有产品确实需要时，再按需采用**生产治理**的能力。

中英文文档描述相同的公开行为。示例中的 `example.com` 只是占位符；请替换为
团队自己控制的 HTTPS 域名。
