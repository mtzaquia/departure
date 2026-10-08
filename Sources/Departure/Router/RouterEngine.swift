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

@Observable
final class RouterEngine: Identifiable, Equatable {
    typealias UnwindTarget = Router.UnwindTarget

    /// Stable identity for this router instance.
    @ObservationIgnored let id = UUID()

    @ObservationIgnored private var isConfigured = false

    var spaces: RouteSpaces

    @ObservationIgnored
    var pendingRoute: PendingNavigation?

    /// Operations retain their outgoing projections until native teardown completes.
    var navigationOperations: [NavigationOperation] = []

    var isNavigating: Bool { !navigationOperations.isEmpty }

    var hasOutgoingPresentations: Bool {
        navigationOperations.contains { !$0.outgoing.isEmpty }
    }

    @ObservationIgnored
    var deliveredUnwindHandlers: [UnwindHandlerDeliveryKey: DeliveredUnwindHandler] = [:]

    @ObservationIgnored
    var routeGraphMutationDepth = 0

    @ObservationIgnored
    var ios17NavigationStackPushWorkaround: (any IOS17NavigationStackPushWorkaroundHandling)? =
        IOS17NavigationStackPushWorkaroundFactory.makeForCurrentPlatform()

    @ObservationIgnored
    var windowDestinationBuilder = WindowDestinationBuilder.passthrough

    var activeRouteScopeID: ObjectIdentifier { ObjectIdentifier(currentRouteScope) }

    var root: RouteScope {
        spaces.normalSpace.root
    }

    var normalSpace: RouteSpace {
        spaces.normalSpace
    }

    var currentRouteScope: RouteScope {
        spaces.activeSpace.currentRouteScope
    }

    /// Creates an empty router.
    init(routes: RootRouteMap? = nil) {
        let root = RouteScope(id: UUID(), route: nil)
        if let routes {
            isConfigured = true
            if let id = routes.scopeID { root.id = id }
            root.useDefinitions(RouteDefinitions(routes.declarations))
        }
        let normalSpace = RouteSpace(priority: .normal, root: root)
        self.spaces = RouteSpaces(normalSpace: normalSpace)
    }

    func configureMap(_ map: RootRouteMap) {
        guard !isConfigured else { return }
        isConfigured = true
        if let id = map.scopeID { root.id = id }
        root.useDefinitions(RouteDefinitions(map.declarations))
    }

    /// Requests a route presentation.
    ///
    /// This method returns after the request has resolved and the router has updated its routing state.
    /// It does not wait for SwiftUI to mount or display the destination view.
    func present(_ route: any Route) async {
        await requestRouteWhenReady(route)
    }

    /// Dismisses route scopes to an explicit target.
    ///
    /// This method returns after the unwind request has resolved, the router path has been updated,
    /// and any removed installed route scopes have left the view hierarchy.
    ///
    /// - Parameter target: The target to unwind to.
    /// - Returns: `false` when no route can be unwound or an ``UnwindTarget/id(_:)`` target is not found.
    @discardableResult
    func unwind(to target: UnwindTarget) async -> Bool {
        await unwindAndWait(to: target)
    }

    /// Dismisses route scopes to an explicit target, delivering a payload to a matching ``UnwindHandler``.
    ///
    /// This method returns after the unwind request has resolved, the router path has been updated,
    /// and any removed installed route scopes have left the view hierarchy.
    ///
    /// - Parameters:
    ///   - target: The target to unwind to.
    ///   - payload: A value delivered to a matching ``UnwindHandler``.
    /// - Returns: `false` when no route can be unwound or an ``UnwindTarget/id(_:)`` target is not found.
    @discardableResult
    func unwind<Payload>(to target: UnwindTarget, payload: Payload) async -> Bool {
        await unwindAndWait(to: target, payload: payload)
    }

    /// Performs an action from the current route scope.
    func perform(_ action: any Action) async {
        await performAction(action)
    }

    static func == (lhs: RouterEngine, rhs: RouterEngine) -> Bool {
        lhs.id == rhs.id
    }
}

extension RouterEngine {
    func mutateRouteGraph(_ mutation: () -> Void) {
        routeGraphMutationDepth += 1
        mutation()
        routeGraphMutationDepth -= 1

        if routeGraphMutationDepth == 0 {
            ios17NavigationStackPushWorkaround?.routeGraphDidMutate(in: self)
            #if DEBUG
            spaces.validateInvariants()
            #endif
        }
    }

    func isNavigationEligible(_ scope: RouteScope) -> Bool {
        scope.belongs(to: spaces.activeSpace)
    }

    func bindBranchSelection(_ selection: AnyRouteBranchSelection, in scope: RouteScope) {
        guard isNavigationEligible(scope) else {
            _ = selection.setValue(scope.activeBranch)
            return
        }
        scope.bindBranchSelection(selection)
    }

    func navigationSource(_ origin: RouteRequestOrigin?) -> RouteScope? {
        guard let scope = resolveRequestOrigin(origin), isNavigationEligible(scope) else { return nil }
        return scope
    }

    /// Resolves a command's captured origin; an absent origin is the internal
    /// current-scope lookup used by engine operations.
    func resolveRequestOrigin(_ origin: RouteRequestOrigin?) -> RouteScope? {
        if let origin { return origin.resolve(in: spaces) }
        return currentRouteScope
    }

}
