//
//  URLRouterDemoApp.swift
//  URLRouterDemo
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import SwiftUI
import Observation
import URLRouter
import URLRouterPolicyProvider
import ContentFeature
import NavigationFeature

@main
/// The demo composes the same `RouterHost` API available to every supported platform.
struct URLRouterDemoApp: App {
    @State private var router = ModuleRouter()
    @State private var policySession = DemoPolicySession()
    @State private var routeObserver = DemoRouteObserver()

    var body: some Scene {
        WindowGroup {
            RouterHost(router: router) {
                DemoTabs(
                    router: router,
                    policyStore: policySession.store,
                    latestRouteEvent: routeObserver.latestEvent,
                    policyStatus: policySession.status
                )
            } destination: { route in
                DemoModules.registry.destination(for: route)
            }
            .moduleLinkRouting(
                router: router,
                registry: DemoModules.registry,
                allowedHosts: ["example.com"],
                policyStore: policySession.store,
                observability: ModuleRouteObservability(observers: [routeObserver])
            )
            .task { await policySession.bootstrapAndRefresh() }
        }
    }

}

@MainActor
enum DemoModules {
    static let registry = ModuleRouteRegistry(modules: [
        ContentFeature.module,
        NavigationFeatureRoutes.module
    ])
    static func makePolicyStore() -> ModuleRoutePolicyStore {
        ModuleRoutePolicyStore(
            localPolicy: ModuleRoutePolicy(
                acceptedContractVersions: ["1"],
                allowsUnversionedLinks: false
            ),
            remotePolicy: ModuleRouteRemotePolicy()
        )
    }
}

@MainActor
@Observable
final class DemoPolicySession {
    let store = DemoModules.makePolicyStore()
    private let provider: RoutePolicyProvider
    private(set) var status = "Using local policy"

    init() {
        provider = RoutePolicyProvider(
            store: store,
            source: DemoPolicySource(),
            cache: InMemoryRoutePolicyCache(),
            strategy: .standard
        )
    }

    func bootstrapAndRefresh() async {
        let bootstrap = await provider.bootstrap()
        let refresh = await provider.refresh()
        status = "Policy \(bootstrap) · \(refresh)"
    }
}

private struct DemoPolicySource: RoutePolicyRemoteSource {
    func fetchPolicyData() async throws -> Data {
        try JSONEncoder().encode(ModuleRouteRemotePolicy())
    }
}

@MainActor
@Observable
final class DemoRouteObserver: ModuleRouteObserving {
    private(set) var latestEvent: ModuleRouteEvent?

    func record(_ event: ModuleRouteEvent) {
        latestEvent = event
    }
}
