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
    private enum Identity: Equatable {
        case inactive
        case routeScope(routerID: UUID, routeScopeID: ObjectIdentifier)
    }

    private let identity: Identity
    private let handler: Handler?

    /// Creates an inactive unwind action.
    public init() {
        self.identity = .inactive
        self.handler = nil
    }

    init(router: RouterEngine, routeScope: RouteScope) {
        self.identity = .routeScope(
            routerID: router.id,
            routeScopeID: ObjectIdentifier(routeScope)
        )
        self.handler = Handler(router: router, routeScope: routeScope)
    }

    /// Unwinds the captured route scope.
    ///
    /// This method returns after the unwind request has resolved, the router path has been updated,
    /// and any removed installed route scopes have left the view hierarchy.
    @discardableResult
    public func callAsFunction() async -> Bool {
        await handler?.unwind(payload: nil) ?? false
    }

    /// Unwinds the captured route scope and delivers a payload to a matching ``UnwindHandler``.
    ///
    /// This method returns after the unwind request has resolved, the router path has been updated,
    /// and any removed installed route scopes have left the view hierarchy.
    @discardableResult
    public func callAsFunction<Payload>(payload: Payload) async -> Bool {
        await handler?.unwind(payload: payload) ?? false
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity
    }

    private final class Handler {
        let router: RouterEngine
        weak var routeScope: RouteScope?

        init(router: RouterEngine, routeScope: RouteScope) {
            self.router = router
            self.routeScope = routeScope
        }

        func unwind(payload: Any?) async -> Bool {
            guard let routeScope else {
                return false
            }

            return await router.unwindPrevious(from: routeScope, payload: payload)
        }
    }
}

/// The current routing phase for a view's local route scope.
public enum RoutePhase: Equatable, Sendable {
    /// This view's route scope is current within its participating branch.
    case active

    /// This view's scope is behind another destination or belongs to an unselected exclusive branch.
    case inactive
}

extension EnvironmentValues {
    @Entry var routeScope: RouteScope?
    @Entry var unscopedRouter = Router.inactive
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

public extension Environment where Value == Router {
    /// Reads the unscoped router using the legacy type-based spelling.
    ///
    /// Unlike `@Environment(\.router)`, this router searches without a captured
    /// view scope. Both spellings are inactive outside `WithRouter`.
    /// - Parameter type: The router type identifying the compatibility lookup.
    @available(*, deprecated, message: "Use @Environment(\\.router) instead.")
    init(_ type: Router.Type) {
        self.init(\.unscopedRouter)
    }
}

extension View {
    func routeScopeEnvironment(_ routeScope: RouteScope) -> some View {
        environment(\.routeScope, routeScope)
    }

    func routeScopeEnvironment(_ routeScope: RouteScope, router: RouterEngine) -> some View {
        self
            .environment(\.routeScope, routeScope)
            .environment(\.router, Router(engine: router, scope: routeScope))
            .environment(\.unscopedRouter, Router(engine: router))
            .environment(\.routePhase, router.routePhase(for: routeScope))
            .environment(\.unwindRoute, UnwindRouteAction(router: router, routeScope: routeScope))
    }
}

extension RouterEngine {
    func routePhase(for routeScope: RouteScope) -> RoutePhase {
        _ = activeRouteScopeID
        _ = routeScope.participation.isBranchHostRegistered
        guard let path = routeForest.routePath(containing: routeScope),
              let tree = routeForest.tree(containing: path), tree === routeForest.activeTree else { return .inactive }
        // A modal suspends scopes outside its subtree. Concurrent columns hosted
        // inside that modal still participate together.
        if let deepestModal = tree.currentModalScope {
            var ancestor: RouteScope? = routeScope
            while let current = ancestor, current !== deepestModal {
                ancestor = current.previousScopeInTree
            }
            guard ancestor === deepestModal else { return .inactive }
        }
        var scope = routeScope
        while let previous = scope.previousScopeInTree {
            if let branch = scope.branchID,
               previous.participates(inBranch: branch) == false { return .inactive }
            scope = previous
        }
        let current = path.last?.activeLocalScope ?? path.owner?.activeLocalScope
        return current === routeScope ? .active : .inactive
    }
}
