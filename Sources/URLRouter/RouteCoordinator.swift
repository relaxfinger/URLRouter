//
//  RouteCoordinator.swift
//  URLRouter
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI

/// The importance of a route request when several requests arrive together.
///
/// The coordinator always finishes one request before starting the next one.
/// Higher-priority requests go first; requests with the same priority keep their
/// arrival order. The package does not assign login or business meaning to these
/// values: the app chooses the priority when it submits a route.
public enum ModuleRouteRequestPriority: Int, CaseIterable, Hashable, Sendable {
    case background
    case userInitiated
    case external
    case critical
}

/// Queue limits for a scene's route coordinator.
public struct ModuleRouteCoordinatorConfiguration: Hashable, Sendable {
    /// The maximum number of waiting routes. A route currently being applied is not counted.
    public let maximumPendingRequests: Int
    /// How long a request may wait before it is discarded.
    public let defaultTimeToLive: TimeInterval
    /// The pause between route applications, allowing SwiftUI to settle one transition first.
    public let transitionDelay: Duration

    public init(
        maximumPendingRequests: Int = 10,
        defaultTimeToLive: TimeInterval = 30,
        transitionDelay: Duration = .milliseconds(350)
    ) {
        self.maximumPendingRequests = max(1, maximumPendingRequests)
        self.defaultTimeToLive = max(0, defaultTimeToLive)
        self.transitionDelay = transitionDelay
    }

    /// The production defaults: ten waiting routes, a 30-second lifetime, and a short transition pause.
    public static let standard = ModuleRouteCoordinatorConfiguration()
}

/// Why a queued route was not applied.
public enum ModuleRouteCoordinatorError: Error, Equatable, Sendable, LocalizedError {
    case requestExpired
    case queueFull

    public var errorDescription: String? {
        switch self {
        case .requestExpired: "The route request expired before it could be displayed."
        case .queueFull: "The route queue is full."
        }
    }
}

/// Serializes URL routing for one scene.
///
/// Create one coordinator beside one `ModuleRouter`, normally in a SwiftUI
/// `@State` property. It validates a route before queuing it, merges an exact
/// duplicate URL, orders waiting requests by priority, and validates the route
/// once more immediately before applying it. The latter check ensures a policy
/// change made while a request waits still takes effect.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@MainActor
public final class ModuleRouteCoordinator {
    private struct PendingRequest {
        let url: URL
        let host: String
        let link: UniversalLink
        let presentation: ResolvedModuleRoute
        let priority: ModuleRouteRequestPriority
        let sequence: UInt64
        let expiresAt: Date
    }

    private let router: ModuleRouter
    private let registry: ModuleRouteRegistry
    private let allowedHosts: Set<String>
    private let policy: ModuleRoutePolicy
    private let policyStore: ModuleRoutePolicyStore?
    private let observability: ModuleRouteObservability?
    private let onFailure: (URL, Error) -> Void
    private let onEvent: (ModuleRouteEvent) -> Void
    private let configuration: ModuleRouteCoordinatorConfiguration

    private var pendingRequests: [PendingRequest] = []
    private var activeURL: URL?
    private var nextSequence: UInt64 = 0
    private var drainTask: Task<Void, Never>?

    /// The number of routes waiting to be applied in this scene.
    public var pendingRequestCount: Int { pendingRequests.count }

    /// Creates a coordinator for exactly one router and one app scene.
    public init(
        router: ModuleRouter,
        registry: ModuleRouteRegistry,
        allowedHosts: Set<String>,
        policy: ModuleRoutePolicy = .permissive,
        policyStore: ModuleRoutePolicyStore? = nil,
        observability: ModuleRouteObservability? = nil,
        configuration: ModuleRouteCoordinatorConfiguration = .standard,
        onFailure: @escaping (URL, Error) -> Void = { _, _ in },
        onEvent: @escaping (ModuleRouteEvent) -> Void = { _ in }
    ) {
        self.router = router
        self.registry = registry
        self.allowedHosts = allowedHosts
        self.policy = policy
        self.policyStore = policyStore
        self.observability = observability
        self.configuration = configuration
        self.onFailure = onFailure
        self.onEvent = onEvent
    }

