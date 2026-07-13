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

    /// Adapts the router to SwiftUI's `openURL` environment action.
    /// URLs outside `allowedHosts` are delegated to the operating system.
    public func openURLAction(allowedHosts: Set<String>) -> OpenURLAction where Route: UniversalLinkRoute {
        openURLAction(allowedHosts: allowedHosts, onPresentation: apply)
    }

    /// Adapts the router to SwiftUI's `openURL` environment action with a
    /// presentation policy such as authentication or analytics.
    ///
    /// The policy receives only a validated, typed presentation. It never
    /// receives the raw URL, keeping URL parsing inside URLRouter.
    public func openURLAction(
        allowedHosts: Set<String>,
        onPresentation: @escaping @MainActor (RoutePresentation<Route>) -> Void
    ) -> OpenURLAction where Route: UniversalLinkRoute {
        OpenURLAction { url in
            self.openURL(url, allowedHosts: allowedHosts, onPresentation: onPresentation)
        }
    }

    /// Handles one URL and reports the corresponding SwiftUI `OpenURLAction` result.
    /// URLs outside `allowedHosts` are delegated to the operating system.
    public func openURL(
        _ url: URL,
        allowedHosts: Set<String>,
        onPresentation: @escaping @MainActor (RoutePresentation<Route>) -> Void
    ) -> OpenURLAction.Result where Route: UniversalLinkRoute {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              allowedHosts.contains(where: { $0.lowercased() == host }) else {
            return .systemAction
        }

        do {
            let link = try UniversalLink(url: url, allowedHosts: allowedHosts)
            onPresentation(try Route.presentation(for: link))
            return .handled
        } catch {
            return .discarded
        }
    }
}

/// Installs one URLRouter-backed URL entry point for a SwiftUI view hierarchy.
///
/// Place this on the root view in a `WindowGroup`. Feature views can then call
/// `openURL(_:)`, while URLs delivered by the operating system are handled too.
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public struct UniversalLinkRoutingModifier<Route: UniversalLinkRoute>: ViewModifier {
    private let router: AppRouter<Route>
    private let allowedHosts: Set<String>
    private let onPresentation: @MainActor (RoutePresentation<Route>) -> Void

    public init(
        router: AppRouter<Route>,
        allowedHosts: Set<String>,
        onPresentation: @escaping @MainActor (RoutePresentation<Route>) -> Void
    ) {
        self.router = router
        self.allowedHosts = allowedHosts
        self.onPresentation = onPresentation
    }

    public func body(content: Content) -> some View {
        content
            .environment(
                \.openURL,
                router.openURLAction(allowedHosts: allowedHosts, onPresentation: onPresentation)
            )
            .onOpenURL { url in
                _ = router.openURL(url, allowedHosts: allowedHosts, onPresentation: onPresentation)
            }
    }
}

@available(iOS 17.0, macOS 14.0, *)
public extension View {
    /// Connects this view hierarchy to URLRouter for in-app and system URL opens.
    @MainActor
    func universalLinkRouting<Route: UniversalLinkRoute>(
        router: AppRouter<Route>,
        allowedHosts: Set<String>,
        onPresentation: @escaping @MainActor (RoutePresentation<Route>) -> Void
    ) -> some View {
        modifier(
            UniversalLinkRoutingModifier(
                router: router,
                allowedHosts: allowedHosts,
                onPresentation: onPresentation
            )
        )
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
