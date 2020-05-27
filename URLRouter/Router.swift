//
//  Router.swift
//  URLRouter
//
//  Created by relaxfinger on 2020/4/19.
//  Copyright © 2020 relaxfinger. All rights reserved.
//

import Foundation

public protocol URLable {
    var url: URL { get }
    var urlComponents: URLComponents { get }
}


open class Router<DestinationType> {
    struct Match {
        var destination: DestinationType
        var parameters: [String : Any]
        var completion: CompletionHandler?
    }
    
    struct Route {
        var pattern: URLable
        var destination: DestinationType
        var completion: CompletionHandler?
        
        func match(for url: URL) -> Match? {
            guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return nil
            }
            
            guard let scheme = urlComponents.scheme, scheme == self.pattern.urlComponents.scheme else {
                return nil
            }
            
            guard let host = urlComponents.host, host == self.pattern.urlComponents.host else {
                return nil
            }
            
            var parameters: [String : Any] = [:]
            
            let patternComponents = self.pattern.urlComponents.path.components(separatedBy: "/")
            let pathComponents = urlComponents.path.components(separatedBy: "/")
            for (component, input) in zip(patternComponents, pathComponents) {
                if component.first == ":" {
                    parameters[String(component.dropFirst())] = input
                } else if component != input {
                    return nil
                }
            }
            
            if let urlQueryItem = urlComponents.queryItems {
                urlQueryItem.forEach { parameters[$0.name] = $0.value }
            }
            
            return Match(destination:self.destination, parameters: parameters, completion: self.completion)
        }
        
        func find(for url: URL) -> Bool {
            guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return false
            }
            
            guard let scheme = urlComponents.scheme, scheme == self.pattern.urlComponents.scheme else {
                return false
            }
            
            guard let host = urlComponents.host, host == self.pattern.urlComponents.host else {
                return false
            }
        
            let patternComponents = self.pattern.urlComponents.path.components(separatedBy: "/")
            let pathComponents = urlComponents.path.components(separatedBy: "/")
            for (component, input) in zip(patternComponents, pathComponents) {
                if component.first == ":" {
                    continue
                } else if component != input {
                    return false
                }
            }
            
            return true
        }
    }
    
    var routes: Array<Route> = []
    
    public func register(_ pattern: URLable, destination: DestinationType) {
        routes.append(Route(pattern: pattern, destination: destination))
    }
    
    func match(for url: URL) -> Match? {
        for route in routes {
            if let match = route.match(for: url) {
                return match
            }
        }
        
        return nil
    }
    
    init() {
    }
}