    /// Validates and submits a route for serialized execution.
    ///
    /// A duplicate of a waiting or active URL is accepted but not added again.
    /// For an external URL that does not belong to an allowed host, this returns
    /// `.systemAction` so SwiftUI can handle it normally.
    @discardableResult
    public func route(
        _ url: URL,
        priority: ModuleRouteRequestPriority = .external,
        expiresAt: Date? = nil
    ) -> OpenURLAction.Result {
        guard let host = routeHost(for: url) else {
            emit(outcome: .systemAction, host: nil)
            return .systemAction
        }

        do {
            let link = try UniversalLink(url: url, allowedHosts: allowedHosts)
            let presentation = try registry.resolve(link)
            try validate(link, presentation: presentation)
            discardExpiredRequests()

            guard activeURL != url, !pendingRequests.contains(where: { $0.url == url }) else {
                emit(outcome: .handled, host: host, presentation: presentation, failureCode: "queue.duplicate_merged")
                return .handled
            }

            let expiry = expiresAt ?? Date().addingTimeInterval(configuration.defaultTimeToLive)
            guard expiry > Date() else {
                discard(url, host: host, presentation: presentation, error: ModuleRouteCoordinatorError.requestExpired)
                return .discarded
            }

            let request = PendingRequest(
                url: url,
                host: host,
                link: link,
                presentation: presentation,
                priority: priority,
                sequence: nextSequence,
                expiresAt: expiry
            )
            nextSequence &+= 1
            guard enqueue(request) else { return .discarded }
            scheduleDrain()
            return .handled
        } catch {
            discard(url, host: host, error: error)
            return .discarded
        }
    }

    private func enqueue(_ request: PendingRequest) -> Bool {
        if pendingRequests.count >= configuration.maximumPendingRequests,
           let lowestIndex = pendingRequests.indices.min(by: { lhs, rhs in
               let left = pendingRequests[lhs]
               let right = pendingRequests[rhs]
               return left.priority.rawValue == right.priority.rawValue
                   ? left.sequence < right.sequence
                   : left.priority.rawValue < right.priority.rawValue
           }) {
            let lowest = pendingRequests[lowestIndex]
            guard request.priority.rawValue > lowest.priority.rawValue else {
                discard(request.url, host: request.host, presentation: request.presentation, error: ModuleRouteCoordinatorError.queueFull)
                return false
            }
            pendingRequests.remove(at: lowestIndex)
            discard(lowest.url, host: lowest.host, presentation: lowest.presentation, error: ModuleRouteCoordinatorError.queueFull)
        }
        pendingRequests.append(request)
        return true
    }

    private func scheduleDrain() {
        guard drainTask == nil else { return }
        drainTask = Task { @MainActor [weak self] in
            // Batch URLs delivered in the same run-loop turn before choosing a winner.
            await Task.yield()
            await self?.drain()
        }
    }

    private func drain() async {
        defer { drainTask = nil }
        while !pendingRequests.isEmpty {
            discardExpiredRequests()
            guard let index = nextRequestIndex() else { break }
            let request = pendingRequests.remove(at: index)
            activeURL = request.url

            do {
                try validate(request.link, presentation: request.presentation)
                router.apply(request.presentation)
                emit(outcome: .handled, host: request.host, presentation: request.presentation)
            } catch {
                discard(request.url, host: request.host, presentation: request.presentation, error: error)
            }
            activeURL = nil

            if !pendingRequests.isEmpty {
                try? await Task.sleep(for: configuration.transitionDelay)
            }
        }
    }

    private func nextRequestIndex() -> Int? {
        pendingRequests.indices.max { lhs, rhs in
            let left = pendingRequests[lhs]
            let right = pendingRequests[rhs]
            return left.priority.rawValue == right.priority.rawValue
                ? left.sequence > right.sequence
                : left.priority.rawValue < right.priority.rawValue
        }
    }

    private func discardExpiredRequests() {
        let now = Date()
        let expired = pendingRequests.filter { $0.expiresAt <= now }
        pendingRequests.removeAll { $0.expiresAt <= now }
        for request in expired {
            discard(request.url, host: request.host, presentation: request.presentation, error: ModuleRouteCoordinatorError.requestExpired)
        }
    }

    private func validate(_ link: UniversalLink, presentation: ResolvedModuleRoute) throws {
        if let policyStore {
            try policyStore.validate(link, presentation: presentation)
        } else {
            try policy.validate(link, presentation: presentation)
        }
    }

    private func routeHost(for url: URL) -> String? {
        guard let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host?.lowercased(),
              allowedHosts.contains(where: { $0.lowercased() == host }) else {
            return nil
        }
        return host
    }

    private func discard(
        _ url: URL,
        host: String,
        presentation: ResolvedModuleRoute? = nil,
        error: Error
    ) {
        onFailure(url, error)
        emit(outcome: .discarded, host: host, presentation: presentation, failure: error)
    }

    private func emit(
        outcome: ModuleRouteEventOutcome,
        host: String?,
        presentation: ResolvedModuleRoute? = nil,
        failure: Error? = nil,
        failureCode: String? = nil
    ) {
        let event = ModuleRouteEvent(
            outcome: outcome,
            host: host,
            moduleID: presentation?.route.moduleID,
            routeID: presentation?.route.routeID,
            presentation: presentation?.presentation,
            failureCode: failureCode ?? failure.map(moduleRouteFailureCode),
            failureDescription: failure?.localizedDescription
        )
        observability?.record(event)
        onEvent(event)
    }
}
