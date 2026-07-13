//
//  DemoFeatureViews.swift
//  URLRouterDemo
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI

/// This file intentionally has no `import URLRouter` dependency.
/// It can move into a feature package unchanged.
enum DemoLinks {
    static let host = "https://example.com"

    static func article(_ id: String) -> URL {
        URL(string: "\(host)/articles/\(id)")!
    }

    static let settings = URL(string: "\(host)/settings")!
    static let signIn = URL(string: "\(host)/sign-in")!
    static let favorites = URL(string: "\(host)/favorites")!
}

struct NavigationDemoView: View {
    @Environment(\.openURL) private var openURL
    @State private var linkText = DemoLinks.article("42").absoluteString

    var body: some View {
        List {
            Section("Navigation") {
                Button("Push article 42") { openURL(DemoLinks.article("42")) }
                Button("Present Settings sheet") { openURL(DemoLinks.settings) }
                Button("Present full-screen sign in") { openURL(DemoLinks.signIn) }
                Button("Switch to Favorites tab") { openURL(DemoLinks.favorites) }
            }

            Section("Universal Link simulator") {
                TextField("https://example.com/articles/42", text: $linkText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Route this URL") {
                    guard let url = URL(string: linkText) else { return }
                    openURL(url)
                }
                Text("Try /articles/42, /settings, /sign-in, /favorites, or /articles/private.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        }
        .navigationTitle("URLRouter Demo")
    }
}

struct FavoritesView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("No Favorites", systemImage: "heart")
        } description: {
            Text("This tab is selected by an openURL action.")
        } actions: {
            Button("Open article 99") { openURL(DemoLinks.article("99")) }
        }
    }
}

struct ArticleView: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text").font(.system(size: 54))
            Text("Article \(id)").font(.title.bold())
            Text("This feature only emits an openURL action.").foregroundStyle(.secondary)
            Button("Push another article") { openURL(DemoLinks.article("next")) }
            Button("Back") { dismiss() }
        }
        .padding()
        .navigationTitle("Article")
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
