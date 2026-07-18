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
    private let latestRouteEvent: ModuleRouteEvent?

    init(router: ModuleRouter, latestRouteEvent: ModuleRouteEvent?) {
        self.router = router
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
            if let latestRouteEvent {
                Label(
                    "Route \(latestRouteEvent.outcome.rawValue) · trace \(latestRouteEvent.traceID.uuidString.prefix(8))",
                    systemImage: latestRouteEvent.outcome == .handled ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            }
        }
    }
}
