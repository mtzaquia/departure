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

/// Immutable definitions shared by every runtime instance of one map occurrence.
final class RouteDefinitions: Sendable {
    struct Branch {
        let scope: RouteDefinitions
        let concurrent: Bool
    }

    static let empty = RouteDefinitions([])
    let scopeID: DeclarationBinding<AnyHashable>?
    private let routesByType: OrderedStorage<ObjectIdentifier, DeclarationBinding<AnyRouteDeclaration>>
    let branches: OrderedStorage<AnyHashable, DeclarationBinding<Branch>>

    init(_ declarations: [RouteScopeDeclaration], id: AnyHashable? = nil) {
        var scopeID = id.map { DeclarationBinding.declared($0) }
        var routes = OrderedStorage<ObjectIdentifier, DeclarationBinding<AnyRouteDeclaration>>()
        var branches = OrderedStorage<AnyHashable, DeclarationBinding<Branch>>()
        for declaration in declarations {
            if let id = declaration.scopeID {
                if scopeID == nil { scopeID = .declared(id) }
                else {
                    scopeID = .conflict
                    log.departureWarning("A scope accepts one explicit map ID; conflicting IDs disable its unwind target.")
                }
            } else if let branch = declaration.branch {
                guard branches[branch] == nil else {
                    branches[branch] = .conflict
                    log.departureWarning("Conflicting branch declarations for `\(branch)`; the branch is disabled.")
                    continue
                }
                branches[branch] = .declared(Branch(scope: RouteDefinitions(declaration.children), concurrent: declaration.concurrent))
            } else {
                for route in declaration.routes {
                    let type = ObjectIdentifier(route.routeType)
                    guard routes[type] == nil else {
                        routes[type] = .conflict
                        log.departureWarning("Conflicting route declarations for `\(route.routeType)`; the route is disabled in this scope.")
                        continue
                    }
                    routes[type] = .declared(route.compiled())
                }
            }
        }
        routesByType = routes
        self.scopeID = scopeID
        self.branches = branches
    }

    var routeAttachments: [AnyRouteDeclaration] { routesByType.values.compactMap(\.declaration) }
    func routeBinding(for type: any Route.Type) -> DeclarationBinding<AnyRouteDeclaration>? { routesByType[ObjectIdentifier(type)] }
}
