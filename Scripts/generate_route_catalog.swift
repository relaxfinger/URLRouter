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

/// Creates the App-root contract on first use so generating the catalog has no
/// manual bootstrap step. Subsequent runs only read the tracked contract.
func createInitialContractIfNeeded(configuration: Configuration) throws {
    guard !fileManager.fileExists(atPath: configuration.contractsURL.path) else { return }
    let scriptsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let updateScript = scriptsDirectory.appendingPathComponent("update_route_contracts.swift")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "swift", updateScript.path,
        "--app-root", configuration.appRoot.path,
        "--output", configuration.contractsURL.path
    ]
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "SDKROOT")
    process.environment = environment
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "RouteCatalog",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "Could not create the initial contract at \(configuration.contractsURL.path)."]
        )
    }
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

func packageRoots(at root: URL) -> [URL] {
    let ignoredDirectories: Set<String> = [".build", ".git", "DerivedData", "Pods", "Carthage", "SourcePackages"]
    guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]) else {
        return []
    }
    var roots: [URL] = []
    for case let url as URL in enumerator {
        if ignoredDirectories.contains(url.lastPathComponent) {
            enumerator.skipDescendants()
            continue
        }
        if url.lastPathComponent == "Package.swift" {
            roots.append(url.deletingLastPathComponent().standardizedFileURL)
        }
    }
    return roots
}

