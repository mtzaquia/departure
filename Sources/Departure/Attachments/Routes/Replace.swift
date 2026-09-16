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

/// Declares a route that replaces the declaring view’s content in place.
///
/// In a ``Branch`` map, replaces that branch’s selected destination and clears
/// its descendant navigation. Other branches retain their paths. The destination
/// does not create a Back entry; it can still declare pushes inside a surrounding
/// SwiftUI `NavigationStack`.
///
/// ```swift
/// Branch(AppColumn.detail) { Replace(MessageRoute.self) }
/// ```
///
/// Use the contextual ``UnwindRouteAction`` or unwind to the nearest branch to
/// clear the selection and reveal the original content. Requests use normal
/// priority and retain the existing route discovery and branch activation rules.
public struct Replace: RouteDeclaration, Sendable {
    let declaration: AnyRouteDeclaration

    /// Creates an in-place replacement declaration.
    /// - Parameter routeType: The destination to select in the declaring view’s slot.
    public init<R: Route>(_ routeType: R.Type) {
        self.declaration = AnyRouteDeclaration(routeType: routeType, kind: .replace)
    }

    public var _routeDeclarations: [AnyRouteDeclaration] {
        [declaration]
    }
}
