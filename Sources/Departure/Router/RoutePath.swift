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

final class RoutePath: Identifiable {
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

    var isEmpty: Bool { first == nil }
    var count: Int { scopes.count }
    var first: RouteScope? { owner?.next(in: self) }
    var last: RouteScope? { scopes.last }

    func append(_ routeScope: RouteScope) {
        (last ?? owner)?.append(routeScope, in: self)
    }

    func contains(_ routeScope: RouteScope) -> Bool {
        routeScope === owner || scopes.contains { $0 === routeScope }
        || routeScope.parent.map(contains) == true
    }

    func scope(before routeScope: RouteScope) -> RouteScope? {
        guard contains(routeScope) else { return nil }
        return routeScope === owner ? owner : routeScope.previousRouteScope
    }

    func keepThrough(_ scope: RouteScope) {
        guard contains(scope) else { return }
        // Cut one owning edge. Outgoing snapshots retain the detached subtree until exit.
        scope.removeContinuation(in: self)
    }

    func scopesRemoved(after scope: RouteScope) -> [RouteScope] {
        guard contains(scope) else { return [] }
        var removed: [RouteScope] = []
        var current = scope
        while let next = current.next(in: self) {
            removed.append(next)
            current = next
        }
        return removed
    }

    func scope(withID id: AnyHashable) -> RouteScope? {
        if let owner, owner.id == id { return owner }
        return scopes.last { $0.id == id }
    }
}
