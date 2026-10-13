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
@testable import Departure

// Topology fixtures share one inert destination value for each concrete route type.
// Tests of destination conflicts construct their own distinct values explicitly.
@MainActor private enum TestDestinationValues {
    static var values: [ObjectIdentifier: Any] = [:]
}

@MainActor
func testDestination<R: Route>(_ route: R.Type) -> RouteDestination<R> {
    let key = ObjectIdentifier(route)
    if let existing = TestDestinationValues.values[key] as? RouteDestination<R> { return existing }
    let destination = RouteDestination(route) { _, _ in EmptyView() }
    TestDestinationValues.values[key] = destination
    return destination
}

// Legacy navigation scenarios supply their builders through real map composition.
// Public API tests exercise type-only declarations and destination closures directly.
@MainActor
func testPush<R: Route>(
    _ destination: RouteDestination<R>, id: AnyHashable? = nil,
    @RouteDeclarationBuilder _ children: () -> [RouteScopeDeclaration] = { [] }
) -> RouteMap {
    RouteMap {
        Push(R.self, id: id, children)
    } destinations: {
        destination
    }
}

@MainActor
func testReplace<R: Route>(
    _ destination: RouteDestination<R>, id: AnyHashable? = nil,
    @RouteDeclarationBuilder _ children: () -> [RouteScopeDeclaration] = { [] }
) -> RouteMap {
    RouteMap {
        Replace(R.self, id: id, children)
    } destinations: {
        destination
    }
}

@MainActor
func testSheet<R: Route>(
    _ destination: RouteDestination<R>, id: AnyHashable? = nil,
    @RouteDeclarationBuilder _ children: () -> [RouteScopeDeclaration] = { [] }
) -> ModalRouteMap {
    ModalRouteMap {
        Sheet(R.self, id: id, children)
    } destinations: {
        destination
    }
}

@MainActor
func testCover<R: Route>(
    _ destination: RouteDestination<R>, transition: Cover.Transition = .slide,
    id: AnyHashable? = nil,
    @RouteDeclarationBuilder _ children: () -> [RouteScopeDeclaration] = { [] }
) -> ModalRouteMap {
    ModalRouteMap {
        Cover(R.self, transition: transition, id: id, children)
    } destinations: {
        destination
    }
}

@MainActor
func testDeclaration<R: Route>(
    _ destination: RouteDestination<R>, presentation: RoutePresentation,
    id: AnyHashable? = nil, children: [RouteScopeDeclaration] = []
) -> AnyRouteDeclaration {
    AnyRouteDeclaration(R.self, presentation: presentation, id: id, children: children)
        .compiled(destinations: RouteDestinationBindings([AnyRouteDestination(destination)], declarations: children))
}

extension RouteMap {
    var declaration: AnyRouteDeclaration {
        RouteDefinitions(scopeDeclarations).routeAttachments[0]
    }
    var _routeDeclarations: [AnyRouteDeclaration] { [declaration] }
}

extension ModalRouteMap {
    var declaration: AnyRouteDeclaration {
        RouteDefinitions(scopeDeclarations).routeAttachments[0]
    }
    var _routeDeclarations: [AnyRouteDeclaration] { [declaration] }
}
