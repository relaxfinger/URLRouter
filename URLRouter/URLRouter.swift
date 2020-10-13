//
//  URLRouter.swift
//  URLRouter
//
//  Created by relaxfinger on 2020/4/19.
//  Copyright © 2020 relaxfinger. All rights reserved.
//

import UIKit
import Foundation

public typealias ViewControllerFactory = (_ url: URL, _ paramters: [String: Any], _ completion: CompletionHandler?) -> UIViewController?
public typealias CompletionHandler = (_ values: [String: Any]?) -> Void

public enum Transition {
    case push
    case modal(UIModalPresentationStyle)
    case select(Int)
};

public protocol Callbackable {
    var completion: CompletionHandler? { get }
}

public protocol Destination {
    var transition: Transition { get }
    var controller: ViewControllerFactory { get }
}

open class URLRouter: Router<Destination> {
    public static let shared = URLRouter()
    
    @discardableResult
    public func open(_ url: URL, completion: CompletionHandler? = nil) -> Bool {
        guard UIApplication.shared.canOpenURL(url) else {
            return false
        }
        
        if #available(iOS 10.0, *) {
            UIApplication.shared.open(url, options: [UIApplication.OpenExternalURLOptionsKey(rawValue: "source") : "URLRouter"], completionHandler: nil)
        } else {
            UIApplication.shared.openURL(url)
        }
        
        for i in 0..<self.routes.count {
            if self.routes[i].find(for: url) {
                self.routes[i].completion = completion
            }
        }
        
        return true
    }
    
    @discardableResult
    public func open(_ urlString: String, completion: CompletionHandler? = nil) -> Bool {
        guard let url = URL(string: urlString) else {
            return false
        }
        
        return open(url, completion: completion)
    }
    
    @discardableResult
    public func route(_ url: URL) -> Bool {
        guard let match = self.match(for: url) else { return false }
        guard let topViewController = UIViewController.topMost else { return false }
        
        switch match.destination.transition {
        case .select(let index):
            return switchTo(topViewController, index: index)
        default:
            guard let viewController = match.destination.controller(url, match.parameters, match.completion) else { return false }
            return topViewController.route(viewController, match.destination.transition)
        }
    }
    
    @discardableResult
    public func close(_ url: URL, animated: Bool) -> Bool {
        guard let match = self.match(for: url) else { return false }
        guard let topViewController = UIViewController.topMost else { return false }
        
        switch match.destination.transition {
        case .push:
            guard let navigationController = topViewController.navigationController else { return false }
            navigationController.popViewController(animated: animated)
        case .modal:
            topViewController.dismissKeyBoard()
            topViewController.dismiss(animated: animated, completion: nil)
        default:
            return false
        }
        
        return true
    }
    
    fileprivate func switchTo(_ controller: UIViewController, index: Int) -> Bool {
        if let tabbarController = controller as? UITabBarController {
            tabbarController.selectedIndex = index
        } else if let tabbarController = controller.tabBarController {
            tabbarController.selectedIndex = index
        } else {
            return false
        }
        
        return true
    }
}

extension UIViewController {
    @discardableResult
    func route(_ viewController: UIViewController, _ transition: Transition) -> Bool {
        switch transition {
        case .push:
            if let navigationController = self as? UINavigationController {
                navigationController.pushViewController(viewController, animated: true)
            } else if let navigationController = self.navigationController {
                navigationController.pushViewController(viewController, animated: true)
            } else {
                let navigationController = UINavigationController(rootViewController: viewController)
                viewController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
                
                self.present(navigationController, animated: true, completion: nil)
            }
        case .modal(let style):
            viewController.modalPresentationStyle = style
            self.present(viewController, animated: true, completion: nil)
        
        default:
            return false
        }
        
        return true
    }
    
    @IBAction func cancel() {
        self.presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    fileprivate func dismissKeyBoard() {
        UIApplication.shared.sendAction(#selector(resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
