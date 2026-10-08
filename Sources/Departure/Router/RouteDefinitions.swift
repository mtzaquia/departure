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
    private let routesByType: OrderedStorage<ObjectIdentifier, AnyRouteDeclaration>
    let branches: OrderedStorage<AnyHashable, Branch>

    init(_ declarations: [RouteScopeDeclaration]) {
        var routes = OrderedStorage<ObjectIdentifier, AnyRouteDeclaration>()
        var branches = OrderedStorage<AnyHashable, Branch>()
        for declaration in declarations {
            if let branch = declaration.branch {
                guard branches[branch] == nil else {
                    log.departureWarning("Duplicate branch declaration; the first definition will be used.")
                    continue
                }
                branches[branch] = Branch(scope: RouteDefinitions(declaration.children), concurrent: declaration.concurrent)
            } else {
                for route in declaration.routes {
                    let type = ObjectIdentifier(route.routeType)
                    guard routes[type] == nil else {
                        log.departureWarning("Duplicate route declaration for `\(route.routeType)`; the first definition will be used.")
                        continue
                    }
                    routes[type] = route.compiled()
                }
            }
        }
        routesByType = routes
        self.branches = branches
    }

    var routeAttachments: [AnyRouteDeclaration] { routesByType.values }
    func routeAttachment(for type: any Route.Type) -> AnyRouteDeclaration? { routesByType[ObjectIdentifier(type)] }
}
