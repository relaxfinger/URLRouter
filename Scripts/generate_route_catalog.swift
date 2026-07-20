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

struct FeaturePackage {
    let name: String
    let path: String
    let moduleIDs: Set<String>
    let destinations: [String: String]
}

struct CatalogRoute {
    let contract: RouteContract
    let feature: FeaturePackage?
    let destination: String
}

let fileManager = FileManager.default

struct Configuration {
    let appRoot: URL
    let contractsURL: URL
    let outputURL: URL
}

func absoluteURL(_ path: String, relativeTo base: URL) -> URL {
    URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
}

func configuration(arguments: [String]) throws -> Configuration {
    let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    var appRoot = workingDirectory
    var contractsPath = "RouteContracts.json"
    var outputPath = "docs/route-catalog.html"
    var index = 0

    while index < arguments.count {
        let option = arguments[index]
        if option == "--help" || option == "-h" {
            print("Usage: swift generate_route_catalog.swift [--app-root <path>] [--contracts <path>] [--output <path>]")
            exit(0)
        }
        guard ["--app-root", "--contracts", "--output"].contains(option), index + 1 < arguments.count else {
            throw NSError(domain: "RouteCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown or incomplete option: \(option). Use --help for usage."])
        }
        index += 1
        switch option {
        case "--app-root": appRoot = absoluteURL(arguments[index], relativeTo: workingDirectory)
        case "--contracts": contractsPath = arguments[index]
        case "--output": outputPath = arguments[index]
        default: break
        }
        index += 1
    }

    return Configuration(
        appRoot: appRoot,
        contractsURL: absoluteURL(contractsPath, relativeTo: appRoot),
        outputURL: absoluteURL(outputPath, relativeTo: appRoot)
    )
}

