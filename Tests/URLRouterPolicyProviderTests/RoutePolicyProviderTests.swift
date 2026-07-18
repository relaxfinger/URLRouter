//
//  RoutePolicyProviderTests.swift
//  URLRouterPolicyProviderTests
//

import XCTest
import URLRouter
@testable import URLRouterPolicyProvider

final class RoutePolicyProviderTests: XCTestCase {
    @MainActor
    func testBootstrapUsesVerifiedStaleCacheDuringAnOutage() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let cachedPolicy = ModuleRouteRemotePolicy(disabledModuleIDs: ["content"])
        let cache = InMemoryRoutePolicyCache(entry: RoutePolicyCacheEntry(
            policy: cachedPolicy,
            fetchedAt: now.addingTimeInterval(-2 * 60 * 60),
            expiresAt: now.addingTimeInterval(-60 * 60)
        ))
        let store = ModuleRoutePolicyStore()
        let provider = RoutePolicyProvider(
            store: store,
            source: FailingSource(),
            cache: cache,
            strategy: RoutePolicyRefreshStrategy(
                refreshInterval: 30 * 60,
                cacheTimeToLive: 60 * 60,
                maximumStaleAge: 24 * 60 * 60
            ),
            now: { now }
        )

        let bootstrapResult = await provider.bootstrap()
        XCTAssertEqual(bootstrapResult, .staleCache)
        XCTAssertEqual(store.remotePolicy, cachedPolicy)
        let refreshResult = await provider.refresh()
        XCTAssertEqual(refreshResult, .failed(.remoteFetch))
        XCTAssertEqual(store.remotePolicy, cachedPolicy)
    }

    @MainActor
    func testRefreshValidatesPersistsAndAtomicallyAppliesPolicy() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let remotePolicy = ModuleRouteRemotePolicy(isCircuitBreakerOpen: true)
        let cache = InMemoryRoutePolicyCache()
        let store = ModuleRoutePolicyStore()
        let provider = RoutePolicyProvider(
            store: store,
            source: StaticSource(data: try JSONEncoder().encode(remotePolicy)),
            cache: cache,
            now: { now }
        )

        let refreshResult = await provider.refresh()
        XCTAssertEqual(refreshResult, .updated)
        XCTAssertEqual(store.remotePolicy, remotePolicy)
        let cachedPolicy = await cache.load()?.policy
        XCTAssertEqual(cachedPolicy, remotePolicy)
        let skippedResult = await provider.refreshIfNeeded()
        XCTAssertEqual(skippedResult, .skipped)
    }

    @MainActor
    func testInvalidPayloadDoesNotReplaceCurrentPolicy() async {
        let existingPolicy = ModuleRouteRemotePolicy(disabledModuleIDs: ["content"])
        let store = ModuleRoutePolicyStore(remotePolicy: existingPolicy)
        let provider = RoutePolicyProvider(
            store: store,
            source: StaticSource(data: Data("not-json".utf8)),
            cache: InMemoryRoutePolicyCache()
        )

        let refreshResult = await provider.refresh()
        XCTAssertEqual(refreshResult, .failed(.payloadValidation))
        XCTAssertEqual(store.remotePolicy, existingPolicy)
    }
}

private struct StaticSource: RoutePolicyRemoteSource {
    let data: Data

    func fetchPolicyData() async throws -> Data { data }
}

private struct FailingSource: RoutePolicyRemoteSource {
    func fetchPolicyData() async throws -> Data { throw Failure() }

    private struct Failure: Error {}
}
