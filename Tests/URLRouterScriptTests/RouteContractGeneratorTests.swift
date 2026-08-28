import Foundation
import XCTest

final class RouteContractGeneratorTests: XCTestCase {
    private struct Manifest: Decodable {
        let schemaVersion: Int
        let supportedVersions: [String]
        let routes: [Route]
    }

    private struct Route: Decodable {
        let moduleID: String
        let routeID: String
        let pathTemplate: String
        let presentations: [String]
        let requiredQueryItems: [String]
    }

    func testGeneratesContractsForCommonAppOwnedRouteStyles() throws {
        let appRoot = try makeTemporaryApp(source: """
        import Foundation

        struct URLQueryItem {
            let name: String
            let value: String?
        }

        enum ModulePresentationStyle {
            case push
            case tab
        }

        struct ModuleRoute {
            let moduleID: String
            let routeID: String
            let parameters: [String: String]

            init(moduleID: String, routeID: String, parameters: [String: String] = [:]) {
                self.moduleID = moduleID
                self.routeID = routeID
                self.parameters = parameters
            }
        }

        struct RouteModule {
            init(id: String, resolver: (Link) -> ModuleRoute?) {}
        }

        struct Link {
            let pathComponents: [String]
            let query: [String: String]
        }

        enum AppRoutes {
            static let practiceTab = ModuleRoute(moduleID: "navigation", routeID: "practice")
            static let historyTab = ModuleRoute(moduleID: "navigation", routeID: "history")
            static let profileTab = ModuleRoute(moduleID: "navigation", routeID: "profile")

            static let navigationModule = RouteModule(id: "navigation") { link in
                switch link.pathComponents {
                case ["practice"]:
                    practiceTab
                case ["history"]:
                    return historyTab
                case ["profile"]:
                    profileTab
                default:
                    nil
                }
            }

            static let practiceModule = RouteModule(id: "practice") { link in
                switch link.pathComponents {
                case ["practice", "recording"]:
                    ModuleRoute(moduleID: "practice", routeID: "recording")
                case ["practice", "topics"]:
                    return ModuleRoute(moduleID: "practice", routeID: "topics")
                default:
                    nil
                }
            }

            static let historyModule = RouteModule(id: "history") { link in
                guard case ["history", "attempt"] = link.pathComponents,
                      let id = link.query["id"] else {
                    return nil
                }
                return ModuleRoute(moduleID: "history", routeID: "attempt", parameters: ["id": id])
            }

            static let feedbackModule = RouteModule(id: "feedback") { link in
                let path = link.pathComponents
                guard path.count == 2,
                      path[0] == "feedback",
                      path[1] == "attempt",
                      let id = link.query["id"] else {
                    return nil
                }
                return ModuleRoute(moduleID: "feedback", routeID: "attempt", parameters: ["id": id])
            }

            static let profileModule = RouteModule(id: "profile") { link in
                guard case ["profile", "paywall"] = link.pathComponents else {
                    return nil
                }
                return ModuleRoute(moduleID: "profile", routeID: "paywall")
            }
        }

        enum AppLinks {
            static let practiceTab = makeURL(path: "/practice", presentation: .tab)
            static let historyTab = makeURL(path: "/history", presentation: .tab)
            static let profileTab = makeURL(path: "/profile", presentation: .tab)
            static let dailyRecording = makeURL(path: "/practice/recording", presentation: .push)
            static let topicLibrary = makeURL(path: "/practice/topics", presentation: .push)
            static let paywall = makeURL(path: "/profile/paywall", presentation: .push)

            static func historyAttempt(_ id: UUID) -> URL {
                makeURL(path: "/history/attempt", presentation: .push, queryItems: [
                    URLQueryItem(name: "id", value: id.uuidString)
                ])
            }

            static func feedbackAttempt(_ id: UUID) -> URL {
                makeURL(path: "/feedback/attempt", presentation: .push, queryItems: [
                    URLQueryItem(name: "id", value: id.uuidString)
                ])
            }

            static func literalArticle(_ id: UUID) -> URL {
                URL(string: "https://example.com/articles/\\(id.uuidString)?presentation=push&version=1")!
            }

            private static func makeURL(path: String, presentation: ModulePresentationStyle, queryItems: [URLQueryItem] = []) -> URL {
                var components = URLComponents()
                components.host = "bandup.app"
                URL(string: "https://example.com")!
            }
        }
        """)

        try runGenerator(appRoot: appRoot)
        let manifest = try readManifest(at: appRoot.appendingPathComponent("RouteContracts.json"))

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.supportedVersions, ["1"])
        XCTAssertEqual(Set(manifest.routes.map { "\($0.moduleID)/\($0.routeID)" }), [
            "navigation/practice",
            "navigation/history",
            "navigation/profile",
            "practice/recording",
            "practice/topics",
            "history/attempt",
            "feedback/attempt",
            "profile/paywall"
        ])
        XCTAssertEqual(route("navigation", "practice", in: manifest)?.pathTemplate, "/practice")
        XCTAssertEqual(route("practice", "recording", in: manifest)?.presentations, ["push"])
        XCTAssertEqual(route("history", "attempt", in: manifest)?.pathTemplate, "/history/attempt")
        XCTAssertEqual(route("history", "attempt", in: manifest)?.requiredQueryItems, ["id", "presentation", "version"])
        XCTAssertEqual(route("feedback", "attempt", in: manifest)?.pathTemplate, "/feedback/attempt")
        XCTAssertEqual(route("profile", "paywall", in: manifest)?.presentations, ["push"])

