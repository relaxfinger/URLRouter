//
//  URLRouterTests.swift
//  URLRouterTests
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import URLRouter

final class URLRouterTests: XCTestCase {

    func testParsesTrustedProductUniversalLink() throws {
        let link = try UniversalLink(
            url: try XCTUnwrap(URL(string: "https://example.com/products/sku-42?ref=mail")),
            allowedHosts: ["example.com"]
        )
        XCTAssertEqual(link.host, "example.com")
        XCTAssertEqual(link.pathComponents, ["products", "sku-42"])
        XCTAssertEqual(link.query, ["ref": "mail"])
    }

    func testRejectsPartialPathAndUntrustedHost() throws {
        XCTAssertThrowsError(try UniversalLink(
            url: try XCTUnwrap(URL(string: "https://evil.example/products/sku-42")),
            allowedHosts: ["example.com"]
        ))
        XCTAssertThrowsError(try UniversalLink(
            url: try XCTUnwrap(URL(string: "https://example.com/products#fragment")),
            allowedHosts: ["example.com"]
        ))
    }

    @MainActor
    func testModuleRouteCarriesFeatureIdentityAndParameters() {
        let route = ModuleRoute(moduleID: "products", routeID: "detail", parameters: ["id": "sku-42"])
        XCTAssertEqual(route.moduleID, "products")
        XCTAssertEqual(route.parameters["id"], "sku-42")
    }

    @MainActor
    func testRegistryResolvesRoutesFromDifferentFeatureModules() throws {
        let registry = ModuleRouteRegistry(modules: [contentModule, navigationModule])

        let article = try registry.resolve(link("https://example.com/articles/42?presentation=push"))
        XCTAssertEqual(article.route.moduleID, "content")
        XCTAssertEqual(article.route.parameters["id"], "42")
        XCTAssertEqual(article.presentation, .push)

        let settings = try registry.resolve(link("https://example.com/settings?presentation=sheet"))
        XCTAssertEqual(settings.route.moduleID, "navigation")
        XCTAssertEqual(settings.presentation, .sheet)
    }

    @MainActor
    func testRegistryRejectsMissingOrUnsupportedPresentation() throws {
        let registry = ModuleRouteRegistry(modules: [contentModule])
        XCTAssertThrowsError(try registry.resolve(link("https://example.com/articles/42")))
        XCTAssertThrowsError(try registry.resolve(link("https://example.com/articles/42?presentation=modal")))
    }

    @MainActor
    func testModuleRouterAppliesEveryPresentationStyle() {
        let router = ModuleRouter()
        let route = ModuleRoute(moduleID: "content", routeID: "article")

        router.apply(ResolvedModuleRoute(route: route, presentation: .push))
        XCTAssertEqual(router.path, [route])

        router.apply(ResolvedModuleRoute(route: route, presentation: .tab))
        XCTAssertEqual(router.selectedTab, route)
        XCTAssertTrue(router.path.isEmpty)

        router.apply(ResolvedModuleRoute(route: route, presentation: .sheet))
        XCTAssertEqual(router.sheet, route)
        router.dismissSheet()
        XCTAssertNil(router.sheet)

        router.apply(ResolvedModuleRoute(route: route, presentation: .fullScreenCover))
        XCTAssertEqual(router.fullScreenCover, route)
        router.dismissFullScreenCover()
        XCTAssertNil(router.fullScreenCover)
    }

    @MainActor
    private var contentModule: RouteModule {
        RouteModule(id: "content") { link in
            guard link.pathComponents.count == 2, link.pathComponents[0] == "articles" else { return nil }
            return ModuleRoute(moduleID: "content", routeID: "article", parameters: ["id": link.pathComponents[1]])
        } destination: { _ in nil }
    }

    @MainActor
    private var navigationModule: RouteModule {
        RouteModule(id: "navigation") { link in
            guard link.pathComponents == ["settings"] else { return nil }
            return ModuleRoute(moduleID: "navigation", routeID: "settings")
        } destination: { _ in nil }
    }

    private func link(_ string: String) throws -> UniversalLink {
        try UniversalLink(url: try XCTUnwrap(URL(string: string)), allowedHosts: ["example.com"])
    }
}
