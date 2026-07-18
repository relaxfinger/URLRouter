//
//  RoutePolicy.swift
//  URLRouter
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import Foundation

/// An error emitted when a route violates the app shell's routing policy.
public enum ModuleRoutePolicyError: Error, Equatable, Sendable, LocalizedError {
    case missingContractVersion(queryItem: String)
    case unsupportedContractVersion(String)
    case presentationNotAllowed(ModulePresentationStyle)
    case moduleDisabled(String)
    case unauthorized(moduleID: String, routeID: String)

    public var errorDescription: String? {
        switch self {
        case .missingContractVersion(let queryItem): "The route requires the \(queryItem) contract version."
        case .unsupportedContractVersion(let version): "The route contract version \(version) is not supported."
        case .presentationNotAllowed(let style): "The \(style.rawValue) presentation is not allowed."
        case .moduleDisabled(let id): "The \(id) module is disabled."
        case .unauthorized(let moduleID, let routeID): "The current user is not authorized for \(moduleID)/\(routeID)."
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
        failureDescription: String? = nil
    ) {
        self.traceID = traceID
        self.timestamp = timestamp
        self.outcome = outcome
        self.host = host
        self.moduleID = moduleID
        self.routeID = routeID
        self.presentation = presentation
        self.failureDescription = failureDescription
    }
}
