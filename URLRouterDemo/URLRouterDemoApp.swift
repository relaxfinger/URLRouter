//
//  URLRouterDemoApp.swift
//  URLRouterDemo
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import Observation
import SwiftUI
import URLRouter

@main
struct URLRouterDemoApp: App {
    @State private var router = AppRouter<DemoRoute>()
    @State private var session = DemoSession()

    var body: some Scene {
        WindowGroup {
            RouterHost(router: router) {
                DemoTabs(router: router, session: session)
            } destination: { route in
                DemoDestination(route: route, router: router, session: session)
            }
            .universalLinkRouting(router: router, allowedHosts: ["example.com"]) { presentation in
                DemoNavigationPolicy.apply(presentation, router: router, session: session)
            }
        }
    }

}

@MainActor
enum DemoNavigationPolicy {
    static func apply(
        _ presentation: RoutePresentation<DemoRoute>,
        router: AppRouter<DemoRoute>,
        session: DemoSession
    ) {
        if isProtected(presentation), !session.isSignedIn {
            session.pendingPresentation = presentation
            router.apply(.fullScreenCover(.signIn))
        } else {
            router.apply(presentation)
        }
    }

    private static func isProtected(_ presentation: RoutePresentation<DemoRoute>) -> Bool {
        if case .push(.article(id: "private")) = presentation {
            return true
        }
        return false
    }
}

enum DemoRoute: Hashable, Sendable, UniversalLinkRoute {
    case home
    case favorites
    case article(id: String)
    case settings
    case signIn

    static func presentation(for link: UniversalLink) throws -> RoutePresentation<DemoRoute> {
        if link.pathComponents.isEmpty {
            return .selectTab(.home)
        }
        if link.pathComponents == ["favorites"] {
            return .selectTab(.favorites)
        }
        if link.pathComponents.count == 2,
           link.pathComponents[0] == "articles",
           !link.pathComponents[1].isEmpty {
            return .push(.article(id: link.pathComponents[1]))
        }
        if link.pathComponents == ["settings"] {
            return .sheet(.settings)
        }
        if link.pathComponents == ["sign-in"] {
            return .fullScreenCover(.signIn)
        }
        throw UniversalLinkError.unsupportedRoute
    }
}

@MainActor
@Observable
final class DemoSession {
    var isSignedIn = false
    var pendingPresentation: RoutePresentation<DemoRoute>?
    var lastError: String?
}
