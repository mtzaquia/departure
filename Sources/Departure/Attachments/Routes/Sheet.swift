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

/// Declares a sheet destination with optional child definitions.
public struct Sheet: RouteDeclaration, Sendable {
    let declaration: AnyRouteDeclaration
    public init<R: Route>(
        _ destination: RouteDestination<R>,
        id: AnyHashable? = nil,
        @RouteDeclarationBuilder _ children: () -> [RouteScopeDeclaration] = { [] }
    ) {
        declaration = AnyRouteDeclaration(destination, presentation: .init(style: .sheet, priority: .default), id: id, children: children())
    }

    /// Declares a sheet with an inline destination builder.
    ///
    /// `destination` receives the requested route and its destination's ``RouteContext``
    /// when SwiftUI evaluates the view.
    public init<R: Route, Content: View>(
        _ route: R.Type,
        id: AnyHashable? = nil,
        @ViewBuilder destination: @escaping @MainActor @Sendable (R, RouteContext) -> Content
    ) {
        self.init(RouteDestination(route, destination: destination), id: id)
    }

    /// Declares a sheet with an inline destination builder and nested routes.
    ///
    /// `destination` builds the view using its scoped ``RouteContext``; `routes`
    /// declares the navigation available from that destination.
    public init<R: Route, Content: View>(
        _ route: R.Type,
        id: AnyHashable? = nil,
        @ViewBuilder destination: @escaping @MainActor @Sendable (R, RouteContext) -> Content,
        @RouteDeclarationBuilder routes: () -> [RouteScopeDeclaration]
    ) {
        self.init(RouteDestination(route, destination: destination), id: id, routes)
    }

    public var _routeDeclarations: [AnyRouteDeclaration] { [declaration] }
}
