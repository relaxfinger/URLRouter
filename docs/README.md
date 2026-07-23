# URLRouter documentation

[中文](README.zh-CN.md) · [Repository README](../README.md) · [Beginner blog tutorial](https://zhangjipeng.com/post-urlrouter.html)

Use the guide that matches the job in front of you:

| Guide | Use it when you need to… |
| --- | --- |
| [Getting started](getting-started.md) | install the package, create a Feature route, host it in SwiftUI, and add Universal Links |
| [Architecture](architecture.md) | decide package ownership, URL shape, public contracts, and App-shell responsibilities |
| [Route-plugin workflow](route-plugin-workflow.md) | configure the Xcode Build Plugin and generate the reviewed contract and catalog |
| [Production governance](production-governance.md) | add remote restrictions, a circuit breaker, concurrent-route coordination, telemetry, and contract checks |
| [ADR 0001](adr/0001-public-compatibility-gates.md) | understand the API and route-contract compatibility gates in pull requests |

## Recommended reading order

1. Complete the five-minute example in the repository README.
2. Read **Getting started** while wiring the first real Feature.
3. Read **Architecture** before a second team or Feature publishes routes.
4. Adopt the relevant parts of **Production governance** only when the product needs them.

The English and Chinese guides describe the same public behavior. Code examples
use `example.com`; replace it with an HTTPS domain controlled by your team.
