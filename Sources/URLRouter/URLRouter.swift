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
    /// The Feature Package that owns this route.
    public let moduleID: String
    public let routeID: String
    public let parameters: [String: String]

    /// Creates a route value returned by a Feature Package's URL matcher.
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

    /// Creates a route together with the presentation requested by its URL.
    public init(route: ModuleRoute, presentation: ModulePresentationStyle) {
        self.route = route
        self.presentation = presentation
    }
}

/// Errors caused by an invalid module registry or an unresolved destination.
public enum ModuleRouteRegistryError: Error, Equatable, Sendable, LocalizedError {
    /// More than one module was registered with the same identifier.
    case duplicateModuleID(String)
    /// A module resolved a route that claims to belong to another module.
    case routeModuleMismatch(expected: String, actual: String)
    /// A module resolved a route but cannot build its destination.
    case unavailableDestination(moduleID: String, routeID: String)

    public var errorDescription: String? {
        switch self {
        case .duplicateModuleID(let id): "The module identifier \(id) is registered more than once."
        case .routeModuleMismatch(let expected, let actual): "Module \(expected) returned a route owned by \(actual)."
        case .unavailableDestination(let moduleID, let routeID): "Module \(moduleID) cannot display route \(routeID)."
        }
    }
}

/// A feature module's URL grammar and destination factory.
@MainActor
public struct RouteModule {
    public let id: String
    private let resolve: (UniversalLink) throws -> ModuleRoute?
    private let destination: (ModuleRoute) -> AnyView?

    /// Creates a module registration. Return `nil` when the URL belongs to another module.
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
    private let modulesByID: [String: RouteModule]
    private let configurationError: ModuleRouteRegistryError?

    /// Creates a registry from every Feature Package linked into the app.
    public init(modules: [RouteModule]) {
        self.modules = modules

        var modulesByID: [String: RouteModule] = [:]
        var configurationError: ModuleRouteRegistryError?
        for module in modules {
            if modulesByID[module.id] != nil {
                configurationError = .duplicateModuleID(module.id)
                break
            }
            modulesByID[module.id] = module
        }
        self.modulesByID = modulesByID
        self.configurationError = configurationError
    }

    /// Resolves a validated URL to its owning module and presentation contract.
    public func resolve(_ link: UniversalLink) throws -> ResolvedModuleRoute {
        if let configurationError { throw configurationError }
        guard let style = link.query["presentation"].flatMap(ModulePresentationStyle.init(rawValue:)) else {
            throw UniversalLinkError.unsupportedRoute
        }
        for module in modules {
            if let route = try module.resolve(link) {
                guard route.moduleID == module.id else {
                    throw ModuleRouteRegistryError.routeModuleMismatch(expected: module.id, actual: route.moduleID)
                }
                guard style == .tab || module.destination(for: route) != nil else {
                    throw ModuleRouteRegistryError.unavailableDestination(moduleID: module.id, routeID: route.routeID)
                }
                return ResolvedModuleRoute(route: route, presentation: style)
            }
        }
        throw UniversalLinkError.unsupportedRoute
    }

    /// Returns the destination view supplied by the route's owning module.
    public func destination(for route: ModuleRoute) -> AnyView {
        guard let destination = modulesByID[route.moduleID]?.destination(for: route) else {
            assertionFailure(ModuleRouteRegistryError.unavailableDestination(moduleID: route.moduleID, routeID: route.routeID).localizedDescription)
            return AnyView(Text("Route unavailable"))
        }
        return destination
    }
}

/// The single source of truth for one app scene's navigation state.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@MainActor
@Observable
public final class ModuleRouter {
    /// Bind this to `NavigationStack(path:)`.
    public var path: [ModuleRoute] = []
    /// Bind this to a `TabView` selection when the app uses tabs.
    public var selectedTab: ModuleRoute?
    /// The active modal route. A router presents at most one modal route at a time.
    public private(set) var modalPresentation: ResolvedModuleRoute?
    public var sheet: ModuleRoute? {
        modalPresentation?.presentation == .sheet ? modalPresentation?.route : nil
    }
    public var fullScreenCover: ModuleRoute? {
        modalPresentation?.presentation == .fullScreenCover ? modalPresentation?.route : nil
    }

