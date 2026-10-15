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

/// A scope-bound navigation handle supplied by `WithRouter` or `RouteContext`.
/// Stored routers retain their source identity and become inactive when that scope
/// leaves navigation. Read ``RootRouter/default`` for external entry points or
/// ``RootRouter/current`` to capture a source in the top space.
/// Live scopes in that space may issue commands even when their ``RoutePhase`` is
/// inactive. Covered or removed scopes cannot issue commands.
public struct Router: Equatable {
    /// A policy shared by ``Router/unwind(_:)`` and ``UnwindRoute``.
    public enum UnwindTarget: Equatable {
        /// Dismisses the captured destination and its descendants.
        /// An elevated root removes its space; the permanent default root returns `false`.
        case current

        /// Dismisses the nearest enclosing sheet or cover, including its pushed descendants.
        /// Includes the current destination and stays within its priority space.
        case nearestModal

        /// Resets navigation in the receiving space, keeping its root and outer presentation.
        case root
    }

    private weak var referencedEngine: RouterEngine?
    var engine: RouterEngine? { referencedEngine }
    let origin: RouteRequestOrigin?

    init(engine: RouterEngine) {
        self.init(engine: engine, scope: engine.currentRouteScope)
    }

    init(engine: RouterEngine, scope: RouteScope) {
        self.init(engine: engine, origin: RouteRequestOrigin(scope: scope))
    }

    private init(engine: RouterEngine?, origin: RouteRequestOrigin?) {
        self.referencedEngine = engine
        self.origin = origin
    }

    static let inactive = Router(engine: nil, origin: nil)

    /// Returns a router targeting a named branch of the nearest enclosing container.
    /// External callers can capture a default flow router through ``RootRouter/default``.
    ///
    /// Obtaining the router does not activate the branch. A presentation owned by
    /// the branch activates it through the container's selection binding. A missing
    /// branch produces an inactive command rather than falling back to another branch.
    /// Route lookup does not fall back to sibling branches when the target has no match.
    /// Branch routers are tied to the owning container rather than the requesting
    /// destination, so they remain usable after that destination is dismissed.
    /// Chained calls address branches nested inside the preceding target.
    /// - Parameter id: The branch value declared by the target container.
    public func branch<ID: Hashable & Sendable>(_ id: ID) -> Router {
        guard let engine else { return .inactive }
        let source = origin ?? RouteRequestOrigin(scope: engine.currentRouteScope)
        guard let target = source.targeting(AnyHashable(id), in: engine.spaces) else {
            return .inactive
        }
        return Router(engine: engine, origin: target)
    }

    /// Resolves and presents a route from this router's scope, within its priority space.
    ///
    /// Returns after the destination is inserted or reused in routing state, or the
    /// request is dropped, superseded or cancelled. Any required parent-host staging completes
    /// first; this does not wait for SwiftUI to display the destination.
    /// Rejected routes do not activate the targeted branch.
    ///
    /// One presentation resolves and updates routing state at a time, including
    /// its reroute chain. While it is suspended, only the latest waiting attempt
    /// is retained; callers superseded before admission return without resolving.
    /// Resolution continues in each caller's own task.
    /// During an unfinished navigation operation, the latest presentation attempt
    /// from a live scope waits for completion. Coverage is checked when it resumes;
    /// a surviving higher-priority space causes the request to be dropped.
    /// - Parameter route: The route to resolve and present.
    public func present(_ route: any Route) async {
        guard let engine else { return }
        await engine.requestRouteWhenReady(route, origin: origin)
    }

    /// Applies an unwind policy from this router's captured scope within its priority space.
    ///
    /// `.root` retains this space's root. Use `dismissSpace()` for whole-space removal.
    /// Waits for this unwind's native teardown. A buffered presentation waits for all
    /// ongoing unwinds, then continues in its own caller without delaying this return.
    /// - Returns: Whether the request was accepted for a live scope in the top space.
    @discardableResult
    public func unwind(_ target: UnwindTarget) async -> Bool {
        guard let engine else { return false }
        return await engine.unwindAndWait(target, origin: origin)
    }

