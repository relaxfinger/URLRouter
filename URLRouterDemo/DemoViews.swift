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
            NavigationDemoView(router: router, session: session)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Optional(DemoRoute.home))

            FavoritesView(router: router)
                .tabItem { Label("Favorites", systemImage: "heart") }
                .tag(Optional(DemoRoute.favorites))
        }
    }
}

struct NavigationDemoView: View {
    let router: AppRouter<DemoRoute>
    let session: DemoSession
    @State private var linkText = "https://example.com/articles/42"

    var body: some View {
        List {
            Section("Navigation") {
                Button("Push article 42") {
                    router.apply(.push(.article(id: "42")))
                }
                Button("Present Settings sheet") {
                    router.apply(.sheet(.settings))
                }
                Button("Present full-screen sign in") {
                    router.apply(.fullScreenCover(.signIn))
                }
                Button("Switch to Favorites tab") {
                    router.apply(.selectTab(.favorites))
                }
            }

            Section("Universal Link simulator") {
                TextField("https://example.com/articles/42", text: $linkText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Route this URL") {
                    guard let url = URL(string: linkText) else {
                        session.lastError = "The text is not a valid URL."
                        return
                    }
                    DemoLinkHandler.open(url, router: router, session: session)
                }

                Text("Try /articles/42, /settings, /sign-in, /favorites, or /articles/private.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Session") {
                Label(
                    session.isSignedIn ? "Signed in" : "Signed out",
                    systemImage: session.isSignedIn ? "checkmark.circle.fill" : "person.crop.circle.badge.xmark"
                )
                .foregroundStyle(session.isSignedIn ? .green : .secondary)

                if let error = session.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("URLRouter Demo")
    }
}

struct FavoritesView: View {
    let router: AppRouter<DemoRoute>

    var body: some View {
        ContentUnavailableView {
            Label("No Favorites", systemImage: "heart")
        } description: {
            Text("This tab is selected by .selectTab(.favorites).")
        } actions: {
            Button("Open article 99") {
                router.apply(.push(.article(id: "99")))
            }
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
            ArticleView(id: id, router: router)
        case .settings:
            SettingsView(router: router)
        case .signIn:
            SignInView(router: router, session: session)
        case .home, .favorites:
            EmptyView()
        }
    }
}

struct ArticleView: View {
    let id: String
    let router: AppRouter<DemoRoute>

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 54))
            Text("Article \(id)")
                .font(.title.bold())
            Text("This page was pushed through AppRouter.")
                .foregroundStyle(.secondary)
            Button("Push another article") {
                router.apply(.push(.article(id: "next")))
            }
            Button("Back to the selected tab") {
                router.popToRoot()
            }
        }
        .padding()
        .navigationTitle("Article")
    }
}

struct SettingsView: View {
    let router: AppRouter<DemoRoute>

    var body: some View {
        NavigationStack {
            Form {
                Section("Presentation") {
                    Text("This route is displayed as a sheet.")
                    Button("Dismiss") {
                        router.dismissSheet()
                    }
                }
            }
            .navigationTitle("Settings")
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
