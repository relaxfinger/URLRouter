import Foundation
import PackagePlugin

@main
struct URLRouterRouteCommandPlugin: CommandPlugin {
    private var pluginPackageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        try run(appRoot: context.package.directoryURL, scriptsRoot: context.package.directoryURL)
    }

    fileprivate func run(appRoot: URL, scriptsRoot: URL) throws {
        let updateScript = scriptsRoot.appending(path: "Scripts/update_route_contracts.swift")
        let catalogScript = scriptsRoot.appending(path: "Scripts/generate_route_catalog.swift")
        try runSwift(script: updateScript, arguments: ["--app-root", appRoot.path])
        try runSwift(script: catalogScript, arguments: ["--app-root", appRoot.path])
    }

    private func runSwift(script: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", script.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "SDKROOT")
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "URLRouterRouteCommandPlugin", code: Int(process.terminationStatus))
        }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension URLRouterRouteCommandPlugin: XcodeCommandPlugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        try run(appRoot: context.xcodeProject.directoryURL, scriptsRoot: pluginPackageRoot)
    }
}
#endif
