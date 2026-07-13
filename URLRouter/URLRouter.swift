//
//  URLRouter.swift
//  URLRouter
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import Observation
import SwiftUI

/// The single source of truth for one app scene's navigation state.
@available(iOS 17.0, macOS 14.0, *)
@MainActor
@Observable
public final class AppRouter<Route: Hashable & Sendable> {
    /// Bind this to `NavigationStack(path:)`.
    public var path: [Route] = []
    /// Bind this to a `TabView` selection when the app uses tabs.
    public var selectedTab: Route?
    public private(set) var sheet: Route?
    public private(set) var fullScreenCover: Route?

    public init() {}

    public func apply(_ presentation: RoutePresentation<Route>) {
        switch presentation {
        case .push(let route): path.append(route)
        case .replaceStack(let routes): path = routes
        case .selectTab(let route, let resetNavigation):
            selectedTab = route
            if resetNavigation { path.removeAll() }
        case .sheet(let route): sheet = route
        case .fullScreenCover(let route): fullScreenCover = route
        }
    }

    public func dismissSheet() { sheet = nil }
    public func dismissFullScreenCover() { fullScreenCover = nil }
    public func popToRoot() { path.removeAll() }

    /// Use from `.onOpenURL`, a scene delegate, a notification, or an App Intent handoff.
    public func handle(universalLink url: URL, allowedHosts: Set<String>) throws where Route: UniversalLinkRoute {
        let link = try UniversalLink(url: url, allowedHosts: allowedHosts)
        apply(try Route.presentation(for: link))
    }
}

/// A reusable SwiftUI shell for push, sheet, and full-screen-cover routes.
#if os(iOS)
@available(iOS 17.0, *)
@MainActor
public struct RouterHost<Route: Hashable & Sendable, Root: View, Destination: View>: View {
    @Bindable private var router: AppRouter<Route>
    private let root: () -> Root
    private let destination: (Route) -> Destination

    public init(
        router: AppRouter<Route>,
        @ViewBuilder root: @escaping () -> Root,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self.router = router
        self.root = root
        self.destination = destination
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            root().navigationDestination(for: Route.self, destination: destination)
        }
        .sheet(isPresented: sheetIsPresented) {
            if let route = router.sheet { destination(route) }
        }
        .fullScreenCover(isPresented: fullScreenCoverIsPresented) {
            if let route = router.fullScreenCover { destination(route) }
        }
    }

    private var sheetIsPresented: Binding<Bool> {
        Binding(get: { router.sheet != nil }, set: { if !$0 { router.dismissSheet() } })
    }

    private var fullScreenCoverIsPresented: Binding<Bool> {
        Binding(get: { router.fullScreenCover != nil }, set: { if !$0 { router.dismissFullScreenCover() } })
    }
}
#endif
