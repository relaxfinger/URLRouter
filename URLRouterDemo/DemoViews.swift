//
//  DemoViews.swift
//  URLRouterDemo
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import SwiftUI
import URLRouter

struct DemoTabs: View {
    @Bindable private var router: ModuleRouter

    init(router: ModuleRouter) {
        self.router = router
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationDemoView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Optional(DemoNavigationFeature.home))

            FavoritesView()
                .tabItem { Label("Favorites", systemImage: "heart") }
                .tag(Optional(DemoNavigationFeature.favorites))
        }
    }
}

struct DemoDestination: View {
    let route: ModuleRoute
    let router: ModuleRouter

    @ViewBuilder
    var body: some View {
        DemoModules.registry.destination(for: route)
    }
}

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 54))
            Text("Sign in")
                .font(.largeTitle.bold())
            Text("This page is presented with fullScreenCover.")
                .foregroundStyle(.secondary)

            Button("Simulate successful sign in") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel") {
                dismiss()
            }
        }
        .padding()
    }
}
