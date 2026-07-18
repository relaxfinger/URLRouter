//
//  RoutePolicyProvider.swift
//  URLRouterPolicyProvider
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import Foundation
import URLRouter

/// Supplies trusted policy bytes from an app-specific backend or remote-config SDK.
///
/// The source owns transport, authentication, and retry details. Keep vendor SDKs
/// in the app target rather than coupling them to this package.
public protocol RoutePolicyRemoteSource: Sendable {
    func fetchPolicyData() async throws -> Data
}

/// Turns a trusted policy payload into the router's remote restrictions.
///
/// Implement this protocol when a backend uses a signed envelope or another
/// schema. The default validator decodes a `ModuleRouteRemotePolicy` JSON value.
public protocol RoutePolicyPayloadValidating: Sendable {
    func validatePolicyPayload(_ data: Data) throws -> ModuleRouteRemotePolicy
}

/// The default JSON payload validator.
public struct JSONRoutePolicyPayloadValidator: RoutePolicyPayloadValidating {
    public init() {}

    public func validatePolicyPayload(_ data: Data) throws -> ModuleRouteRemotePolicy {
        try JSONDecoder().decode(ModuleRouteRemotePolicy.self, from: data)
    }
}

/// A persisted, previously validated remote policy.
public struct RoutePolicyCacheEntry: Codable, Equatable, Sendable {
    public let policy: ModuleRouteRemotePolicy
    public let fetchedAt: Date
    public let expiresAt: Date

    public init(policy: ModuleRouteRemotePolicy, fetchedAt: Date, expiresAt: Date) {
        self.policy = policy
        self.fetchedAt = fetchedAt
        self.expiresAt = expiresAt
    }
}

/// Persists only policies that have already passed payload validation.
public protocol RoutePolicyCaching: Sendable {
    func load() async throws -> RoutePolicyCacheEntry?
    func save(_ entry: RoutePolicyCacheEntry) async throws
}

/// An in-memory cache for previews, tests, and apps that supply their own persistence.
public actor InMemoryRoutePolicyCache: RoutePolicyCaching {
    private var entry: RoutePolicyCacheEntry?

    public init(entry: RoutePolicyCacheEntry? = nil) {
        self.entry = entry
    }

    public func load() -> RoutePolicyCacheEntry? { entry }

    public func save(_ entry: RoutePolicyCacheEntry) {
        self.entry = entry
    }
}

/// A small JSON file cache. Create it in the app's Application Support directory.
public actor FileRoutePolicyCache: RoutePolicyCaching {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> RoutePolicyCacheEntry? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(RoutePolicyCacheEntry.self, from: Data(contentsOf: url))
    }

    public func save(_ entry: RoutePolicyCacheEntry) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(entry).write(to: url, options: .atomic)
    }
}

/// Recommended timing and fallback bounds for policy refreshes.
public struct RoutePolicyRefreshStrategy: Sendable {
    /// Refresh when the app returns to the foreground after this interval.
    public let refreshInterval: TimeInterval
    /// Freshly fetched policies remain valid in the normal cache window.
    public let cacheTimeToLive: TimeInterval
    /// A verified policy may be used during an outage for at most this long.
    public let maximumStaleAge: TimeInterval

    public init(
        refreshInterval: TimeInterval = 30 * 60,
        cacheTimeToLive: TimeInterval = 60 * 60,
        maximumStaleAge: TimeInterval = 24 * 60 * 60
    ) {
        precondition(refreshInterval > 0 && cacheTimeToLive > 0 && maximumStaleAge >= cacheTimeToLive)
        self.refreshInterval = refreshInterval
        self.cacheTimeToLive = cacheTimeToLive
        self.maximumStaleAge = maximumStaleAge
    }

    /// A sensible default: refresh on foreground after 30 minutes, retain a
    /// verified policy for an hour, and permit outage fallback for up to a day.
    public static let standard = RoutePolicyRefreshStrategy()
}

public enum RoutePolicyBootstrapResult: Equatable, Sendable {
    case freshCache
    case staleCache
    case localFallback
}

public enum RoutePolicyRefreshResult: Equatable, Sendable {
    case updated
    case skipped
    case failed(RoutePolicyRefreshFailure)
}

public enum RoutePolicyRefreshFailure: String, Equatable, Sendable {
    case remoteFetch
    case payloadValidation
    case cacheWrite
}

/// Coordinates cache-first startup and non-blocking policy refreshes.
///
/// Call `bootstrap()` before installing or immediately after installing the
/// router, then call `refresh()` in a background task at cold start. Call
/// `refreshIfNeeded()` when returning to the foreground. Failed refreshes keep
/// the last verified policy; policies older than `maximumStaleAge` are ignored.
@MainActor
public final class RoutePolicyProvider {
    private let store: ModuleRoutePolicyStore
    private let source: any RoutePolicyRemoteSource
    private let validator: any RoutePolicyPayloadValidating
    private let cache: any RoutePolicyCaching
    private let strategy: RoutePolicyRefreshStrategy
    private let now: @Sendable () -> Date
    private var currentEntry: RoutePolicyCacheEntry?

    public init(
        store: ModuleRoutePolicyStore,
        source: any RoutePolicyRemoteSource,
        validator: any RoutePolicyPayloadValidating = JSONRoutePolicyPayloadValidator(),
        cache: any RoutePolicyCaching,
        strategy: RoutePolicyRefreshStrategy = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.source = source
        self.validator = validator
        self.cache = cache
        self.strategy = strategy
        self.now = now
    }

    /// Restores the newest verified cache without waiting for the network.
    @discardableResult
    public func bootstrap() async -> RoutePolicyBootstrapResult {
        guard let entry = try? await cache.load() else { return .localFallback }
        let age = now().timeIntervalSince(entry.fetchedAt)
        guard age <= strategy.maximumStaleAge else { return .localFallback }

        currentEntry = entry
        store.replaceRemotePolicy(with: entry.policy)
        return now() <= entry.expiresAt ? .freshCache : .staleCache
    }

    /// Refreshes only after the configured foreground interval.
    @discardableResult
    public func refreshIfNeeded() async -> RoutePolicyRefreshResult {
        if let currentEntry,
           now().timeIntervalSince(currentEntry.fetchedAt) < strategy.refreshInterval {
            return .skipped
        }
        return await refresh()
    }

    /// Fetches, validates, atomically applies, and persists a new policy.
    @discardableResult
    public func refresh() async -> RoutePolicyRefreshResult {
        let data: Data
        do {
            data = try await source.fetchPolicyData()
        } catch {
            return .failed(.remoteFetch)
        }

        let policy: ModuleRouteRemotePolicy
        do {
            policy = try validator.validatePolicyPayload(data)
        } catch {
            return .failed(.payloadValidation)
        }

        let fetchedAt = now()
        let entry = RoutePolicyCacheEntry(
            policy: policy,
            fetchedAt: fetchedAt,
            expiresAt: fetchedAt.addingTimeInterval(strategy.cacheTimeToLive)
        )
        do {
            try await cache.save(entry)
        } catch {
            return .failed(.cacheWrite)
        }

        currentEntry = entry
        store.replaceRemotePolicy(with: policy)
        return .updated
    }
}
