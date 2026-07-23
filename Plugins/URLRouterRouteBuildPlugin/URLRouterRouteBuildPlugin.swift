import Foundation
import PackagePlugin

@main
struct URLRouterRouteBuildPlugin: BuildToolPlugin {
    private var pluginPackageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let outputDirectory = context.pluginWorkDirectoryURL.appending(path: "RouteCatalog")
        return [try makeCommand(
            appRoot: context.package.directoryURL,
            outputDirectory: outputDirectory,
            scriptsRoot: context.package.directoryURL
        )]
    }

    private func makeCommand(appRoot: URL, outputDirectory: URL, scriptsRoot: URL) throws -> Command {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let updateScript = scriptsRoot.appending(path: "Scripts/update_route_contracts.swift")
        let catalogScript = scriptsRoot.appending(path: "Scripts/generate_route_catalog.swift")
        return .prebuildCommand(
            displayName: "Verify URLRouter route contracts",
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "sh", "-c",
                "unset SDKROOT; swift \"\(updateScript.path)\" --app-root \"\(appRoot.path)\" --check && swift \"\(catalogScript.path)\" --app-root \"\(appRoot.path)\" --contracts RouteContracts.json --output \"$1/route-catalog.html\"",
                "urlrouter-route-plugin", outputDirectory.path
            ],
            outputFilesDirectory: outputDirectory
        )
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension URLRouterRouteBuildPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let outputDirectory = context.pluginWorkDirectoryURL.appending(path: "RouteCatalog")
        return [try makeCommand(
            appRoot: context.xcodeProject.directoryURL,
            outputDirectory: outputDirectory,
            scriptsRoot: pluginPackageRoot
        )]
    }
}
#endif
