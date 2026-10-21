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

/// One destination catalog collected from the entire composed definition tree.
struct RouteDestinationBindings: Sendable {
    private let destinations: [ObjectIdentifier: DeclarationBinding<AnyRouteDestination>]

    init(_ destinations: [AnyRouteDestination] = [], declarations: [RouteScopeDeclaration] = []) {
        var bindings: [ObjectIdentifier: DeclarationBinding<AnyRouteDestination>] = [:]
        destinations.forEach(include)
        collect(declarations)
        self.destinations = bindings

        func include(_ destination: AnyRouteDestination) {
            let type = ObjectIdentifier(destination.routeType)
            switch bindings[type] {
            case nil:
                bindings[type] = .declared(destination)
            case .declared(let existing) where existing != destination:
                bindings[type] = .conflict
                log.departureWarning(
                    "Conflicting destination builders for `\(destination.routeType)` in the composed root map; that destination binding is disabled throughout the tree."
                )
            default:
                break
            }
        }

        func collect(_ declarations: [RouteScopeDeclaration]) {
            for declaration in declarations {
                switch declaration.content {
                case .destinations(let values):
                    values.forEach(include)
                case .routes(let routes):
                    for route in routes {
                        if let destination = route.destination { include(destination) }
                        collect(route.children)
                    }
                case .branch(_, let children), .branches(_, let children):
                    collect(children)
                case .scopeID:
                    break
                }
            }
        }
    }

    func binding(for type: any Route.Type) -> DeclarationBinding<AnyRouteDestination>? {
        destinations[ObjectIdentifier(type)]
    }
}
