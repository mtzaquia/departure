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

/// Reads an unwind action using the same policy as ``Router/unwind(_:)``.
///
/// ```swift
/// @UnwindRoute private var unwindRoute
/// @UnwindRoute(.nearestModal) private var unwindModal
/// @UnwindRoute(CheckoutRoute.self) private var unwindCheckout
/// ```
///
/// Lookup includes the current destination and follows its ancestry within the
/// receiving priority space. Sibling branches and other spaces are never searched.
/// Each read captures the destination it will dismiss. A retained action never
/// retargets a replacement instance. It remains usable while that destination is
/// live, even after the child that read it has popped.
/// A missing target returns `false` and emits a warning when invoked, including
/// in Release builds and when debug logging is disabled.
@propertyWrapper
@MainActor
public struct UnwindRoute: DynamicProperty {
    @Environment(\.routerEngine) private var engine
    @Environment(\.routeScope) private var scope
    private let selection: RouterEngine.UnwindSelection

    /// Reads an action for an unwind policy, defaulting to the current destination.
    /// - Parameter target: The same policy accepted by ``Router/unwind(_:)``.
    public init(_ target: Router.UnwindTarget = .current) { selection = .policy(target) }

    /// Reads an action that dismisses the nearest live occurrence of the exact route type.
    /// - Parameter route: The exact route type to dismiss, including its descendants.
    public init<R: Route>(_ route: R.Type) { selection = .routeType(route) }

    /// The action captured from this view's scope and the resolved policy boundary.
    ///
    /// Calling the action observes live-scope authority, covered-space restrictions,
    /// payload delivery, and native teardown completion in the shared unwind engine.
    public var wrappedValue: UnwindRouteAction {
        guard let engine else {
            return selection == .policy(.current) ? UnwindRouteAction() : UnwindRouteAction(missing: selection)
        }
        return engine.unwindRouteAction(from: scope, selection: selection)
    }
}

extension RouterEngine {
    func unwindRouteAction(from source: RouteScope?, target: UnwindTarget = .current) -> UnwindRouteAction {
        unwindRouteAction(from: source, selection: .policy(target))
    }

    func unwindRouteAction(from source: RouteScope?, selection: UnwindSelection) -> UnwindRouteAction {
        guard let source, let target = resolveUnwind(selection, from: source) else {
            return selection == .policy(.current) ? UnwindRouteAction() : UnwindRouteAction(missing: selection)
        }
        return UnwindRouteAction(router: self, routeScope: target)
    }
}
