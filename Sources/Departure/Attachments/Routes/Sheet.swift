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

/// Declares a route presented as a sheet, with optional child definitions.
public struct Sheet: RouteDeclaration, Sendable {
    let declaration: AnyRouteDeclaration

    /// Declares a route type and its child definitions without a destination builder.
    ///
    /// Requests matching this declaration report a diagnostic and leave navigation
    /// unchanged while it has no destination. Lookup does not fall back to another
    /// declaration of the same route type.
    ///
    /// - Parameters:
    ///   - route: The route type available at this map location.
    ///   - id: An explicit unwind name for the destination's scope.
    ///   - children: The navigation available from this destination.
    public init<R: Route>(
        _ route: R.Type,
        id: AnyHashable? = nil,
        @RouteDeclarationBuilder _ children: () -> [RouteScopeDeclaration] = { [] }
    ) {
        declaration = AnyRouteDeclaration(route, presentation: .init(style: .sheet, priority: .default), id: id, children: children())
    }

    public var _routeDeclarations: [AnyRouteDeclaration] { [declaration] }
}
