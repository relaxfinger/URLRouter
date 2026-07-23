//
//  DemoViews.swift
//  URLRouterDemo
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import SwiftUI
import URLRouter // ModuleRouter and ModuleRoutePolicyStore drive this tab shell.
import NavigationFeature

struct DemoTabs: View {
    @Environment(\.openURL) private var openURL
    @Bindable private var router: ModuleRouter // URLRouter owns the selected tab state.
    @Bindable private var policyStore: ModuleRoutePolicyStore // URLRouter reads this on the next link.
    private let latestRouteEvent: ModuleRouteEvent?
    private let policyStatus: String

    init(
        router: ModuleRouter,
        policyStore: ModuleRoutePolicyStore,
        latestRouteEvent: ModuleRouteEvent?,
        policyStatus: String
    ) {
        self.router = router
        self.policyStore = policyStore
        self.latestRouteEvent = latestRouteEvent
        self.policyStatus = policyStatus
    }

    var body: some View {
        // Bind SwiftUI tab selection to URLRouter's tab route state.
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
                Button("Open App Diagnostics") { openURL(DemoAppLinks.diagnostics) }
                    .font(.caption)
                Text(policyStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                // Simulate the backend circuit breaker by replacing URLRouter's remote policy.
                policyStore.replaceRemotePolicy(with: ModuleRouteRemotePolicy(
                    isCircuitBreakerOpen: !enabled
                ))
            }
        )
    }
}
