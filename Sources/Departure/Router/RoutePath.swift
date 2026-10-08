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

struct RoutePathTrim {
    let path: RoutePath
    let keepThrough: RoutePath.Position

    var removedScopes: [RouteScope] {
        path.scopesRemovedAfter(keepThrough)
    }
}

final class RoutePath: Identifiable {
    enum Position: Equatable, CustomStringConvertible {
        case owner
        case scope(RouteScope)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.owner, .owner):
                true

            case let (.scope(lhs), .scope(rhs)):
                lhs === rhs

            case (.owner, .scope), (.scope, .owner):
                false
            }
        }

        var description: String {
            switch self {
            case .owner:
                "owner"

            case let .scope(scope):
                "scope(\(scope.departureDebugDescription))"
            }
        }
    }

    enum UnwindResolution {
        case noRouteToUnwind
        case targetNotFound
        case keepPathThrough(Position)
    }

    let id = UUID()
    weak var owner: RouteScope?
    var scopes: [RouteScope] {
        var result: [RouteScope] = []
        var current = owner
        while let next = current?.next(in: self) {
            result.append(next)
            current = next
        }
        return result
    }

    init(owner: RouteScope) { self.owner = owner }

    var isEmpty: Bool {
        scopes.isEmpty
    }

    var count: Int {
        scopes.count
    }

    var first: RouteScope? {
        scopes.first
    }

    var last: RouteScope? {
        scopes.last
    }

    func append(_ routeScope: RouteScope) {
        (last ?? owner)?.append(routeScope, in: self)
    }

    func position(of routeScope: RouteScope) -> Position? {
        guard routeScope !== owner else {
            return .owner
        }

        if routeScope.owningPath === self {
            var current = routeScope
            while let previous = current.previousRouteScope, previous.continuation === current {
                if previous === owner { return .scope(routeScope) }
                guard previous.owningPath === self else { return nil }
                current = previous
            }
            return nil
        }

        guard let parent = routeScope.parent else {
            return nil
        }

        return position(of: parent)
    }

    func contains(_ routeScope: RouteScope) -> Bool {
        routeScope === owner
        || position(of: routeScope) != nil
        || routeScope.parent === owner
    }

    func scope(at position: Position) -> RouteScope? {
        switch position {
        case .owner:
            return owner

        case let .scope(scope):
            return scope
        }
    }

    func keepThrough(_ position: Position) {
        guard let retained = scope(at: position),
              position == .owner || self.position(of: retained) == position else { return }
        // Cut one owning edge. Outgoing snapshots retain the detached subtree until exit.
        retained.removeContinuation(in: self)
    }

    func scopesRemovedAfter(_ position: Position) -> [RouteScope] {
        guard let retained = scope(at: position),
              position == .owner || self.position(of: retained) == position else { return [] }
        var removed: [RouteScope] = []
        var current = retained
        while let next = current.next(in: self) {
            removed.append(next)
            current = next
        }
        return removed
    }

    func positionBefore(_ routeScope: RouteScope) -> Position? {
        guard case .scope = position(of: routeScope), let previous = routeScope.previousRouteScope else {
            return position(of: routeScope)
        }
        return previous === owner ? .owner : .scope(previous)
    }

    var lastPosition: Position {
        guard let last else {
            return .owner
        }

        return .scope(last)
    }

    func shallower(_ lhs: Position, _ rhs: Position) -> Position {
        if lhs == .owner || rhs == .owner {
            return .owner
        }

        guard case let .scope(lhsScope) = lhs,
              case let .scope(rhsScope) = rhs,
              lhsScope.owningPath === self, rhsScope.owningPath === self
        else {
            assertionFailure("Route trim positions must belong to their route path.")
            return lhs
        }

        return lhsScope.pathDepth <= rhsScope.pathDepth ? lhs : rhs
    }

    func unwindResolution(to target: RouterEngine.UnwindTarget?) -> UnwindResolution {
        guard let target else {
            guard let currentScope = scopes.last else {
                return .noRouteToUnwind
            }

            return .keepPathThrough(positionBefore(currentScope) ?? .owner)
        }

        switch target {
        case .root, .nearestBranch:
            // Both clear the resolved path entirely; they differ only in which path
            // `RouterEngine.unwindAndWait` resolves against (the root path vs. the nearest branch path).
            // Clearing an already-empty branch path is the `.nearestBranch` no-op.
            return .keepPathThrough(.owner)

        case .topmostAncestor:
            guard let currentScope = scopes.last else {
                return .noRouteToUnwind
            }

            return .keepPathThrough(positionBefore(currentScope) ?? .owner)

        case let .id(id):
            if owner?.id == id {
                return .keepPathThrough(.owner)
            }

            guard let scope = scopes.last(where: { $0.id == id }) else {
                return .targetNotFound
            }

            return .keepPathThrough(.scope(scope))
        }
    }

}