        try runGenerator(appRoot: appRoot, check: true)

        let catalogURL = appRoot.appendingPathComponent("docs/route-catalog.html")
        try runCatalogGenerator(appRoot: appRoot, output: catalogURL)
        let catalog = try String(contentsOf: catalogURL, encoding: .utf8)
        XCTAssertTrue(catalog.contains("https://bandup.app/history/attempt?id={id}&amp;presentation=push&amp;version=1"))
        XCTAssertFalse(catalog.contains("https://example.com/history/attempt"))
    }

    func testCatalogHostArgumentOverridesSourceInference() throws {
        let appRoot = try makeTemporaryApp(source: """
        struct ModuleRoute {
            init(moduleID: String, routeID: String) {}
        }

        struct RouteModule {
            init(id: String, resolver: (Link) -> ModuleRoute?) {}
        }

        struct Link {
            let pathComponents: [String]
        }

        enum AppRoutes {
            static let profile = ModuleRoute(moduleID: "profile", routeID: "home")
            static let module = RouteModule(id: "profile") { link in
                switch link.pathComponents {
                case ["profile"]: return profile
                default: return nil
                }
            }
        }

        enum AppLinks {
            static let profile = URL(string: "https://wrong.example/profile?presentation=tab&version=1")!
        }
        """)

        try runGenerator(appRoot: appRoot)
        let catalogURL = appRoot.appendingPathComponent("docs/custom-catalog.html")
        try runCatalogGenerator(appRoot: appRoot, output: catalogURL, host: "docs.bandup.app")
        let catalog = try String(contentsOf: catalogURL, encoding: .utf8)

        XCTAssertTrue(catalog.contains("https://docs.bandup.app/profile?presentation=tab&amp;version=1"))
        XCTAssertFalse(catalog.contains("wrong.example"))
    }

    func testCatalogHostInferenceIgnoresInterpolatedURLHelpers() throws {
        let appRoot = try makeTemporaryApp(source: """
        struct ModuleRoute {
            init(moduleID: String, routeID: String) {}
        }

        struct RouteModule {
            init(id: String, resolver: (Link) -> ModuleRoute?) {}
        }

        struct Link {
            let pathComponents: [String]
        }

        enum AppRoutes {
            static let home = ModuleRoute(moduleID: "home", routeID: "index")
            static let module = RouteModule(id: "home") { link in
                switch link.pathComponents {
                case ["home"]: return home
                default: return nil
                }
            }
        }

        enum AppLinks {
            static func makeURL(host: String, path: String) -> String {
                "https://\\(host)\\(path)"
            }

            static let home = URL(string: "https://catalog.example/home?presentation=push&version=1")!
        }
        """)

        try runGenerator(appRoot: appRoot)
        let catalogURL = appRoot.appendingPathComponent("docs/route-catalog.html")
        try runCatalogGenerator(appRoot: appRoot, output: catalogURL)
        let catalog = try String(contentsOf: catalogURL, encoding: .utf8)

        XCTAssertTrue(catalog.contains("https://catalog.example/home?presentation=push&amp;version=1"))
        XCTAssertFalse(catalog.contains("https://\\(host)\\(path)"))
    }

    private func makeTemporaryApp(source: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("URLRouterScriptTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("App", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try source.write(to: sourceDirectory.appendingPathComponent("Routes.swift"), atomically: true, encoding: .utf8)
        return root
    }

    private func runGenerator(appRoot: URL, check: Bool = false) throws {
        let script = packageRoot().appendingPathComponent("Scripts/update_route_contracts.swift")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", script.path, "--app-root", appRoot.path] + (check ? ["--check"] : [])
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "SDKROOT")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            XCTFail(String(data: data, encoding: .utf8) ?? "Generator failed.")
        }
    }

    private func runCatalogGenerator(appRoot: URL, output: URL, host: String? = nil) throws {
        let script = packageRoot().appendingPathComponent("Scripts/generate_route_catalog.swift")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift",
            script.path,
            "--app-root",
            appRoot.path,
            "--output",
            output.path
        ] + (host.map { ["--host", $0] } ?? [])
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "SDKROOT")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            XCTFail(String(data: data, encoding: .utf8) ?? "Catalog generator failed.")
        }
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readManifest(at url: URL) throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    private func route(_ moduleID: String, _ routeID: String, in manifest: Manifest) -> Route? {
        manifest.routes.first { $0.moduleID == moduleID && $0.routeID == routeID }
    }
}
