# URLRouter route-plugin workflow

This guide applies when an App consumes URLRouter through either a remote or a
local Swift Package dependency. No path to SwiftPM's checkout directory is
needed.

## What each plugin does

| Plugin Product | When it runs | Output | May change Git-tracked files? |
| --- | --- | --- | --- |
| `URLRouterRouteBuildPlugin` | Every Xcode build | A temporary `route-catalog.html` in Derived Data | No |
| `URLRouterRouteCommandPlugin` | A developer runs it intentionally | App-root `RouteContracts.json` and `docs/route-catalog.html` | Yes, after Xcode grants write access |

Keep exactly one `RouteContracts.json` at the App root. It describes the
public routes aggregated from every Feature Package **and App-owned Swift
source**; do not create one per Feature Package. The catalog renders App-owned
routes in an `App` section. Commit both this file and `docs/route-catalog.html`
with the route change that produced them.

## Xcode: configure the Build Plugin

Before starting, add URLRouter **directly** to the App target's Package
Dependencies. In Xcode, use **File → Add Package Dependencies…**, enter the
URLRouter repository URL, select version `2.5.1` or later, and add the
`URLRouter` library product to the App target. The plugin will not be
selectable if URLRouter is only a transitive dependency of another package.

1. In the Project navigator, select the blue project file.
2. Under **TARGETS**, select the App target that owns the Feature Packages.
3. Open **Build Phases**.
4. Expand **Run Build Tool Plug-ins**. If it is absent, use the **+** button in
   Build Phases to add a *Run Build Tool Plug-ins* phase.
5. Press **+** in that phase and choose `URLRouterRouteBuildPlugin` from
   URLRouter's products.
6. Build the App once. Xcode runs a task named **Verify URLRouter route
   contracts**.

The first successful build confirms that the App-root `RouteContracts.json`
matches the routes that can be safely inferred from the Feature Packages. It
also creates `RouteCatalog/route-catalog.html` inside Xcode's plugin work
directory under Derived Data. That HTML is a build artifact for local
inspection, not a file to commit.

If the plugin is not listed, first resolve package versions with **File →
Packages → Resolve Package Versions**, confirm that the selected URLRouter
version is 2.5.1 or later, and confirm the App target directly depends on the
`URLRouter` package. Then close and reopen the project if Xcode has not
refreshed its package products.

## Xcode: generate the tracked contract and catalog

Run this after adding, removing, or changing a public route, its required
parameters, its destination, or presentation mode.

1. Save the Feature Package source changes.
2. Select **File → Packages → URLRouterRouteCommandPlugin**.
3. When Xcode asks for permission to write to the package/project directory,
   approve the request. This is intentional: the command updates reviewed
   source-controlled artifacts.
4. Inspect the changed App-root `RouteContracts.json` and
   `docs/route-catalog.html`.
5. Build the App again. The Build Plugin must now pass.
6. Include the Feature source, both generated files, and appropriate tests in
   the same pull request.

The command fails rather than guessing when it cannot reliably infer a route
URL or its parameters. Fix the Feature's standard `RouteModule` resolver or
URL-builder declaration, then run the command again.

## Swift Package App equivalent

From the App's package root, run:

```bash
swift package plugin generate-urlrouter-contracts --allow-writing-to-package-directory
```

This has the same effect as the Xcode Command Plugin. The command must be run
from the App package, not from URLRouter's own checkout, so that the App root
and its Feature Packages are scanned.

## CI and review checklist

CI should keep these checks after generation:

```bash
swift Scripts/update_route_contracts.swift --check
swift Scripts/validate_route_contract.swift RouteContracts.json
```

For a remote dependency, invoke the equivalent scripts from the resolved
URLRouter package if CI does not already use the Xcode build plugin. The build
plugin intentionally does not rewrite the repository: generated contract
changes must remain visible in a pull request.
