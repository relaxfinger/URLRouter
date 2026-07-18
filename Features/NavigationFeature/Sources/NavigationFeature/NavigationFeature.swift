//
//  NavigationFeature.swift
//  NavigationFeature
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import SwiftUI
import URLRouter

@MainActor
public enum NavigationFeatureRoutes {
    public static let id = "navigation"
    public static let home = ModuleRoute(moduleID: id, routeID: "home")
    public static let favorites = ModuleRoute(moduleID: id, routeID: "favorites")
    public static let settings = ModuleRoute(moduleID: id, routeID: "settings")
    public static let signIn = ModuleRoute(moduleID: id, routeID: "signIn")

    public static let module = RouteModule(id: id) { link in
        switch link.pathComponents {
        case []: return home
        case ["favorites"]: return favorites
        case ["settings"]: return settings
        case ["sign-in"]: return signIn
        default: return nil
        }
    } destination: { route in
        switch route.routeID {
        case "settings": AnyView(SettingsView())
        case "signIn": AnyView(SignInView())
        default: nil
        }
    }
}

public struct HomeView: View {
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        List {
            Section("Cross-feature navigation") {
                Button("Open ContentFeature article 42") { openURL(ContentLinks.article("42")) }
                Button("Present Settings sheet") { openURL(NavigationLinks.settings) }
                Button("Present full-screen sign in") { openURL(NavigationLinks.signIn) }
                Button("Switch to Favorites tab") { openURL(NavigationLinks.favorites) }
            }
        }
        .navigationTitle("NavigationFeature")
    }
}

public struct FavoritesView: View {
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        ContentUnavailableView {
            Label("No Favorites", systemImage: "heart")
        } description: {
            Text("This tab is selected by an openURL action.")
        } actions: {
            Button("Open ContentFeature article 99") { openURL(ContentLinks.article("99")) }
        }
    }
}

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    public init() {}
    public var body: some View {
        NavigationStack {
            Form {
                Section("Presentation") {
                    Text("This route is displayed as a sheet.")
                    Button("Dismiss") { dismiss() }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

public struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    public init() {}
    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 54))
            Text("Sign in").font(.largeTitle.bold())
            Button("Dismiss") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

public enum ContentLinks {
    public static func article(_ id: String) -> URL {
        URL(string: "https://example.com/articles/\(id)?presentation=push&version=1")!
    }
}

public enum NavigationLinks {
    public static let settings = URL(string: "https://example.com/settings?presentation=sheet&version=1")!
    public static let signIn = URL(string: "https://example.com/sign-in?presentation=fullScreenCover&version=1")!
    public static let favorites = URL(string: "https://example.com/favorites?presentation=tab&version=1")!
}
