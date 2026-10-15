//
//  Copyright (c) 2026 @mtzaquia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import SwiftUI

/// Reads an unwind action for this destination or its nearest matching ancestor route.
///
/// Use `@UnwindRoute` to dismiss the current route scope, or supply a route type
/// to dismiss that route and its descendants without passing an action through views.
/// Lookup includes the current scope and follows its logical ancestry within its
/// priority space; sibling branches and other spaces are never searched.
///
/// ```swift
/// @UnwindRoute private var unwindRoute
/// @UnwindRoute(CheckoutRoute.self) private var unwindCheckout
/// ```
///
/// Each read captures the exact matched scope. Retained actions never retarget
/// another instance after that scope is removed. A missing match produces an
/// inactive action that returns `false` and emits a warning when invoked,
/// including in Release builds and when debug logging is disabled.
@propertyWrapper
@MainActor
public struct UnwindRoute: DynamicProperty {
    @Environment(\.routerEngine) private var engine
    @Environment(\.routeScope) private var scope
    private let routeType: (any Route.Type)?

    /// Reads a local action that dismisses the current destination and its descendants.
    public init() { routeType = nil }

    /// Reads an action for the nearest live occurrence of a route type in this scope's ancestry.
    /// - Parameter route: The exact route type to match, including the current destination.
    public init<R: Route>(_ route: R.Type) { routeType = route }

    /// The action captured from the current scope or the nearest matching ancestor.
    ///
    /// Outside a live router scope, the action is inactive. Calling the action
    /// observes the existing unwind rules, including covered-space restrictions
    /// and native teardown completion.
    public var wrappedValue: UnwindRouteAction {
        guard let engine else {
            return routeType.map { UnwindRouteAction(missing: $0) } ?? UnwindRouteAction()
        }
        return engine.unwindRouteAction(from: scope, matching: routeType)
    }
}

extension RouterEngine {
    func unwindRouteAction(from source: RouteScope?, matching routeType: (any Route.Type)? = nil) -> UnwindRouteAction {
        guard let source, let path = spaces.routePath(containing: source),
              let space = spaces.space(containing: path) else {
            return routeType.map { UnwindRouteAction(missing: $0) } ?? UnwindRouteAction()
        }
        guard let routeType else { return UnwindRouteAction(router: self, routeScope: source) }
        for scope in source.ancestry {
            guard scope.space === space, spaces.routePath(containing: scope) != nil else { break }
            if let route = scope.route, ObjectIdentifier(type(of: route)) == ObjectIdentifier(routeType) {
                return UnwindRouteAction(router: self, routeScope: scope)
            }
        }
        return UnwindRouteAction(missing: routeType)
    }
}
