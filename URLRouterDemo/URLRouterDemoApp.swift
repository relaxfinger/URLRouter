//
//  URLRouterDemoApp.swift
//  URLRouterDemo
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import SwiftUI
import URLRouter
import ContentFeature
import NavigationFeature

@main
/// The demo composes the same `RouterHost` API available to every supported platform.
struct URLRouterDemoApp: App {
    @State private var router = ModuleRouter()

    var body: some Scene {
        WindowGroup {
            RouterHost(router: router) {
                DemoTabs(router: router)
            } destination: { route in
                DemoModules.registry.destination(for: route)
            }
            .moduleLinkRouting(router: router, registry: DemoModules.registry, allowedHosts: ["example.com"])
        }
    }

}

@MainActor
enum DemoModules {
    static let registry = ModuleRouteRegistry(modules: [
        ContentFeature.module,
        NavigationFeatureRoutes.module
    ])
}
