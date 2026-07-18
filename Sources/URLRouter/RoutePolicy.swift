//
//  RoutePolicy.swift
//  URLRouter
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import Foundation
import Observation

/// An error emitted when a route violates the app shell's routing policy.
public enum ModuleRoutePolicyError: Error, Equatable, Sendable, LocalizedError {
    case missingContractVersion(queryItem: String)
    case unsupportedContractVersion(String)
    case presentationNotAllowed(ModulePresentationStyle)
    case moduleDisabled(String)
    case unauthorized(moduleID: String, routeID: String)
    case routingSuspended

    public var errorDescription: String? {
        switch self {
        case .missingContractVersion(let queryItem): "The route requires the \(queryItem) contract version."
        case .unsupportedContractVersion(let version): "The route contract version \(version) is not supported."
        case .presentationNotAllowed(let style): "The \(style.rawValue) presentation is not allowed."
        case .moduleDisabled(let id): "The \(id) module is disabled."
        case .unauthorized(let moduleID, let routeID): "The current user is not authorized for \(moduleID)/\(routeID)."
        case .routingSuspended: "Routing is temporarily suspended by the app shell."
        }
    }
}

/// A Codable, remotely-delivered restriction layer for the app shell.
///
/// Fetch, authenticate, cache, and roll back this value in the host application.
/// The router deliberately performs no network access and this configuration can
/// only make a local policy stricter; it cannot grant authorization.
public struct ModuleRouteRemotePolicy: Codable, Equatable, Sendable {
    /// Stops all module routing immediately. Use for incident mitigation.
    public let isCircuitBreakerOpen: Bool
    /// Additional accepted contract versions. `nil` leaves version governance to the local policy.
    public let acceptedContractVersions: Set<String>?
    /// Whether the remote policy permits links without a contract version.
    public let allowsUnversionedLinks: Bool
    /// Modules disabled by a remote feature flag or emergency switch.
    public let disabledModuleIDs: Set<String>
    /// When present, only these modules remain available.
    public let enabledModuleIDs: Set<String>?
    /// When present, only these presentation styles remain available.
    public let allowedPresentationStyles: Set<ModulePresentationStyle>?

    public init(
        isCircuitBreakerOpen: Bool = false,
        acceptedContractVersions: Set<String>? = nil,
        allowsUnversionedLinks: Bool = true,
        disabledModuleIDs: Set<String> = [],
        enabledModuleIDs: Set<String>? = nil,
        allowedPresentationStyles: Set<ModulePresentationStyle>? = nil
    ) {
        self.isCircuitBreakerOpen = isCircuitBreakerOpen
        self.acceptedContractVersions = acceptedContractVersions
        self.allowsUnversionedLinks = allowsUnversionedLinks
        self.disabledModuleIDs = disabledModuleIDs
        self.enabledModuleIDs = enabledModuleIDs
        self.allowedPresentationStyles = allowedPresentationStyles
    }

    fileprivate func validate(_ link: UniversalLink, presentation: ResolvedModuleRoute, queryItem: String) throws {
        guard !isCircuitBreakerOpen else { throw ModuleRoutePolicyError.routingSuspended }
        if let acceptedContractVersions {
            guard let version = link.query[queryItem] else {
                guard allowsUnversionedLinks else {
                    throw ModuleRoutePolicyError.missingContractVersion(queryItem: queryItem)
                }
                return try validateRoute(presentation)
            }
            guard acceptedContractVersions.contains(version) else {
                throw ModuleRoutePolicyError.unsupportedContractVersion(version)
            }
        }
        try validateRoute(presentation)
    }

    private func validateRoute(_ presentation: ResolvedModuleRoute) throws {
        guard !disabledModuleIDs.contains(presentation.route.moduleID) else {
            throw ModuleRoutePolicyError.moduleDisabled(presentation.route.moduleID)
        }
        if let enabledModuleIDs {
            guard enabledModuleIDs.contains(presentation.route.moduleID) else {
                throw ModuleRoutePolicyError.moduleDisabled(presentation.route.moduleID)
            }
        }
        if let allowedPresentationStyles {
            guard allowedPresentationStyles.contains(presentation.presentation) else {
                throw ModuleRoutePolicyError.presentationNotAllowed(presentation.presentation)
            }
        }
    }
}

/// Governs which URL contracts the app shell accepts.
///
/// Keep this policy in the app shell so Feature Packages remain independent from
/// identity providers, remote configuration, and analytics vendors.
@MainActor
public struct ModuleRoutePolicy {
    /// Accepted values of the URL contract-version query item. `nil` accepts all versions.
    public let acceptedContractVersions: Set<String>?
    /// The query item used to carry a route-contract version.
    public let contractVersionQueryItem: String
    /// Whether URLs without a contract version are accepted during migrations.
    public let allowsUnversionedLinks: Bool
    /// Presentation styles available in this app shell.
    public let allowedPresentationStyles: Set<ModulePresentationStyle>

    private let isModuleEnabled: (String) -> Bool
    private let isAuthorized: (ModuleRoute, UniversalLink) -> Bool

