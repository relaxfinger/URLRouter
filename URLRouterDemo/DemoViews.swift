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
    @Bindable private var router: AppRouter<DemoRoute>
    private let session: DemoSession

    init(router: AppRouter<DemoRoute>, session: DemoSession) {
        self.router = router
        self.session = session
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationDemoView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Optional(DemoRoute.home))

            FavoritesView()
                .tabItem { Label("Favorites", systemImage: "heart") }
                .tag(Optional(DemoRoute.favorites))
        }
    }
}

struct DemoDestination: View {
    let route: DemoRoute
    let router: AppRouter<DemoRoute>
    let session: DemoSession

    @ViewBuilder
    var body: some View {
        switch route {
        case .article(let id):
            ArticleView(id: id)
        case .settings:
            SettingsView()
        case .signIn:
            SignInView(router: router, session: session)
        case .home, .favorites:
            EmptyView()
        }
    }
}

struct SignInView: View {
    let router: AppRouter<DemoRoute>
    let session: DemoSession

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 54))
            Text("Sign in")
                .font(.largeTitle.bold())
            Text("This page is presented with fullScreenCover.")
                .foregroundStyle(.secondary)

            Button("Simulate successful sign in") {
                session.isSignedIn = true
                let pending = session.pendingPresentation
                session.pendingPresentation = nil
                router.dismissFullScreenCover()
                if let pending {
                    router.apply(pending)
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel") {
                session.pendingPresentation = nil
                router.dismissFullScreenCover()
            }
        }
        .padding()
    }
}
