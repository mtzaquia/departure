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

/// A router bound to a route scope in a shared routing container.
///
/// Read `@Environment(\.router)` in views. Stored routers retain their original
/// scope; commands become inactive when that scope leaves the routing graph.
/// Routers and their commands are isolated to the main actor.
public struct Router: Equatable {
    /// A destination for ``Router/unwind(to:)``.
    public enum UnwindTarget {
        /// Unwinds every presented route across all branches and scopes, returning to the app's start.
        case root

        /// Unwinds to the first scope of the nearest enclosing branch.
        ///
        /// Brings the user to the branch's root regardless of how deep the receiving scope is. If the
        /// user is already at the branch root, this is a no-op. If the user is not inside a branch,
        /// the unwind request returns `false`.
        case nearestBranch

        /// Unwinds to the nearest ancestor of the receiving router's route scope.
        ///
        /// Dismisses the receiving scope and its descendants, matching a local
        /// ``UnwindRouteAction`` captured from that scope.
        case topmostAncestor

        /// Unwinds to the scope that was declared with a matching ``SwiftUICore/View/routes(id:_:)`` ID.
        case id(AnyHashable)
    }

    let engine: RouterEngine?
    let origin: RouteRequestOrigin?

    /// Creates a root router for a new routing container.
    public init() {
        let engine = RouterEngine()
        self.init(engine: engine, scope: engine.root)
    }

    init(engine: RouterEngine, scope: RouteScope) {
        self.engine = engine
        self.origin = RouteRequestOrigin(scope: scope)
    }

    private init(engine: RouterEngine?, origin: RouteRequestOrigin?) {
        self.engine = engine
        self.origin = origin
    }

    static let inactive = Router(engine: nil, origin: nil)

    /// Returns a router targeting a named branch of the nearest enclosing container.
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
        Router(engine: engine, origin: origin?.targeting(AnyHashable(id), in: engine?.routeForest))
    }

    /// Resolves and presents a route from this router's scope.
    ///
    /// Returns after routing state updates, without waiting for SwiftUI to display
    /// the destination. Rejected routes do not activate the targeted branch.
    /// - Parameter route: The route to resolve and present.
    public func present(_ route: any Route) async {
        guard let engine, let origin else { return }
        await engine.requestRouteWhenReady(route, origin: origin)
    }

    /// Unwinds from this router's scope to an explicit target.
    ///
    /// `.root` clears the entire routing container. Other targets resolve locally.
    /// - Returns: Whether an unwind target was found for an active scope.
    @discardableResult
    public func unwind(to target: UnwindTarget) async -> Bool {
        guard let engine, let origin else { return false }
        return await engine.unwindAndWait(to: target, origin: origin)
    }

    /// Unwinds from this router's scope and delivers a payload to a matching handler.
    /// - Returns: Whether an unwind target was found for an active scope.
    @discardableResult
    public func unwind<Payload>(to target: UnwindTarget, payload: Payload) async -> Bool {
        guard let engine, let origin else { return false }
        return await engine.unwindAndWait(to: target, payload: payload, origin: origin)
    }

    /// Performs an action from this router's scope.
    public func perform(_ action: any Action) async {
        guard let engine, let origin else { return }
        await engine.performAction(action, origin: origin)
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

    func targeting(_ branch: AnyHashable, in forest: RouteForest?) -> RouteRequestOrigin? {
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
    enum Target {
        case scope(RouteScope)
        case unmountedBranch(owner: RouteScope, id: AnyHashable)

        var scope: RouteScope? {
            if case .scope(let scope) = self { return scope }
            return nil
        }
    }

    func resolve(in forest: RouteForest) -> Target? {
        guard let scope, forest.routePath(containing: scope) != nil else { return nil }
        guard branches.isEmpty == false else { return .scope(scope) }

        // Branch handles already capture their container at creation. Losing
        // that container must not redirect a stored handle to an ancestor.
        guard scope.branchContainer != nil else { return nil }
        var container = scope
        for (index, branch) in branches.enumerated() {
            guard container.declarations.branchIDs.contains(branch)
                || container.branchScopes[branch] != nil else { return nil }
            guard let child = container.branchScopes[branch] else {
                return index == branches.count - 1 ? .unmountedBranch(owner: container, id: branch) : nil
            }
            if index == branches.count - 1 { return .scope(child.activeLocalScope) }
            // Stay at the next container instead of following its selected branch
            // into a destination that no longer owns the nested branch map.
            container = child.path.scopes.reversed().first { $0.branchContainer != nil } ?? child
        }
        return nil
    }
}