    /// Creates a policy. The default accepts every backward-compatible route.
    public init(
        acceptedContractVersions: Set<String>? = nil,
        contractVersionQueryItem: String = "version",
        allowsUnversionedLinks: Bool = true,
        allowedPresentationStyles: Set<ModulePresentationStyle> = Set(ModulePresentationStyle.allCases),
        isModuleEnabled: @escaping (String) -> Bool = { _ in true },
        isAuthorized: @escaping (ModuleRoute, UniversalLink) -> Bool = { _, _ in true }
    ) {
        self.acceptedContractVersions = acceptedContractVersions
        self.contractVersionQueryItem = contractVersionQueryItem
        self.allowsUnversionedLinks = allowsUnversionedLinks
        self.allowedPresentationStyles = allowedPresentationStyles
        self.isModuleEnabled = isModuleEnabled
        self.isAuthorized = isAuthorized
    }

    /// A policy that preserves URLRouter's default permissive behavior.
    public static let permissive = ModuleRoutePolicy()

    func validate(_ link: UniversalLink, presentation: ResolvedModuleRoute) throws {
        if let acceptedContractVersions {
            guard let version = link.query[contractVersionQueryItem] else {
                guard allowsUnversionedLinks else {
                    throw ModuleRoutePolicyError.missingContractVersion(queryItem: contractVersionQueryItem)
                }
                return try validateRoute(link, presentation: presentation)
            }
            guard acceptedContractVersions.contains(version) else {
                throw ModuleRoutePolicyError.unsupportedContractVersion(version)
            }
        }
        try validateRoute(link, presentation: presentation)
    }

    private func validateRoute(_ link: UniversalLink, presentation: ResolvedModuleRoute) throws {
        guard allowedPresentationStyles.contains(presentation.presentation) else {
            throw ModuleRoutePolicyError.presentationNotAllowed(presentation.presentation)
        }
        guard isModuleEnabled(presentation.route.moduleID) else {
            throw ModuleRoutePolicyError.moduleDisabled(presentation.route.moduleID)
        }
        guard isAuthorized(presentation.route, link) else {
            throw ModuleRoutePolicyError.unauthorized(
                moduleID: presentation.route.moduleID,
                routeID: presentation.route.routeID
            )
        }
    }
}

/// Holds a local policy and its atomically replaceable remote restrictions.
///
/// Keep one store for each app scene or app shell. Replacing its remote policy
/// affects the next route immediately, enabling safe rollout and emergency
/// circuit breaking without an app release.
@MainActor
@Observable
public final class ModuleRoutePolicyStore {
    public let localPolicy: ModuleRoutePolicy
    public private(set) var remotePolicy: ModuleRouteRemotePolicy?

    public init(
        localPolicy: ModuleRoutePolicy = .permissive,
        remotePolicy: ModuleRouteRemotePolicy? = nil
    ) {
        self.localPolicy = localPolicy
        self.remotePolicy = remotePolicy
    }

    /// Replaces the current remote restrictions after the host has validated them.
    public func replaceRemotePolicy(with policy: ModuleRouteRemotePolicy?) {
        remotePolicy = policy
    }

    func validate(_ link: UniversalLink, presentation: ResolvedModuleRoute) throws {
        try localPolicy.validate(link, presentation: presentation)
        try remotePolicy?.validate(
            link,
            presentation: presentation,
            queryItem: localPolicy.contractVersionQueryItem
        )
    }
}

/// The outcome of a URL routing attempt.
public enum ModuleRouteEventOutcome: String, Hashable, Sendable {
    case handled
    case systemAction
    case discarded
}

/// A privacy-conscious routing event for application telemetry.
public struct ModuleRouteEvent: Hashable, Sendable {
    /// A unique ID that correlates this handling attempt with application logs.
    public let traceID: UUID
    public let timestamp: Date
    public let outcome: ModuleRouteEventOutcome
    public let host: String?
    public let moduleID: String?
    public let routeID: String?
    public let presentation: ModulePresentationStyle?
    /// A stable, privacy-safe category suitable for metrics and alerting.
    public let failureCode: String?
    /// A stable error description without exposing URL query values.
    public let failureDescription: String?

    public init(
        traceID: UUID = UUID(),
        timestamp: Date = Date(),
        outcome: ModuleRouteEventOutcome,
        host: String?,
        moduleID: String? = nil,
        routeID: String? = nil,
        presentation: ModulePresentationStyle? = nil,
        failureCode: String? = nil,
        failureDescription: String? = nil
    ) {
        self.traceID = traceID
        self.timestamp = timestamp
        self.outcome = outcome
        self.host = host
        self.moduleID = moduleID
        self.routeID = routeID
        self.presentation = presentation
        self.failureCode = failureCode
        self.failureDescription = failureDescription
    }
}

/// A vendor-neutral destination for routing telemetry.
@MainActor
public protocol ModuleRouteObserving: AnyObject {
    func record(_ event: ModuleRouteEvent)
}

/// Fans route events out to the app's logging, metrics, and tracing adapters.
@MainActor
public final class ModuleRouteObservability {
    private var observers: [any ModuleRouteObserving]

    public init(observers: [any ModuleRouteObserving] = []) {
        self.observers = observers
    }

    public func addObserver(_ observer: any ModuleRouteObserving) {
        observers.append(observer)
    }

    public func record(_ event: ModuleRouteEvent) {
        observers.forEach { $0.record(event) }
    }
}
