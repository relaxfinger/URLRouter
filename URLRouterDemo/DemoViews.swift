//
//  DemoViews.swift
//  URLRouterDemo
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import SwiftUI
import URLRouter
import NavigationFeature

struct DemoTabs: View {
    @Bindable private var router: ModuleRouter
    @Bindable private var policyStore: ModuleRoutePolicyStore
    private let latestRouteEvent: ModuleRouteEvent?

    init(
        router: ModuleRouter,
        policyStore: ModuleRoutePolicyStore,
        latestRouteEvent: ModuleRouteEvent?
    ) {
        self.router = router
        self.policyStore = policyStore
        self.latestRouteEvent = latestRouteEvent
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Optional(NavigationFeatureRoutes.home))

            NavigationFeature.FavoritesView()
                .tabItem { Label("Favorites", systemImage: "heart") }
                .tag(Optional(NavigationFeatureRoutes.favorites))
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Toggle("Routing enabled", isOn: routingEnabled)
                    .font(.caption)
                    .padding(.horizontal)
                if let latestRouteEvent {
                    Label(
                        "Route \(latestRouteEvent.outcome.rawValue) · \(latestRouteEvent.failureCode ?? "success") · trace \(latestRouteEvent.traceID.uuidString.prefix(8))",
                        systemImage: latestRouteEvent.outcome == .handled ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var routingEnabled: Binding<Bool> {
        Binding(
            get: { !(policyStore.remotePolicy?.isCircuitBreakerOpen ?? false) },
            set: { enabled in
                policyStore.replaceRemotePolicy(with: ModuleRouteRemotePolicy(
                    isCircuitBreakerOpen: !enabled
                ))
            }
        )
    }
}
