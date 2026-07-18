//
//  URLRouterTests.swift
//  URLRouterTests
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import XCTest
import SwiftUI
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

    func testRejectsInvalidLinkSecurityAndQueryContracts() throws {
        let cases: [(String, UniversalLinkError)] = [
            ("http://example.com/products", .unsupportedScheme),
            ("https://user:password@example.com/products", .credentialsAreNotAllowed),
            ("https://example.com:444/products", .unsupportedPort),
            ("https://example.com/products/%2F", .invalidPathEncoding),
            ("https://example.com/products?ref=one&ref=two", .duplicateQueryItem("ref")),
            ("https://example.com/products?ref", .missingQueryValue("ref"))
        ]

        for (string, expectedError) in cases {
            XCTAssertThrowsError(try UniversalLink(
                url: try XCTUnwrap(URL(string: string)),
                allowedHosts: ["example.com"]
            )) { error in
                XCTAssertEqual(error as? UniversalLinkError, expectedError)
            }
        }
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
    func testRegistryRejectsInvalidModuleConfiguration() throws {
        let duplicateRegistry = ModuleRouteRegistry(modules: [contentModule, contentModule])
        XCTAssertThrowsError(try duplicateRegistry.resolve(link("https://example.com/articles/42?presentation=push"))) { error in
            XCTAssertEqual(error as? ModuleRouteRegistryError, .duplicateModuleID("content"))
        }

        let mismatchedModule = RouteModule(id: "content") { _ in
            ModuleRoute(moduleID: "navigation", routeID: "settings")
        } destination: { _ in AnyView(EmptyView()) }
        let mismatchRegistry = ModuleRouteRegistry(modules: [mismatchedModule])
        XCTAssertThrowsError(try mismatchRegistry.resolve(link("https://example.com/articles/42?presentation=push"))) { error in
            XCTAssertEqual(
                error as? ModuleRouteRegistryError,
                .routeModuleMismatch(expected: "content", actual: "navigation")
            )
        }

        let missingDestinationModule = RouteModule(id: "content") { _ in
            ModuleRoute(moduleID: "content", routeID: "detail")
        } destination: { _ in nil }
        let missingDestinationRegistry = ModuleRouteRegistry(modules: [missingDestinationModule])
        XCTAssertThrowsError(try missingDestinationRegistry.resolve(link("https://example.com/articles/42?presentation=push"))) { error in
            XCTAssertEqual(
                error as? ModuleRouteRegistryError,
                .unavailableDestination(moduleID: "content", routeID: "detail")
            )
        }
    }

    @MainActor
    func testRegistryAllowsTabRoutesWithoutDestinations() throws {
        let tabModule = RouteModule(id: "navigation") { _ in
            ModuleRoute(moduleID: "navigation", routeID: "favorites")
        } destination: { _ in nil }
        let registry = ModuleRouteRegistry(modules: [tabModule])

        let resolved = try registry.resolve(link("https://example.com/favorites?presentation=tab"))
        XCTAssertEqual(resolved.route.routeID, "favorites")
        XCTAssertEqual(resolved.presentation, .tab)
    }

    @MainActor
    func testRoutePolicyEnforcesContractAndAccessGovernance() throws {
        let route = ModuleRoute(moduleID: "content", routeID: "detail")
        let presentation = ResolvedModuleRoute(route: route, presentation: .push)
        let unversioned = try link("https://example.com/articles/42?presentation=push")

        let strictPolicy = ModuleRoutePolicy(
            acceptedContractVersions: ["1"],
            allowsUnversionedLinks: false
        )
        XCTAssertThrowsError(try strictPolicy.validate(unversioned, presentation: presentation)) { error in
            XCTAssertEqual(error as? ModuleRoutePolicyError, .missingContractVersion(queryItem: "version"))
        }

        let unsupportedVersion = try link("https://example.com/articles/42?presentation=push&version=2")
        XCTAssertThrowsError(try strictPolicy.validate(unsupportedVersion, presentation: presentation)) { error in
            XCTAssertEqual(error as? ModuleRoutePolicyError, .unsupportedContractVersion("2"))
        }

        let disabledPolicy = ModuleRoutePolicy(isModuleEnabled: { _ in false })
        XCTAssertThrowsError(try disabledPolicy.validate(unversioned, presentation: presentation)) { error in
            XCTAssertEqual(error as? ModuleRoutePolicyError, .moduleDisabled("content"))
        }

        let unauthorizedPolicy = ModuleRoutePolicy(isAuthorized: { _, _ in false })
        XCTAssertThrowsError(try unauthorizedPolicy.validate(unversioned, presentation: presentation)) { error in
            XCTAssertEqual(
                error as? ModuleRoutePolicyError,
                .unauthorized(moduleID: "content", routeID: "detail")
            )
        }
    }

    @MainActor
    func testModuleRouterAppliesEveryPresentationStyle() {
        let router = ModuleRouter()
        let route = ModuleRoute(moduleID: "content", routeID: "article")

        router.apply(ResolvedModuleRoute(route: route, presentation: .push))
        XCTAssertEqual(router.path, [route])

        router.apply(ResolvedModuleRoute(route: route, presentation: .push))
        XCTAssertEqual(router.path, [route])

        router.apply(ResolvedModuleRoute(route: route, presentation: .tab))
        XCTAssertEqual(router.selectedTab, route)
        XCTAssertTrue(router.path.isEmpty)

        router.apply(ResolvedModuleRoute(route: route, presentation: .sheet))
        XCTAssertEqual(router.sheet, route)
        router.apply(ResolvedModuleRoute(route: route, presentation: .fullScreenCover))
        XCTAssertNil(router.sheet)
        XCTAssertEqual(router.fullScreenCover, route)
        router.apply(ResolvedModuleRoute(route: route, presentation: .push))
        XCTAssertNil(router.fullScreenCover)
        XCTAssertEqual(router.path, [route])
    }

    @MainActor
    private var contentModule: RouteModule {
        RouteModule(id: "content") { link in
            guard link.pathComponents.count == 2, link.pathComponents[0] == "articles" else { return nil }
            return ModuleRoute(moduleID: "content", routeID: "article", parameters: ["id": link.pathComponents[1]])
        } destination: { _ in AnyView(EmptyView()) }
    }

    @MainActor
    private var navigationModule: RouteModule {
        RouteModule(id: "navigation") { link in
            guard link.pathComponents == ["settings"] else { return nil }
            return ModuleRoute(moduleID: "navigation", routeID: "settings")
        } destination: { _ in AnyView(EmptyView()) }
    }

    private func link(_ string: String) throws -> UniversalLink {
        try UniversalLink(url: try XCTUnwrap(URL(string: string)), allowedHosts: ["example.com"])
    }
}
