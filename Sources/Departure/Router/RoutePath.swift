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
    enum UnwindResolution {
        case noRouteToUnwind
        case targetNotFound
        case keepPathThrough([RouteScope].Index?)
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

    var endIndex: [RouteScope].Index {
        scopes.endIndex
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

    func index(of routeScope: RouteScope) -> [RouteScope].Index? {
        guard routeScope !== owner else {
            return nil
        }

        if let index = scopes.firstIndex(where: { $0 === routeScope }) {
            return index
        }

        guard let parent = routeScope.parent else {
            return nil
        }

        return index(of: parent)
    }

    func contains(_ routeScope: RouteScope) -> Bool {
        routeScope === owner
        || index(of: routeScope) != nil
        || routeScope.parent === owner
    }

    func scope(at index: [RouteScope].Index?) -> RouteScope? {
        guard let index else {
            return owner
        }

        guard scopes.indices.contains(index) else {
            return nil
        }

        return scopes[index]
    }

    func keepThrough(_ index: [RouteScope].Index?) {
        guard let index else {
            scopes.removeAll()
            return
        }

        let removalStartIndex = scopes.index(after: index)
        guard removalStartIndex < scopes.endIndex else {
            return
        }

        scopes.removeSubrange(removalStartIndex..<scopes.endIndex)
    }

    /// The scopes dropped when keeping the path through `index` (i.e. everything after it).
    func scopesRemovedByKeepingThrough(_ index: [RouteScope].Index?) -> [RouteScope] {
        guard let index else {
            return scopes
        }

        let removalStartIndex = scopes.index(after: index)

        guard removalStartIndex < scopes.endIndex else {
            return []
        }

        return Array(scopes[removalStartIndex..<scopes.endIndex])
    }

    func unwindResolution(to target: Router.UnwindTarget?) -> UnwindResolution {
        guard let target else {
            guard let currentPathIndex = scopes.indices.last else {
                return .noRouteToUnwind
            }

            guard currentPathIndex > scopes.startIndex else {
                return .keepPathThrough(nil)
            }

            return .keepPathThrough(scopes.index(before: currentPathIndex))
        }

        switch target {
        case .root, .nearestBranch:
            // Both clear the resolved path entirely; they differ only in which path
            // `Router.unwindAndWait` resolves against (the root path vs. the nearest branch path).
            // Clearing an already-empty branch path is the `.nearestBranch` no-op.
            return .keepPathThrough(nil)

        case let .id(id):
            if owner?.id == id {
                return .keepPathThrough(nil)
            }

            guard let pathIndex = scopes.lastIndex(where: { $0.id == id }) else {
                return .targetNotFound
            }

            return .keepPathThrough(pathIndex)
        }
    }
}
