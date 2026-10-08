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

import Foundation
import SwiftUI

/// Unwinds the captured route scope from SwiftUI views.
///
/// ```swift
/// @Environment(\.unwindRoute) private var unwindRoute
///
/// Button("Done") {
///     Task {
///         await unwindRoute()
///     }
/// }
/// ```
public struct UnwindRouteAction: Equatable {
    private let router: Router

    /// Creates an inactive unwind action.
    public init() { router = .inactive }

    init(router: RouterEngine, routeScope: RouteScope) {
        self.router = Router(engine: router, scope: routeScope)
    }

    /// Unwinds the captured route scope.
    ///
    /// This method returns after the unwind request has resolved, the router path has been updated,
    /// and any removed installed route scopes have left the view hierarchy.
    @discardableResult
    public func callAsFunction() async -> Bool {
        await router.unwind(to: .topmostAncestor)
    }

    /// Unwinds the captured route scope and delivers a payload to a matching ``UnwindHandler``.
    ///
    /// This method returns after the unwind request has resolved, the router path has been updated,
    /// and any removed installed route scopes have left the view hierarchy.
    @discardableResult
    public func callAsFunction<Payload>(payload: Payload) async -> Bool {
        await router.unwind(to: .topmostAncestor, payload: payload)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.router == rhs.router }
}

/// The current routing phase for a view's local route scope.
public enum RoutePhase: Equatable, Sendable {
    /// This view's route scope is current within its participating branch.
    case active

    /// This view's scope is behind another destination or belongs to an unselected exclusive branch.
    case inactive
}

private struct RoutingEnvironmentReference {
    weak var engine: RouterEngine?
    weak var scope: RouteScope?
}

@propertyWrapper
struct RouterEnvironment: DynamicProperty {
    @Environment(\.routerEngine) private var engine

    var wrappedValue: RouterEngine {
        guard let engine else {
            preconditionFailure("A routing view requires a live WithRouter owner.")
        }
        return engine
    }
}

extension EnvironmentValues {
    @Entry private var routingReference = RoutingEnvironmentReference()

    var routeScope: RouteScope? {
        get { routingReference.scope }
        set { routingReference.scope = newValue }
    }

    var routerEngine: RouterEngine? {
        get { routingReference.engine }
        set { routingReference.engine = newValue }
    }

}

public extension EnvironmentValues {
    /// The router bound to this view's route scope, or an inactive router outside `WithRouter`.
    @Entry var router = Router.inactive

    /// Unwinds the captured route scope.
    @Entry var unwindRoute = UnwindRouteAction()

    /// The current routing phase for this view's local route scope.
    ///
    /// This value is local to the view hierarchy it is read from. The current route destination,
    /// branch root, or root content reads ``RoutePhase/active``; installed scopes behind another
    /// route read ``RoutePhase/inactive``.
    @Entry var routePhase = RoutePhase.inactive
}

extension View {
    func routeScopeEnvironment(_ routeScope: RouteScope) -> some View {
        environment(\.routeScope, routeScope)
    }

    func routeScopeEnvironment(_ routeScope: RouteScope, router: RouterEngine) -> some View {
        self
            .environment(\.routeScope, routeScope)
            .environment(\.router, Router(engine: router, scope: routeScope))
            .environment(\.routePhase, router.routePhase(for: routeScope))
            .environment(\.unwindRoute, UnwindRouteAction(router: router, routeScope: routeScope))
    }
}

extension RouterEngine {
    func routePhase(for routeScope: RouteScope) -> RoutePhase {
        _ = activeRouteScopeID
        guard let path = spaces.routePath(containing: routeScope),
              let space = spaces.space(containing: path), space === spaces.activeSpace else { return .inactive }
        // A modal suspends scopes outside its subtree. Concurrent columns hosted
        // inside that modal still participate together.
        if let deepestModal = space.currentModalScope {
            var ancestor: RouteScope? = routeScope
            while let current = ancestor, current !== deepestModal {
                ancestor = current.previousScopeInSpace
            }
            guard ancestor === deepestModal else { return .inactive }
        }
        var scope = routeScope
        while let previous = scope.previousScopeInSpace {
            if let branch = scope.branchID,
               previous.participates(inBranch: branch) == false { return .inactive }
            scope = previous
        }
        let current = path.last?.activeLocalScope ?? path.owner?.activeLocalScope
        return current === routeScope ? .active : .inactive
    }
}
