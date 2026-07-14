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

    init(router: ModuleRouter) {
        self.router = router
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
    }
}
