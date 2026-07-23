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
    @State private var router: ModuleRouter // One URLRouter navigation state per scene.
    @State private var policySession: DemoPolicySession // Owns URLRouter's local and remote route policy.
    @State private var routeObserver: DemoRouteObserver // Receives URLRouter route telemetry events.
    @State private var routeCoordinator: ModuleRouteCoordinator // Serializes simultaneous route requests for this scene.

    init() {
        let router = ModuleRouter()
        let policySession = DemoPolicySession()
        let routeObserver = DemoRouteObserver()
        _router = State(initialValue: router)
        _policySession = State(initialValue: policySession)
        _routeObserver = State(initialValue: routeObserver)
        _routeCoordinator = State(initialValue: ModuleRouteCoordinator(
            router: router,
            registry: DemoModules.registry,
            allowedHosts: ["example.com"],
            policyStore: policySession.store,
            // Forward privacy-safe queue and routing events to the demo observer.
            observability: ModuleRouteObservability(observers: [routeObserver])
        ))
    }

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
            // Install the coordinator once; it queues simultaneous openURL and Universal Link requests.
            .moduleLinkRouting(coordinator: routeCoordinator)
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
        NavigationFeatureRoutes.module,
        DemoAppRoutes.module // This route intentionally belongs to the App, not a Feature Package.
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

/// Demonstrates a route owned directly by the App shell when a UI has not been
/// extracted into its own Feature Package.
@MainActor
enum DemoAppRoutes {
    static let id = "app"
    static let diagnostics = ModuleRoute(moduleID: id, routeID: "diagnostics")

    static let module = RouteModule(id: id) { link in
        switch link.pathComponents {
        case ["diagnostics"]: return diagnostics
        default: return nil
        }
    } destination: { route in
        switch route.routeID {
        case "diagnostics": AnyView(DemoDiagnosticsView())
        default: nil
        }
    }
}

enum DemoAppLinks {
    static let diagnostics = URL(string: "https://example.com/diagnostics?presentation=sheet&version=1")!
}

private struct DemoDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("App-owned route") {
                    Text("This sheet is declared by URLRouterDemo, not by a Feature Package.")
                }
                Section("Route catalog") {
                    Text("The generator lists this route in the App section.")
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar { Button("Done") { dismiss() } }
        }
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