    /// Unwinds from this router's scope, and delivers a payload to a matching handler.
    /// Waits for this unwind's native teardown, independently of any buffered presentation.
    /// - Returns: Whether the request was accepted for a live scope in the top space.
    @discardableResult
    public func unwind<Payload>(_ target: UnwindTarget, payload: Payload) async -> Bool {
        guard let engine else { return false }
        return await engine.unwindAndWait(target, payload: payload, origin: origin)
    }

    /// Dismisses the nearest live occurrence of an exact route type and its descendants.
    /// Lookup includes the current destination and stays within its priority space.
    /// - Parameter route: The exact route type whose nearest occurrence should be dismissed.
    /// - Returns: Whether a matching scope was found and dismissed, after native teardown.
    @discardableResult
    public func unwind<R: Route>(from route: R.Type) async -> Bool {
        guard let engine else { return false }
        return await engine.unwindAndWait(.routeType(route), origin: origin)
    }

    /// Dismisses the nearest matching route and delivers a payload using the same policy.
    /// - Parameters:
    ///   - route: The exact route type whose nearest occurrence should be dismissed.
    ///   - payload: The value delivered to a matching ``UnwindHandler``.
    /// - Returns: Whether a matching scope was found and dismissed, after native teardown.
    @discardableResult
    public func unwind<R: Route, Payload>(from route: R.Type, payload: Payload) async -> Bool {
        guard let engine else { return false }
        return await engine.unwindAndWait(.routeType(route), payload: payload, origin: origin)
    }

    /// Performs an action from this router's scope, within its priority space.
    /// Covered or removed scopes reject dispatch, including their interceptors.
    public func perform(_ action: any Action) async {
        guard let engine else { return }
        await engine.performAction(action, origin: origin)
    }

    /// Removes this router's entire elevated space. Only the top space can request it.
    @discardableResult
    public func dismissSpace() async -> Bool {
        guard let engine, let source = engine.navigationSource(origin), let space = source.space else { return false }
        return await engine.dismissSpace(space, source: source)
    }

    public static func == (lhs: Router, rhs: Router) -> Bool {
        lhs.engine === rhs.engine && lhs.origin == rhs.origin
    }
}

/// Carries request identity across resolution and navigation readiness waits.
final class RouteRequestOrigin: Equatable {
    weak var scope: RouteScope?
    let scopeID: ObjectIdentifier
    let branches: [AnyHashable]

    init(scope: RouteScope, branches: [AnyHashable] = []) {
        self.scope = scope
        self.scopeID = ObjectIdentifier(scope)
        self.branches = branches
    }

    func targeting(_ branch: AnyHashable, in forest: RouteSpaces?) -> RouteRequestOrigin? {
        guard let scope, let forest, forest.routePath(containing: scope) != nil else { return nil }
        if branches.isEmpty {
            guard let owner = scope.ancestry.first(where: { $0.branchContainer != nil }) else { return nil }
            return RouteRequestOrigin(scope: owner, branches: [branch])
        }
        return RouteRequestOrigin(scope: scope, branches: branches + [branch])
    }

    static func == (lhs: RouteRequestOrigin, rhs: RouteRequestOrigin) -> Bool {
        lhs.scopeID == rhs.scopeID && lhs.branches == rhs.branches
    }
}

extension RouteRequestOrigin {
    func resolve(in forest: RouteSpaces) -> RouteScope? {
        guard let scope, forest.routePath(containing: scope) != nil else { return nil }
        guard branches.isEmpty == false else { return scope }

        // Branch handles already capture their container at creation. Losing
        // that container must not redirect a stored handle to an ancestor.
        guard scope.branchContainer != nil else { return nil }
        var container = scope
        for (index, branch) in branches.enumerated() {
            guard let child = container.branchScopes[branch] else { return nil }
            if index == branches.count - 1 { return child.activeLocalScope }
            // Stay at the next container instead of following its selected branch
            // into a destination that no longer owns the nested branch map.
            container = child.path.scopes.reversed().first { $0.branchContainer != nil } ?? child
        }
        return nil
    }
}
