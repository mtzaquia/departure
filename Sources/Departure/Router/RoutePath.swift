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
import Observation

@Observable
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

    @ObservationIgnored let id = UUID()
    @ObservationIgnored weak var owner: RouteScope?
    var scopes: [RouteScope] = [] {
        didSet {
            let currentScopeIDs = Set(scopes.map(ObjectIdentifier.init))
            for routeScope in oldValue where currentScopeIDs.contains(ObjectIdentifier(routeScope)) == false {
                if routeScope.owningPath === self {
                    routeScope.owningPath = nil
                }
            }

            for routeScope in scopes {
                routeScope.owningPath = self
            }
        }
    }

    init(owner: RouteScope? = nil) {
        self.owner = owner
    }

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
        scopes.append(routeScope)
    }

    func position(of routeScope: RouteScope) -> Position? {
        guard routeScope !== owner else {
            return .owner
        }

        if let scope = scopes.first(where: { $0 === routeScope }) {
            return .scope(scope)
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
        guard let removalStartIndex = index(after: position) else {
            return
        }

        scopes.removeSubrange(removalStartIndex..<scopes.endIndex)
    }

    func scopesRemovedAfter(_ position: Position) -> [RouteScope] {
        guard let removalStartIndex = index(after: position) else {
            return []
        }

        guard removalStartIndex < scopes.endIndex else {
            return []
        }

        return Array(scopes[removalStartIndex..<scopes.endIndex])
    }

    func positionBefore(_ routeScope: RouteScope) -> Position? {
        guard let index = scopes.firstIndex(where: { $0 === routeScope }) else {
            return position(of: routeScope)
        }

        guard index > scopes.startIndex else {
            return .owner
        }

        return .scope(scopes[scopes.index(before: index)])
    }

    func firstModalPosition(after position: Position) -> Position? {
        guard let searchStartIndex = index(after: position) else {
            return nil
        }

        guard searchStartIndex < scopes.endIndex else {
            return nil
        }

        guard let index = scopes[searchStartIndex...].firstIndex(where: {
            $0.hostDeclaration?.presentationKind != .push
        }) else {
            return nil
        }

        return .scope(scopes[index])
    }

    var lastPosition: Position {
        guard let last else {
            return .owner
        }

        return .scope(last)
    }

    func unwindResolution(to target: Router.UnwindTarget?) -> UnwindResolution {
        guard let target else {
            guard let currentScope = scopes.last else {
                return .noRouteToUnwind
            }

            return .keepPathThrough(positionBefore(currentScope) ?? .owner)
        }

        switch target {
        case .root, .nearestBranch:
            // Both clear the resolved path entirely; they differ only in which path
            // `Router.unwindAndWait` resolves against (the root path vs. the nearest branch path).
            // Clearing an already-empty branch path is the `.nearestBranch` no-op.
            return .keepPathThrough(.owner)

        case .previous:
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

    private func index(after position: Position) -> [RouteScope].Index? {
        switch position {
        case .owner:
            return scopes.startIndex

        case let .scope(scope):
            guard let index = scopes.firstIndex(where: { $0 === scope }) else {
                return nil
            }

            return scopes.index(after: index)
        }
    }
}