func appSource(in root: URL, excluding packageRoots: [URL]) -> String {
    let ignoredDirectories: Set<String> = [".build", ".git", "DerivedData", "Pods", "Carthage", "SourcePackages", "Tests", "UITests"]
    let nestedPackageRoots = Set(packageRoots.filter { $0 != root.standardizedFileURL }.map(\.path))
    guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]) else {
        return ""
    }
    var sources: [String] = []
    for case let url as URL in enumerator {
        if ignoredDirectories.contains(url.lastPathComponent) || nestedPackageRoots.contains(url.path) {
            enumerator.skipDescendants()
            continue
        }
        if url.pathExtension == "swift", let source = try? contents(of: url.path) {
            sources.append(source)
        }
    }
    return sources.joined(separator: "\n")
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
    packageRoots(at: root).filter { $0 != root.standardizedFileURL }.compactMap { packageURL -> FeaturePackage? in
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

func featureName(for item: CatalogRoute) -> String {
    item.feature?.name ?? "未找到对应 Feature package"
}

func anchorID(for featureName: String) -> String {
    let slug = featureName.lowercased().map { character -> String in
        character.isLetter || character.isNumber ? String(character) : "-"
    }.joined()
    return "feature-" + slug.replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
}

do {
    let configuration = try configuration(arguments: Array(CommandLine.arguments.dropFirst()))
    try createInitialContractIfNeeded(configuration: configuration)
    let manifestData = try Data(contentsOf: configuration.contractsURL)
    let manifest = try JSONDecoder().decode(RouteContractManifest.self, from: manifestData)
    guard manifest.schemaVersion == 1 else { throw NSError(domain: "RouteCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported route contract schema version."]) }

    let features = featurePackages(at: configuration.appRoot)
    let appSourceText = appSource(in: configuration.appRoot, excluding: packageRoots(at: configuration.appRoot))
    let appModuleIDs = Set(
        matches(#"RouteModule\(\s*id:\s*\"([^\"]+)\""#, in: appSourceText).compactMap { $0.count > 1 ? $0[1] : nil }
        + matches(#"(?:public\s+)?static\s+let\s+id\s*=\s*\"([^\"]+)\""#, in: appSourceText).compactMap { $0.count > 1 ? $0[1] : nil }
    )
    let appFeature = appModuleIDs.isEmpty ? nil : FeaturePackage(
        name: "App",
        path: configuration.appRoot.path,
        moduleIDs: appModuleIDs,
        destinations: destinationMap(in: appSourceText)
    )
    let catalogFeatures = features + (appFeature.map { [$0] } ?? [])
    let catalog = manifest.routes.map { route -> CatalogRoute in
        let feature = catalogFeatures.first { $0.moduleIDs.contains(route.moduleID) }
        let destination = feature?.destinations[route.routeID] ?? "由 App 容器处理（Feature 未提供 destination View）"
        return CatalogRoute(contract: route, feature: feature, destination: destination)
    }

    let groupedCatalog = Dictionary(grouping: catalog, by: featureName(for:))
    let orderedFeatureNames = groupedCatalog.keys.sorted { left, right in
        if left == "未找到对应 Feature package" { return false }
        if right == "未找到对应 Feature package" { return true }
        return left.localizedStandardCompare(right) == .orderedAscending
    }

    let featureNavigation = orderedFeatureNames.compactMap { name -> String? in
        guard let routes = groupedCatalog[name] else { return nil }
        return "<a class=\"feature-link\" href=\"#\(html(anchorID(for: name)))\"><span>\(html(name))</span><b>\(routes.count)</b></a>"
    }.joined(separator: "\n        ")

    let sections = orderedFeatureNames.compactMap { name -> String? in
        guard let routes = groupedCatalog[name] else { return nil }
        let rows = routes.sorted { $0.contract.pathTemplate < $1.contract.pathTemplate }.map { item in
            let route = item.contract
            return """
            <tr>
              <td><code>\(html(sampleURL(for: route, versions: manifest.supportedVersions)))</code></td>
              <td>\(parameters(for: route))</td>
              <td><code>\(html(item.destination))</code></td>
              <td><code>\(html(route.moduleID))/\(html(route.routeID))</code></td>
              <td><span class=\"presentation\">\(html(route.presentations.joined(separator: "、")))</span></td>
            </tr>
            """
        }.joined(separator: "\n")
        return """
        <section class=\"feature-section\" id=\"\(html(anchorID(for: name)))\" data-feature=\"\(html(name))\">
          <div class=\"feature-heading\">
            <div><p class=\"eyebrow\">FEATURE PACKAGE</p><h2>\(html(name))</h2></div>
            <span class=\"route-count\">\(routes.count) 条路由</span>
          </div>
          <div class=\"table-wrap\">
            <table>
              <thead><tr><th>URL 模板</th><th>参数</th><th>目标页面</th><th>路由 ID</th><th>展示方式</th></tr></thead>
              <tbody>\(rows)</tbody>
            </table>
          </div>
        </section>
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
        * { box-sizing: border-box; } body { margin: 0; background: Canvas; color: CanvasText; line-height: 1.5; }
        header { padding: 48px max(24px, calc((100vw - 1320px) / 2)); border-bottom: 1px solid color-mix(in srgb, CanvasText 16%, transparent); background: color-mix(in srgb, AccentColor 7%, Canvas); }
        h1 { margin: 0 0 4px; font-size: clamp(2rem, 5vw, 3.2rem); letter-spacing: -.04em; } .meta { color: color-mix(in srgb, CanvasText 60%, transparent); margin: 0; }
        main { max-width: 1320px; margin: 0 auto; padding: 28px 24px 72px; }
        .search { position: sticky; top: 0; z-index: 2; padding: 16px 0; background: Canvas; } input { width: 100%; padding: 13px 16px; font: inherit; border: 1px solid color-mix(in srgb, CanvasText 28%, transparent); border-radius: 10px; background: Canvas; color: CanvasText; box-shadow: 0 4px 18px color-mix(in srgb, CanvasText 7%, transparent); }
        .feature-nav { display: flex; flex-wrap: wrap; gap: 8px; margin: 8px 0 30px; } .feature-link { display: inline-flex; gap: 9px; align-items: center; padding: 7px 10px 7px 12px; color: inherit; text-decoration: none; border: 1px solid color-mix(in srgb, CanvasText 17%, transparent); border-radius: 999px; } .feature-link:hover { border-color: AccentColor; } .feature-link b { min-width: 21px; padding: 1px 6px; text-align: center; border-radius: 99px; background: color-mix(in srgb, AccentColor 18%, transparent); font-size: .8em; }
        .feature-section { scroll-margin-top: 84px; margin: 0 0 30px; padding: 22px; border: 1px solid color-mix(in srgb, CanvasText 14%, transparent); border-radius: 16px; background: color-mix(in srgb, CanvasText 2%, Canvas); box-shadow: 0 10px 30px color-mix(in srgb, CanvasText 4%, transparent); } .feature-heading { display: flex; justify-content: space-between; align-items: flex-start; gap: 16px; margin-bottom: 18px; } h2 { margin: 0; font-size: 1.35rem; } .eyebrow { margin: 0 0 3px; font-size: .72rem; letter-spacing: .12em; color: color-mix(in srgb, CanvasText 55%, transparent); } .route-count, .presentation { display: inline-block; padding: 3px 8px; border-radius: 6px; background: color-mix(in srgb, AccentColor 15%, transparent); font-size: .84rem; white-space: nowrap; }
        .table-wrap { overflow-x: auto; } table { width: 100%; min-width: 850px; border-collapse: collapse; } th, td { padding: 12px; text-align: left; vertical-align: top; border-bottom: 1px solid color-mix(in srgb, CanvasText 12%, transparent); } th { font-size: .78rem; letter-spacing: .04em; color: color-mix(in srgb, CanvasText 62%, transparent); } tr:last-child td { border-bottom: 0; } code { font-size: .88em; word-break: break-word; } .empty { display: none; margin: 32px 0; padding: 24px; text-align: center; border: 1px dashed color-mix(in srgb, CanvasText 30%, transparent); border-radius: 12px; color: color-mix(in srgb, CanvasText 65%, transparent); }
        @media (max-width: 800px) { header { padding-top: 30px; padding-bottom: 30px; } main { padding: 18px 12px 48px; } .feature-section { padding: 16px; } .feature-heading { align-items: center; } }
      </style>
    </head>
    <body>
      <header>
        <h1>URLRouter 路由目录</h1>
        <p class="meta">由 <code>\(html(configuration.contractsURL.lastPathComponent))</code> 与 App 内的 Feature Package 自动生成 · 共 \(catalog.count) 条路由，分属 \(orderedFeatureNames.count) 个 Feature</p>
      </header>
      <main>
        <div class="search"><input id="filter" type="search" placeholder="筛选 Feature、URL、参数、页面或路由 ID…" autofocus></div>
        <nav class="feature-nav" aria-label="Feature package 快速定位">\(featureNavigation)</nav>
        <p id="empty" class="empty">没有匹配的路由或 Feature package。</p>
        \(sections)
      </main>
      <script>
        const filter = document.querySelector('#filter');
        const sections = [...document.querySelectorAll('.feature-section')];
        const links = [...document.querySelectorAll('.feature-link')];
        const empty = document.querySelector('#empty');
        filter.addEventListener('input', () => {
          const query = filter.value.trim().toLowerCase();
          let visibleSections = 0;
          sections.forEach(section => {
            const featureMatches = section.dataset.feature.toLowerCase().includes(query);
            const rows = [...section.querySelectorAll('tbody tr')];
            let visibleRows = 0;
            rows.forEach(row => { row.hidden = !featureMatches && !row.innerText.toLowerCase().includes(query); if (!row.hidden) visibleRows += 1; });
            section.hidden = visibleRows === 0;
            if (!section.hidden) visibleSections += 1;
          });
          links.forEach(link => { link.hidden = document.querySelector(link.getAttribute('href')).hidden; });
          empty.style.display = visibleSections ? 'none' : 'block';
        });
      </script>
    </body>
    </html>
    """

    try fileManager.createDirectory(at: configuration.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try page.write(to: configuration.outputURL, atomically: true, encoding: .utf8)
    print("Generated \(configuration.outputURL.path) (\(catalog.count) routes across \(features.count) Feature packages\(appFeature == nil ? "" : " plus App")).")
} catch {
    fputs("Route catalog generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
