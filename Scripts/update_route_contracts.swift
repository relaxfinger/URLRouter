import Foundation

struct RouteContractManifest: Codable, Equatable {
    let schemaVersion: Int
    let supportedVersions: [String]
    let routes: [RouteContract]
}

struct RouteContract: Codable, Equatable {
    let moduleID: String
    let routeID: String
    let pathTemplate: String
    let presentations: [String]
    let requiredQueryItems: [String]
}

struct FeatureSource {
    let moduleID: String
    let source: String
}

let fileManager = FileManager.default

func matches(_ pattern: String, in text: String) -> [[String]] {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return expression.matches(in: text, range: range).map { match in
        (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}

func sourceFiles(in directory: URL, recursively: Bool = true) -> [URL] {
    guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
    let ignored: Set<String> = [".build", ".git", "DerivedData", "Pods", "Carthage", "SourcePackages"]
    var result: [URL] = []
    for case let url as URL in enumerator {
        if ignored.contains(url.lastPathComponent) { enumerator.skipDescendants(); continue }
        if url.pathExtension == "swift" { result.append(url) }
    }
    return result
}

func absoluteURL(_ path: String, relativeTo base: URL) -> URL {
    URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
}

func usage() {
    print("Usage: swift update_route_contracts.swift [--app-root <path>] [--output <path>] [--check]")
}

func configuration() throws -> (root: URL, output: URL, check: Bool) {
    let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    var root = workingDirectory
    var output = "RouteContracts.json"
    var check = false
    let arguments = Array(CommandLine.arguments.dropFirst())
    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--help", "-h": usage(); exit(0)
        case "--check": check = true
        case "--app-root", "--output":
            guard index + 1 < arguments.count else { throw NSError(domain: "RouteContracts", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing value for \(arguments[index])."]) }
            index += 1
            if arguments[index - 1] == "--app-root" { root = absoluteURL(arguments[index], relativeTo: workingDirectory) }
            else { output = arguments[index] }
        default: throw NSError(domain: "RouteContracts", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown option: \(arguments[index])."])
        }
        index += 1
    }
    return (root, absoluteURL(output, relativeTo: root), check)
}

func featureSources(at root: URL) -> [FeatureSource] {
    guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]) else { return [] }
    let ignored: Set<String> = [".build", ".git", "DerivedData", "Pods", "Carthage", "SourcePackages"]
    var packages: [URL] = []
    for case let url as URL in enumerator {
        if ignored.contains(url.lastPathComponent) { enumerator.skipDescendants(); continue }
        if url.lastPathComponent == "Package.swift" { packages.append(url.deletingLastPathComponent()) }
    }
    return packages.flatMap { packageURL -> [FeatureSource] in
        let sources = sourceFiles(in: packageURL.appendingPathComponent("Sources"))
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        let literalIDs = matches(#"RouteModule\(\s*id:\s*\"([^\"]+)\""#, in: sources).compactMap { $0.count > 1 ? $0[1] : nil }
        let declaredIDs = matches(#"(?:public\s+)?static\s+let\s+id\s*=\s*\"([^\"]+)\""#, in: sources).compactMap { $0.count > 1 ? $0[1] : nil }
        return Array(Set(literalIDs + declaredIDs)).map { FeatureSource(moduleID: $0, source: sources) }
    }
}

func routeNames(in source: String, moduleID: String) -> [(name: String?, routeID: String)] {
    let pattern = #"(?:(?:public\s+)?static\s+let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*)?ModuleRoute\(\s*moduleID:\s*(?:id|\""# + NSRegularExpression.escapedPattern(for: moduleID) + #"\")\s*,\s*routeID:\s*\"([^\"]+)\""#
    return matches(pattern, in: source).compactMap { match in
        guard match.count >= 3 else { return nil }
        return (match[1].isEmpty ? nil : match[1], match[2])
    }
}

func paths(in source: String, routeNames: [(name: String?, routeID: String)]) -> [String: String] {
    var result: [String: String] = [:]
    let idsByName = Dictionary(uniqueKeysWithValues: routeNames.compactMap { item in
        item.name.map { ($0, item.routeID) }
    })
    // Standard switch resolver: `case ["settings"]: return settings`.
    for match in matches(#"case\s*\[([^\]]*)\]\s*:\s*return\s+([A-Za-z_][A-Za-z0-9_]*)"#, in: source) where match.count >= 3 {
        guard let routeID = idsByName[match[2]] else { continue }
        let components = matches(#"\"([^\"]+)\""#, in: match[1]).compactMap { $0.count > 1 ? $0[1] : nil }
        result[routeID] = components.isEmpty ? "/" : "/" + components.joined(separator: "/")
    }
    // Standard guard resolver. Parameters are inferred from `parameters: ["id": link.pathComponents[1]]`.
    for route in routeNames where result[route.routeID] == nil {
        guard let occurrence = source.range(of: "routeID: \"\(route.routeID)\"") else { continue }
        let start = source.index(occurrence.lowerBound, offsetBy: -min(800, source.distance(from: source.startIndex, to: occurrence.lowerBound)))
        let end = source.index(occurrence.upperBound, offsetBy: min(400, source.distance(from: occurrence.upperBound, to: source.endIndex)))
        let context = String(source[start..<end])
        guard let countMatch = matches(#"link\.pathComponents\.count\s*==\s*(\d+)"#, in: context).last,
              countMatch.count > 1, let count = Int(countMatch[1]) else { continue }
        var components = Array(repeating: "{unknown}", count: count)
        for literal in matches(#"link\.pathComponents\[(\d+)\]\s*==\s*\"([^\"]+)\""#, in: context) where literal.count >= 3 {
            if let index = Int(literal[1]), index < count { components[index] = literal[2] }
        }
        for parameter in matches(#"\"([^\"]+)\"\s*:\s*link\.pathComponents\[(\d+)\]"#, in: context) where parameter.count >= 3 {
            if let index = Int(parameter[2]), index < count { components[index] = ":\(parameter[1])" }
        }
        guard !components.contains("{unknown}") else { continue }
        result[route.routeID] = "/" + components.joined(separator: "/")
    }
    return result
}

func urlMetadata(in source: String) -> [String: (presentations: [String], queryItems: [String], versions: [String])] {
    var result: [String: (presentations: [String], queryItems: [String], versions: [String])] = [:]
    for match in matches(#"https?://[^\"]+"#, in: source) where !match[0].isEmpty {
        let value = match[0].replacingOccurrences(of: #"\\\(([A-Za-z_][A-Za-z0-9_]*)\)"#, with: ":$1", options: .regularExpression)
        guard let queryStart = value.firstIndex(of: "?") else { continue }
        let beforeQuery = String(value[..<queryStart])
        guard let scheme = beforeQuery.range(of: "://") else { continue }
        let pathStart = beforeQuery[scheme.upperBound...].firstIndex(of: "/")
        let path = pathStart.map { String(beforeQuery[$0...]) } ?? "/"
        let pairs = String(value[value.index(after: queryStart)...]).split(separator: "&").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
        let queryItems = pairs.compactMap { $0.first }
        let presentations = pairs.filter { $0.first == "presentation" }.compactMap { $0.count > 1 ? $0[1] : nil }
        let versions = pairs.filter { $0.first == "version" }.compactMap { $0.count > 1 ? $0[1] : nil }
        guard !presentations.isEmpty else { continue }
        result[path] = (presentations, queryItems, versions)
    }
    return result
}

do {
    let config = try configuration()
    let allAppSource = sourceFiles(in: config.root).compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    var routes: [RouteContract] = []
    var versions = Set<String>()
    var failures: [String] = []

    for feature in featureSources(at: config.root) {
        let names = routeNames(in: feature.source, moduleID: feature.moduleID)
        let routePaths = paths(in: feature.source, routeNames: names)
        let metadata = urlMetadata(in: feature.source)
        for route in names {
            guard let path = routePaths[route.routeID] else { failures.append("Could not infer path for \(feature.moduleID)/\(route.routeID)."); continue }
            var details = metadata[path]
            // Tab routes commonly have no URL builder; infer them from an App-shell TabView tag.
            if details == nil, let name = route.name,
               allAppSource.contains(".tag(Optional(") && allAppSource.contains(".\(name))") {
                details = (["tab"], ["presentation", "version"], ["1"])
            }
            guard let details else { failures.append("Could not infer presentation/query parameters for \(feature.moduleID)/\(route.routeID)."); continue }
            versions.formUnion(details.versions)
            routes.append(RouteContract(moduleID: feature.moduleID, routeID: route.routeID, pathTemplate: path, presentations: Array(Set(details.presentations)).sorted(), requiredQueryItems: Array(Set(details.queryItems)).sorted()))
        }
    }
    guard failures.isEmpty else { throw NSError(domain: "RouteContracts", code: 1, userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "\n")]) }
    let manifest = RouteContractManifest(schemaVersion: 1, supportedVersions: versions.isEmpty ? ["1"] : versions.sorted(), routes: routes)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(manifest)
    if config.check {
        let current = try Data(contentsOf: config.output)
        guard current == data else { throw NSError(domain: "RouteContracts", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(config.output.path) is out of date. Run update_route_contracts.swift before building."]) }
        print("Route contracts are up to date (\(routes.count) routes).")
    } else {
        try fileManager.createDirectory(at: config.output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: config.output, options: .atomic)
        print("Updated \(config.output.path) (\(routes.count) routes).")
    }
} catch {
    fputs("Route contract update failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
