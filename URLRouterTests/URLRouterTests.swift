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
    private enum TestRoute: Hashable, Sendable, UniversalLinkRoute {
        case home, product(id: String), settings

        static func presentation(for link: UniversalLink) throws -> RoutePresentation<TestRoute> {
            if link.pathComponents.isEmpty { return .selectTab(.home) }
            if link.pathComponents.count == 2,
               link.pathComponents[0] == "products",
               !link.pathComponents[1].isEmpty {
                return .push(.product(id: link.pathComponents[1]))
            }
            if link.pathComponents == ["settings"] { return .sheet(.settings) }
            throw UniversalLinkError.unsupportedRoute
        }
    }

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
        let link = try UniversalLink(
            url: try XCTUnwrap(URL(string: "https://example.com/products")),
            allowedHosts: ["example.com"]
        )
        XCTAssertThrowsError(try TestRoute.presentation(for: link))
    }

    @MainActor
    func testRouterOwnsPushAndPresentationState() throws {
        let router = AppRouter<TestRoute>()
        try router.handle(
            universalLink: try XCTUnwrap(URL(string: "https://example.com/products/sku-42")),
            allowedHosts: ["example.com"]
        )
        XCTAssertEqual(router.path, [.product(id: "sku-42")])
        router.apply(.sheet(.settings))
        XCTAssertEqual(router.sheet, .settings)
        router.dismissSheet()
        XCTAssertNil(router.sheet)
    }
}
