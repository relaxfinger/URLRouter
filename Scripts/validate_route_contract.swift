import Foundation

struct RouteContractManifest: Decodable {
    let schemaVersion: Int
    let supportedVersions: [String]
    let routes: [RouteContract]
}

struct RouteContract: Decodable {
    let moduleID: String
    let routeID: String
    let pathTemplate: String
    let presentations: [String]
    let requiredQueryItems: [String]
}

let validPresentations: Set<String> = ["push", "tab", "sheet", "fullScreenCover"]
let manifestPath = CommandLine.arguments.dropFirst().first ?? "RouteContracts.json"

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    let manifest = try JSONDecoder().decode(RouteContractManifest.self, from: data)
    var failures: [String] = []

    if manifest.schemaVersion != 1 {
        failures.append("Unsupported schemaVersion \(manifest.schemaVersion); expected 1.")
    }
    if manifest.supportedVersions.isEmpty || Set(manifest.supportedVersions).count != manifest.supportedVersions.count || manifest.supportedVersions.contains(where: { $0.isEmpty }) {
        failures.append("supportedVersions must be non-empty, unique, and contain no empty values.")
    }

    var routeKeys = Set<String>()
    var invocationKeys = Set<String>()
    for route in manifest.routes {
        let label = "\(route.moduleID)/\(route.routeID)"
        guard !route.moduleID.isEmpty, !route.routeID.isEmpty, route.pathTemplate.hasPrefix("/") else {
            failures.append("\(label) needs non-empty IDs and an absolute pathTemplate.")
            continue
        }
        guard routeKeys.insert(label).inserted else {
            failures.append("Duplicate moduleID/routeID: \(label).")
            continue
        }
        guard !route.presentations.isEmpty, Set(route.presentations).count == route.presentations.count,
              Set(route.presentations).isSubset(of: validPresentations) else {
            failures.append("\(label) has invalid or duplicate presentations.")
            continue
        }
        guard Set(route.requiredQueryItems).count == route.requiredQueryItems.count,
              Set(["presentation", "version"]).isSubset(of: Set(route.requiredQueryItems)) else {
            failures.append("\(label) must require presentation and version query items.")
            continue
        }
        for presentation in route.presentations {
            let invocationKey = "\(route.pathTemplate)#\(presentation)"
            if !invocationKeys.insert(invocationKey).inserted {
                failures.append("Duplicate route invocation contract: \(invocationKey).")
            }
        }
    }

    guard failures.isEmpty else {
        throw NSError(domain: "RouteContract", code: 1, userInfo: [
            NSLocalizedDescriptionKey: failures.joined(separator: "\n")
        ])
    }
    print("Route contract validation passed (\(manifest.routes.count) routes, versions: \(manifest.supportedVersions.joined(separator: ", "))).")
} catch {
    fputs("Route contract validation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
