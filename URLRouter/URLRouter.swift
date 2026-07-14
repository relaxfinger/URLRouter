//
//  URLRouter.swift
//  URLRouter
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import Observation
import SwiftUI

/// A destination owned by a feature module rather than the app target.
public struct ModuleRoute: Hashable, Sendable {
    public let moduleID: String
    public let routeID: String
    public let parameters: [String: String]

    public init(moduleID: String, routeID: String, parameters: [String: String] = [:]) {
        self.moduleID = moduleID
        self.routeID = routeID
        self.parameters = parameters
    }
}

/// The presentation contract encoded in an internal URL's `presentation` query item.
public enum ModulePresentationStyle: String, Hashable, Sendable {
    case push, tab, sheet, fullScreenCover
}

/// A module-owned destination together with the presentation requested by its URL.
public struct ResolvedModuleRoute: Hashable, Sendable {
    public let route: ModuleRoute
    public let presentation: ModulePresentationStyle

    public init(route: ModuleRoute, presentation: ModulePresentationStyle) {
        self.route = route
        self.presentation = presentation
    }
}

/// A feature module's URL grammar and destination factory.
@MainActor
public struct RouteModule {
    public let id: String
    private let resolve: (UniversalLink) throws -> ModuleRoute?
    private let destination: (ModuleRoute) -> AnyView?

    public init(
        id: String,
        resolve: @escaping (UniversalLink) throws -> ModuleRoute?,
        destination: @escaping (ModuleRoute) -> AnyView?
    ) {
        self.id = id
        self.resolve = resolve
        self.destination = destination
    }

    fileprivate func resolve(_ link: UniversalLink) throws -> ModuleRoute? { try resolve(link) }
    fileprivate func destination(for route: ModuleRoute) -> AnyView? { destination(route) }
}

/// Registry assembled from feature packages. The app target does not parse feature URLs.
@MainActor
public final class ModuleRouteRegistry {
    private let modules: [RouteModule]

    public init(modules: [RouteModule]) { self.modules = modules }

    public func resolve(_ link: UniversalLink) throws -> ResolvedModuleRoute {
        guard let style = link.query["presentation"].flatMap(ModulePresentationStyle.init(rawValue:)) else {
            throw UniversalLinkError.unsupportedRoute
        }
        for module in modules {
            if let route = try module.resolve(link) {
                return ResolvedModuleRoute(route: route, presentation: style)
            }
        }
        throw UniversalLinkError.unsupportedRoute
    }

    public func destination(for route: ModuleRoute) -> AnyView {
        modules.first(where: { $0.id == route.moduleID })?.destination(for: route) ?? AnyView(EmptyView())
    }
}

/// The single source of truth for one app scene's navigation state.
@available(iOS 17.0, macOS 14.0, *)
@MainActor
@Observable
public final class ModuleRouter {
    /// Bind this to `NavigationStack(path:)`.
    public var path: [ModuleRoute] = []
    /// Bind this to a `TabView` selection when the app uses tabs.
    public var selectedTab: ModuleRoute?
    public private(set) var sheet: ModuleRoute?
    public private(set) var fullScreenCover: ModuleRoute?

    public init() {}

    fileprivate func apply(_ presentation: ResolvedModuleRoute) {
        switch presentation.presentation {
        case .push: path.append(presentation.route)
        case .tab:
            selectedTab = presentation.route
            path.removeAll()
        case .sheet: sheet = presentation.route
        case .fullScreenCover: fullScreenCover = presentation.route
        }
    }

    fileprivate func dismissSheet() { sheet = nil }
    fileprivate func dismissFullScreenCover() { fullScreenCover = nil }
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
public struct ModuleLinkRoutingModifier: ViewModifier {
    private let router: ModuleRouter
    private let registry: ModuleRouteRegistry
    private let allowedHosts: Set<String>

    public init(router: ModuleRouter, registry: ModuleRouteRegistry, allowedHosts: Set<String>) {
        self.router = router
        self.registry = registry
        self.allowedHosts = allowedHosts
    }

    public func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { route($0) })
            .onOpenURL { _ = route($0) }
    }

    private func route(_ url: URL) -> OpenURLAction.Result {
        guard let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host?.lowercased(),
              allowedHosts.contains(where: { $0.lowercased() == host }) else { return .systemAction }
        do {
            let presentation = try registry.resolve(UniversalLink(url: url, allowedHosts: allowedHosts))
            router.apply(presentation)
            return .handled
        } catch { return .discarded }
    }
}

@available(iOS 17.0, macOS 14.0, *)
public extension View {
    @MainActor
    func moduleLinkRouting(router: ModuleRouter, registry: ModuleRouteRegistry, allowedHosts: Set<String>) -> some View {
        modifier(ModuleLinkRoutingModifier(router: router, registry: registry, allowedHosts: allowedHosts))
    }
}

/// A reusable SwiftUI shell for push, sheet, and full-screen-cover routes.
#if os(iOS)
@available(iOS 17.0, *)
@MainActor
public struct RouterHost<Root: View, Destination: View>: View {
    @Bindable private var router: ModuleRouter
    private let root: () -> Root
    private let destination: (ModuleRoute) -> Destination

    public init(
        router: ModuleRouter,
        @ViewBuilder root: @escaping () -> Root,
        @ViewBuilder destination: @escaping (ModuleRoute) -> Destination
    ) {
        self.router = router
        self.root = root
        self.destination = destination
    }

    public var body: some View {
        NavigationStack(path: $router.path) {
            root().navigationDestination(for: ModuleRoute.self, destination: destination)
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
