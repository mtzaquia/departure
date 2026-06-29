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
import Observation

/// The routing engine installed by ``WithRouter``.
///
/// Consumer views read the router from the environment, then send commands through it.
///
/// ```swift
/// @Environment(Router.self) private var router
///
/// Button("Settings") {
///     Task {
///         await router.present(SettingsRoute())
///     }
/// }
/// ```
@Observable
public final class Router: Identifiable, Equatable {
    /// A destination for ``Router/unwind(to:)``.
    public enum UnwindTarget {
        /// Unwinds every presented route across all branches and scopes, returning to the app's start.
        case root

        /// Unwinds to the first scope of the nearest enclosing branch.
        ///
        /// Brings the user to the branch's root regardless of how deep the current route is. If the
        /// user is already at the branch root — or is not inside a branch — this is a no-op.
        case nearestBranch

        /// Unwinds to the scope that was declared with a matching ``SwiftUICore/View/routes(id:_:)`` ID.
        case id(AnyHashable)
    }

    /// Stable identity for this router instance.
    @ObservationIgnored public let id = UUID()

    @ObservationIgnored
    let root: RouteScope

    @ObservationIgnored
    let normalTree: RouteTree

    var routeForest: RouteForest

    @ObservationIgnored
    var pendingRoute: PendingRoute?

    @ObservationIgnored
    var unwindPresentationSnapshot: UnwindPresentationSnapshot?

    @ObservationIgnored
    var isNavigationInProgress = false

    @ObservationIgnored
    var deliveredUnwindHandlers: [UnwindHandlerDeliveryKey: DeliveredUnwindHandler] = [:]

    @ObservationIgnored
    var routeGraphMutationDepth = 0

    var activeRouteScopeIDs: Set<ObjectIdentifier>

    var currentRouteScope: RouteScope {
        routeForest.activeTree.currentRouteScope
    }

    /// Creates an empty router.
    public init() {
        let root = RouteScope(id: UUID(), route: nil)
        let rootPath = RoutePath(owner: root)
        self.root = root
        let normalTree = RouteTree(priority: .normal, root: root, rootPath: rootPath)
        self.normalTree = normalTree
        self.routeForest = RouteForest(normalTree: normalTree)
        self.activeRouteScopeIDs = normalTree.activeRouteScopeIDs
    }

    /// Requests a route presentation.
    ///
    /// This method returns after the request has resolved and the router has updated its routing state.
    /// It does not wait for SwiftUI to mount or display the destination view.
    public func present(_ route: any Route) async {
        await requestRouteWhenReady(route)
    }

    /// Dismisses route scopes.  If no parameter is provided, it dismisses the current route.
    ///
    /// This method returns after the unwind request has resolved, the router path has been updated,
    /// and any removed installed route scopes have left the view hierarchy.
    ///
    /// - Parameter target: The target to unwind to, or `nil` for the route to just dismiss itself.
    /// - Returns: `false` when an explicit target was requested but not found.
    @discardableResult
    public func unwind(to target: UnwindTarget? = nil) async -> Bool {
        await unwindAndWait(to: target)
    }

    /// Dismisses route scopes, delivering a payload to a matching ``UnwindHandler``.
    ///
    /// This method returns after the unwind request has resolved, the router path has been updated,
    /// and any removed installed route scopes have left the view hierarchy.
    ///
    /// - Parameters:
    ///   - target: The target to unwind to, or `nil` for the route to just dismiss itself.
    ///   - payload: A value delivered to a matching ``UnwindHandler``.
    /// - Returns: `false` when an explicit target was requested but not found.
    @discardableResult
    public func unwind<Payload>(to target: UnwindTarget? = nil, payload: Payload) async -> Bool {
        await unwindAndWait(to: target, payload: payload)
    }

    /// Performs an action from the current route scope.
    public func perform(_ action: any Action) async {
        await performAction(action)
    }

    public static func == (lhs: Router, rhs: Router) -> Bool {
        lhs.id == rhs.id
    }
}

extension Router {
    func mutateRouteGraph(_ mutation: () -> Void) {
        routeGraphMutationDepth += 1
        mutation()
        routeGraphMutationDepth -= 1

        if routeGraphMutationDepth == 0 {
            reconcileActiveRouteScopeID()
        }
    }

    private func reconcileActiveRouteScopeID() {
        let routeScopeIDs = routeForest.activeTree.activeRouteScopeIDs
        if activeRouteScopeIDs != routeScopeIDs {
            activeRouteScopeIDs = routeScopeIDs
        }
    }
}
