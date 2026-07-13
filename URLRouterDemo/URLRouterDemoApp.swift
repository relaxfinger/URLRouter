//
//  URLRouterDemoApp.swift
//  URLRouterDemo
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import SwiftUI
import URLRouter

@main
struct URLRouterDemoApp: App {
    @State private var router = AppRouter<ModuleRoute>()

    var body: some Scene {
        WindowGroup {
            RouterHost(router: router) {
                DemoTabs(router: router)
            } destination: { route in
                DemoDestination(route: route, router: router)
            }
            .moduleLinkRouting(router: router, registry: DemoFeatureModule.registry, allowedHosts: ["example.com"])
        }
    }

}

@MainActor
enum DemoFeatureModule {
    static let id = "demo"
    static let home = ModuleRoute(moduleID: id, routeID: "home")
    static let favorites = ModuleRoute(moduleID: id, routeID: "favorites")
    static let settings = ModuleRoute(moduleID: id, routeID: "settings")
    static let signIn = ModuleRoute(moduleID: id, routeID: "signIn")

    static let registry = ModuleRouteRegistry(modules: [
        RouteModule(id: id) { link in
            switch link.pathComponents {
            case []: return home
            case ["favorites"]: return favorites
            case ["settings"]: return settings
            case ["sign-in"]: return signIn
            default:
                guard link.pathComponents.count == 2,
                      link.pathComponents[0] == "articles",
                      !link.pathComponents[1].isEmpty else { return nil }
                return ModuleRoute(moduleID: id, routeID: "article", parameters: ["id": link.pathComponents[1]])
            }
        } destination: { route in
            switch route.routeID {
            case "article": AnyView(ArticleView(id: route.parameters["id"] ?? ""))
            case "settings": AnyView(SettingsView())
            case "signIn": AnyView(SignInView())
            default: nil
            }
        }
    ])
}
