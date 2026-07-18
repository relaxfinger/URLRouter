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
import ContentFeature
import NavigationFeature

@main
/// The demo composes the same `RouterHost` API available to every supported platform.
struct URLRouterDemoApp: App {
    @State private var router = ModuleRouter()
    @State private var policyStore = DemoModules.makePolicyStore()
    @State private var routeObserver = DemoRouteObserver()

    var body: some Scene {
        WindowGroup {
            RouterHost(router: router) {
                DemoTabs(
                    router: router,
                    policyStore: policyStore,
                    latestRouteEvent: routeObserver.latestEvent
                )
            } destination: { route in
                DemoModules.registry.destination(for: route)
            }
            .moduleLinkRouting(
                router: router,
                registry: DemoModules.registry,
                allowedHosts: ["example.com"],
                policyStore: policyStore,
                observability: ModuleRouteObservability(observers: [routeObserver])
            )
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
final class DemoRouteObserver: ModuleRouteObserving {
    private(set) var latestEvent: ModuleRouteEvent?

    func record(_ event: ModuleRouteEvent) {
        latestEvent = event
    }
}
