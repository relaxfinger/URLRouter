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
}
