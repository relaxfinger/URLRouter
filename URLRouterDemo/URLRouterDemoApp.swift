//
//  URLRouterDemoApp.swift
//  URLRouterDemo
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import SwiftUI
import Observation
import URLRouter // Core routing types and the SwiftUI router host.
import URLRouterPolicyProvider // Optional cache-first remote policy lifecycle.
import ContentFeature
import NavigationFeature

@main
/// The demo composes the same `RouterHost` API available to every supported platform.
struct URLRouterDemoApp: App {
    @State private var router = ModuleRouter() // One URLRouter navigation state per scene.
    @State private var policySession = DemoPolicySession() // Owns URLRouter's local and remote route policy.
    @State private var routeObserver = DemoRouteObserver() // Receives URLRouter route telemetry events.

    var body: some Scene {
        WindowGroup {
            // RouterHost renders URLRouter push, sheet, and full-screen destinations.
            RouterHost(router: router) {
                DemoTabs(
                    router: router,
                    policyStore: policySession.store,
                    latestRouteEvent: routeObserver.latestEvent,
                    policyStatus: policySession.status
                )
            } destination: { route in
                // Ask URLRouter's registry for the Feature-owned destination view.
                DemoModules.registry.destination(for: route)
            }
            // Install URLRouter once at the scene root for openURL and Universal Links.
            .moduleLinkRouting(
                router: router,
                registry: DemoModules.registry,
                allowedHosts: ["example.com"],
                policyStore: policySession.store,
                // Send privacy-safe URLRouter events to the demo observer.
                observability: ModuleRouteObservability(observers: [routeObserver])
            )
            // Restore cached policy first, then refresh the demo's remote policy.
            .task { await policySession.bootstrapAndRefresh() }
        }
    }

}

@MainActor
enum DemoModules {
    // Register every Feature Package with URLRouter; Features keep their own URL parsing.
    static let registry = ModuleRouteRegistry(modules: [
        ContentFeature.module,
        NavigationFeatureRoutes.module
    ])
    static func makePolicyStore() -> ModuleRoutePolicyStore {
        // Keep URLRouter's trusted local rules separate from replaceable remote restrictions.
        ModuleRoutePolicyStore(
            localPolicy: ModuleRoutePolicy(
                acceptedContractVersions: ["1"],
                allowsUnversionedLinks: false
            ),
            remotePolicy: ModuleRouteRemotePolicy() // Demo starts with routing enabled.
        )
    }
}

@MainActor
@Observable
final class DemoPolicySession {
    let store = DemoModules.makePolicyStore() // The store used by moduleLinkRouting.
    private let provider: RoutePolicyProvider
    private(set) var status = "Using local policy"

    init() {
        // RoutePolicyProvider demonstrates URLRouter's cache-first policy refresh flow.
        provider = RoutePolicyProvider(
            store: store,
            source: DemoPolicySource(),
            cache: InMemoryRoutePolicyCache(),
            strategy: .standard
        )
    }

    func bootstrapAndRefresh() async {
        let bootstrap = await provider.bootstrap() // Apply a verified cached policy, if any.
        let refresh = await provider.refresh() // Then fetch and atomically apply the newest policy.
        status = "Policy \(bootstrap) · \(refresh)"
    }
}

private struct DemoPolicySource: RoutePolicyRemoteSource {
    func fetchPolicyData() async throws -> Data {
        // Real apps fetch a signed payload from their own backend or config service.
        try JSONEncoder().encode(ModuleRouteRemotePolicy())
    }
}

@MainActor
@Observable
final class DemoRouteObserver: ModuleRouteObserving {
    private(set) var latestEvent: ModuleRouteEvent?

    func record(_ event: ModuleRouteEvent) {
        // URLRouter emits a privacy-safe event after every routing attempt.
        latestEvent = event
    }
}
