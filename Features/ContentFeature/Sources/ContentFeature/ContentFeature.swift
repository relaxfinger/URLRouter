//
//  ContentFeature.swift
//  ContentFeature
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import SwiftUI
import URLRouter

@MainActor
public enum ContentFeature {
    public static let id = "content"

    public static let module = RouteModule(id: id) { link in
        guard link.pathComponents.count == 2,
              link.pathComponents[0] == "articles",
              !link.pathComponents[1].isEmpty else { return nil }
        return ModuleRoute(moduleID: id, routeID: "article", parameters: ["id": link.pathComponents[1]])
    } destination: { route in
        guard route.routeID == "article" else { return nil }
        return AnyView(ArticleView(id: route.parameters["id"] ?? ""))
    }
}

public struct ArticleView: View {
    public let id: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    public init(id: String) { self.id = id }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text").font(.system(size: 54))
            Text("Article \(id)").font(.title.bold())
            Text("This ContentFeature page can route back to NavigationFeature with openURL.")
                .foregroundStyle(.secondary)
            Button("Push another article") { openURL(ContentLinks.article("next")) }
            Button("Open NavigationFeature settings") { openURL(NavigationLinks.settings) }
            Button("Back") { dismiss() }
        }
        .padding()
        .navigationTitle("Article")
    }
}

public enum ContentLinks {
    public static func article(_ id: String) -> URL {
        URL(string: "https://example.com/articles/\(id)?presentation=push&version=1")!
    }
}

public enum NavigationLinks {
    public static let settings = URL(string: "https://example.com/settings?presentation=sheet&version=1")!
}
