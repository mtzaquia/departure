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
/// leaves navigation. Read `RootRouter.current` to capture a source for external navigation.
public struct Router: Equatable {
    /// A destination for ``Router/unwind(to:)``.
    public enum UnwindTarget {
        /// Resets navigation in the receiving space, keeping its root and outer presentation.
        case root

        /// Unwinds to the first scope of the nearest enclosing branch.
        ///
        /// Brings the user to the branch's root regardless of how deep the receiving scope is. If the
        /// user is already at the branch root, this is a no-op. If the user is not inside a branch,
        /// the unwind request returns `false`.
        case nearestBranch

        /// Dismisses the receiving scope. An elevated root removes its whole space.
        ///
        /// Dismisses the receiving scope and its descendants, matching a local
        /// ``UnwindRouteAction`` captured from that scope.
        case topmostAncestor

        /// Unwinds to the mapped scope with a matching declaration ID.
        case id(AnyHashable)
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
    /// External callers can capture a scoped router through `RootRouter.current`.
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
    /// Returns after routing state updates, without waiting for SwiftUI to display
    /// the destination. Rejected routes do not activate the targeted branch.
    /// - Parameter route: The route to resolve and present.
    public func present(_ route: any Route) async {
        guard let engine else { return }
        await engine.requestRouteWhenReady(route, origin: origin)
    }

    /// Unwinds from this router's scope, to an explicit target in its priority space.
    ///
    /// `.root` retains this space's root. Use `dismissSpace()` for whole-space removal.
    /// - Returns: Whether an unwind target was found for an active scope.
    @discardableResult
    public func unwind(to target: UnwindTarget) async -> Bool {
        guard let engine else { return false }
        return await engine.unwindAndWait(to: target, origin: origin)
    }

    /// Unwinds from this router's scope, and delivers a payload to a matching handler.
    /// - Returns: Whether an unwind target was found for an active scope.
    @discardableResult
    public func unwind<Payload>(to target: UnwindTarget, payload: Payload) async -> Bool {
        guard let engine else { return false }
        return await engine.unwindAndWait(to: target, payload: payload, origin: origin)
    }

    /// Performs an action from this router's scope, within its priority space.
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
            var candidate: RouteScope? = scope
            while let owner = candidate {
                if owner.branchContainer != nil {
                    return RouteRequestOrigin(scope: owner, branches: [branch])
                }
                candidate = forest.enclosingScope(before: owner)
            }
            return nil
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