    /// Creates independent navigation state for one SwiftUI scene.
    public init() {}

    /// Applies a route using a deterministic presentation policy.
    ///
    /// Push and tab routes dismiss an active modal route. A new modal route replaces
    /// the current modal route instead of allowing multiple presentation bindings.
    func apply(_ presentation: ResolvedModuleRoute) {
        switch presentation.presentation {
        case .push:
            dismissModal()
            path.append(presentation.route)
        case .tab:
            dismissModal()
            selectedTab = presentation.route
            path.removeAll()
        case .sheet, .fullScreenCover:
            modalPresentation = presentation
        }
    }

    func dismissSheet() {
        guard modalPresentation?.presentation == .sheet else { return }
        dismissModal()
    }

    func dismissFullScreenCover() {
        guard modalPresentation?.presentation == .fullScreenCover else { return }
        dismissModal()
    }

    private func dismissModal() { modalPresentation = nil }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@MainActor
public struct ModuleLinkRoutingModifier: ViewModifier {
    private let router: ModuleRouter
    private let registry: ModuleRouteRegistry
    private let allowedHosts: Set<String>
    private let onFailure: (URL, Error) -> Void

    /// Creates the root URL handler for trusted Universal Links and in-app `openURL` actions.
    public init(
        router: ModuleRouter,
        registry: ModuleRouteRegistry,
        allowedHosts: Set<String>,
        onFailure: @escaping (URL, Error) -> Void = { _, _ in }
    ) {
        self.router = router
        self.registry = registry
        self.allowedHosts = allowedHosts
        self.onFailure = onFailure
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
        } catch {
            onFailure(url, error)
            return .discarded
        }
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public extension View {
    @MainActor
    /// Installs URLRouter once at the root of a scene.
    func moduleLinkRouting(
        router: ModuleRouter,
        registry: ModuleRouteRegistry,
        allowedHosts: Set<String>,
        onFailure: @escaping (URL, Error) -> Void = { _, _ in }
    ) -> some View {
        modifier(ModuleLinkRoutingModifier(router: router, registry: registry, allowedHosts: allowedHosts, onFailure: onFailure))
    }
}

/// A reusable SwiftUI shell for push, sheet, and full-screen-cover routes.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@MainActor
public struct RouterHost<Root: View, Destination: View>: View {
    @Bindable private var router: ModuleRouter
    private let root: () -> Root
    private let destination: (ModuleRoute) -> Destination

    /// Creates the SwiftUI host that renders module destinations.
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
#if os(macOS)
        NavigationStack(path: $router.path) {
            root().navigationDestination(for: ModuleRoute.self, destination: destination)
        }
        .sheet(isPresented: sheetIsPresented) {
            if let route = router.sheet { destination(route) }
        }
        // SwiftUI does not offer fullScreenCover on macOS. Preserve the route
        // contract by presenting that destination in a sheet on this platform.
        .sheet(isPresented: fullScreenCoverIsPresented) {
            if let route = router.fullScreenCover { destination(route) }
        }
#else
        NavigationStack(path: $router.path) {
            root().navigationDestination(for: ModuleRoute.self, destination: destination)
        }
        .sheet(isPresented: sheetIsPresented) {
            if let route = router.sheet { destination(route) }
        }
        .fullScreenCover(isPresented: fullScreenCoverIsPresented) {
            if let route = router.fullScreenCover { destination(route) }
        }
#endif
    }

    private var sheetIsPresented: Binding<Bool> {
        Binding(get: { router.sheet != nil }, set: { if !$0 { router.dismissSheet() } })
    }

    private var fullScreenCoverIsPresented: Binding<Bool> {
        Binding(get: { router.fullScreenCover != nil }, set: { if !$0 { router.dismissFullScreenCover() } })
    }
}
