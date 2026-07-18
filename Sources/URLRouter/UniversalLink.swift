//
//  Router.swift
//  URLRouter
//
//  Copyright (c) 2026 relaxfinger
//  SPDX-License-Identifier: MIT
//

import Foundation

/// A validated HTTPS Universal Link, independent from any UI framework.
public struct UniversalLink: Hashable, Sendable {
    public let host: String
    public let pathComponents: [String]
    public let query: [String: String]

    public init(url: URL, allowedHosts: Set<String>) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw UniversalLinkError.invalidURL
        }
        guard components.scheme?.lowercased() == "https" else {
            throw UniversalLinkError.unsupportedScheme
        }
        guard components.user == nil, components.password == nil else {
            throw UniversalLinkError.credentialsAreNotAllowed
        }
        guard components.port == nil || components.port == 443 else {
            throw UniversalLinkError.unsupportedPort
        }
        guard let host = components.host?.lowercased(), allowedHosts.contains(where: { $0.lowercased() == host }) else {
            throw UniversalLinkError.untrustedHost
        }
        guard components.fragment == nil else {
            throw UniversalLinkError.fragmentIsNotAllowed
        }

        self.host = host
        self.pathComponents = try components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { segment in
                guard let decoded = String(segment).removingPercentEncoding,
                      !decoded.contains("/") else {
                    throw UniversalLinkError.invalidPathEncoding
                }
                return decoded
            }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else {
                throw UniversalLinkError.missingQueryValue(item.name)
            }
            guard query[item.name] == nil else {
                throw UniversalLinkError.duplicateQueryItem(item.name)
            }
            query[item.name] = value
        }
        self.query = query
    }
}

public enum UniversalLinkError: Error, Equatable, Sendable, LocalizedError {
    case invalidURL, unsupportedScheme, credentialsAreNotAllowed, unsupportedPort
    case untrustedHost, fragmentIsNotAllowed, invalidPathEncoding, unsupportedRoute
    case missingQueryValue(String), duplicateQueryItem(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "The URL cannot be parsed."
        case .unsupportedScheme: "Universal Links must use HTTPS."
        case .credentialsAreNotAllowed: "URLs containing credentials are not accepted."
        case .unsupportedPort: "Only the default HTTPS port is accepted."
        case .untrustedHost: "The Universal Link host is not allowed."
        case .fragmentIsNotAllowed: "Universal Links must not contain a fragment."
        case .invalidPathEncoding: "The URL path contains an invalid encoded segment."
        case .missingQueryValue(let name): "The query item \(name) requires a value."
        case .duplicateQueryItem(let name): "The query item \(name) appears more than once."
        case .unsupportedRoute: "The Universal Link does not map to a route."
        }
    }
}