func contents(of path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

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

func html(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

func swiftFiles(in directory: URL) -> [URL] {
    guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
        return []
    }
    return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
}

func destinationMap(in source: String) -> [String: String] {
    var result: [String: String] = [:]
    // Handles `guard route.routeID == "detail" ... return AnyView(DetailView(...))`.
    for match in matches(#"route\.routeID\s*==\s*\"([^\"]+)\"[\s\S]{0,400}?AnyView\(\s*([A-Za-z_][A-Za-z0-9_]*)"#, in: source) where match.count >= 3 {
        result[match[1]] = match[2]
    }
    // Handles `case "settings": AnyView(SettingsView())` in a destination switch.
    for match in matches(#"case\s+\"([^\"]+)\"\s*:\s*(?:return\s+)?AnyView\(\s*([A-Za-z_][A-Za-z0-9_]*)"#, in: source) where match.count >= 3 {
        result[match[1]] = match[2]
    }
    return result
}

func featurePackages(at root: URL) -> [FeaturePackage] {
    let ignoredDirectories: Set<String> = [".build", ".git", "DerivedData", "Pods", "Carthage", "SourcePackages"]
    guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]) else {
        return []
    }

    var packageURLs: [URL] = []
    for case let url as URL in enumerator {
        if ignoredDirectories.contains(url.lastPathComponent) {
            enumerator.skipDescendants()
            continue
        }
        if url.lastPathComponent == "Package.swift" {
            packageURLs.append(url.deletingLastPathComponent())
        }
    }

    return packageURLs.compactMap { packageURL -> FeaturePackage? in
            let packageManifest = packageURL.appendingPathComponent("Package.swift")
            guard let packageText = try? contents(of: packageManifest.path) else { return nil }
            let name = matches(#"name:\s*\"([^\"]+)\""#, in: packageText).first?[1] ?? packageURL.lastPathComponent
            // A package may contain other local packages. Only inspect its own Sources directory.
            let sourceDirectory = packageURL.appendingPathComponent("Sources", isDirectory: true)
            let source = swiftFiles(in: sourceDirectory).compactMap { try? contents(of: $0.path) }.joined(separator: "\n")
            let literalIDs = matches(#"RouteModule\(\s*id:\s*\"([^\"]+)\""#, in: source).compactMap { $0.count > 1 ? $0[1] : nil }
            let declaredIDs = matches(#"(?:public\s+)?static\s+let\s+id\s*=\s*\"([^\"]+)\""#, in: source).compactMap { $0.count > 1 ? $0[1] : nil }
            let moduleIDs = Set(literalIDs + declaredIDs)
            // Only packages that declare a RouteModule are Feature packages for this catalog.
            guard !moduleIDs.isEmpty else { return nil }
            return FeaturePackage(name: name, path: packageURL.path, moduleIDs: moduleIDs, destinations: destinationMap(in: source))
    }
}

func sampleURL(for route: RouteContract, versions: [String]) -> String {
    let path = route.pathTemplate.replacingOccurrences(of: #":([A-Za-z][A-Za-z0-9_]*)"#, with: "{$1}", options: .regularExpression)
    let queryItems = route.requiredQueryItems.map { item -> String in
        switch item {
        case "presentation": return "presentation=" + (route.presentations.first ?? "{presentation}")
        case "version": return "version=" + (versions.first ?? "{version}")
        default: return "\(item)={\(item)}"
        }
    }
    return "https://example.com\(path)" + (queryItems.isEmpty ? "" : "?" + queryItems.joined(separator: "&"))
}

func parameters(for route: RouteContract) -> String {
    let pathParameters = matches(#":([A-Za-z][A-Za-z0-9_]*)"#, in: route.pathTemplate).compactMap { $0.count > 1 ? "\($0[1])（路径）" : nil }
    let queryParameters = route.requiredQueryItems.map { "\($0)（查询，必填）" }
    return (pathParameters + queryParameters).joined(separator: "<br>")
}

do {
    let configuration = try configuration(arguments: Array(CommandLine.arguments.dropFirst()))
    let manifestData = try Data(contentsOf: configuration.contractsURL)
    let manifest = try JSONDecoder().decode(RouteContractManifest.self, from: manifestData)
    guard manifest.schemaVersion == 1 else { throw NSError(domain: "RouteCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported route contract schema version."]) }

    let features = featurePackages(at: configuration.appRoot)
    let catalog = manifest.routes.map { route -> CatalogRoute in
        let feature = features.first { $0.moduleIDs.contains(route.moduleID) }
        let destination = feature?.destinations[route.routeID] ?? "由 App 容器处理（Feature 未提供 destination View）"
        return CatalogRoute(contract: route, feature: feature, destination: destination)
    }

    let rows = catalog.map { item in
        let route = item.contract
        return """
        <tr>
          <td><code>\(html(sampleURL(for: route, versions: manifest.supportedVersions)))</code></td>
          <td>\(parameters(for: route))</td>
          <td><code>\(html(item.destination))</code></td>
          <td>\(html(item.feature?.name ?? "未找到对应 Feature package"))</td>
          <td><code>\(html(route.moduleID))/\(html(route.routeID))</code></td>
          <td>\(html(route.presentations.joined(separator: "、")))</td>
        </tr>
        """
    }.joined(separator: "\n")

    let page = """
    <!doctype html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>URLRouter 路由目录</title>
      <style>
        :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
        body { margin: 40px auto; max-width: 1440px; padding: 0 24px; line-height: 1.5; }
        h1 { margin-bottom: 4px; } .meta { color: #6b7280; margin-top: 0; }
        input { box-sizing: border-box; width: 100%; padding: 11px; margin: 20px 0; font: inherit; border: 1px solid #9ca3af; border-radius: 8px; }
        table { width: 100%; border-collapse: collapse; } th, td { padding: 12px; text-align: left; vertical-align: top; border-bottom: 1px solid #d1d5db; }
        th { position: sticky; top: 0; background: Canvas; } code { font-size: .9em; word-break: break-word; }
        @media (max-width: 800px) { body { margin-top: 20px; padding: 0 12px; } table { font-size: .9rem; } th, td { min-width: 130px; } }
      </style>
    </head>
    <body>
      <h1>URLRouter 路由目录</h1>
      <p class="meta">由 <code>\(html(configuration.contractsURL.lastPathComponent))</code> 与 App 内的 Feature Package 自动生成 · 共 \(catalog.count) 条路由</p>
      <input id="filter" type="search" placeholder="筛选 URL、参数、页面或 Feature package…" autofocus>
      <table>
        <thead><tr><th>URL 模板</th><th>参数</th><th>目标页面</th><th>Feature package</th><th>路由 ID</th><th>展示方式</th></tr></thead>
        <tbody>\(rows)</tbody>
      </table>
      <script>
        const filter = document.querySelector('#filter');
        filter.addEventListener('input', () => document.querySelectorAll('tbody tr').forEach(row => {
          row.hidden = !row.innerText.toLowerCase().includes(filter.value.toLowerCase());
        }));
      </script>
    </body>
    </html>
    """

    try fileManager.createDirectory(at: configuration.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try page.write(to: configuration.outputURL, atomically: true, encoding: .utf8)
    print("Generated \(configuration.outputURL.path) (\(catalog.count) routes across \(features.count) Feature packages).")
} catch {
    fputs("Route catalog generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
