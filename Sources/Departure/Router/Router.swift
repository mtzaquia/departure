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

/// The routing engine installed by ``WithRouter``.
///
/// Consumer views read the router from the environment, then send commands through it.
///
/// ```swift
/// @Environment(Router.self) private var router
///
/// Button("Settings") {
///     Task {
///         await router.present(SettingsRoute())
///     }
/// }
/// ```
@Observable
public final class Router: Identifiable, Equatable {
    struct PendingRoute {
        let route: any Route
        let match: DeclarationMatch
        let startsHighPrioritySegment: Bool
    }

    struct UnwindPresentationSnapshot {
        let preservedPath: [RouteScope]
        let highPrioritySegmentStartIndex: [RouteScope].Index?
    }

    /// A destination for ``Router/unwind(to:)``.
    public enum UnwindTarget {
        /// Unwinds every presented route.
        case root

        /// Unwinds to the scope that was declared with a matching ``SwiftUICore/View/routes(id:_:)`` ID.
        case id(AnyHashable)
    }

    /// Stable identity for this router instance.
    public let id = UUID()

    let root: RouteScope
    var path: [RouteScope] = []

    var highPrioritySegmentStartIndex: [RouteScope].Index?
    var pendingRoute: PendingRoute?
    var unwindPresentationSnapshot: UnwindPresentationSnapshot?

    var currentRouteScope: RouteScope {
        (path.last ?? root).activeLocalScope
    }

    /// Creates an empty router.
    public init() {
        self.root = RouteScope(id: UUID(), route: nil)
    }

    /// Requests a route presentation.
    ///
    /// This method returns after the request has resolved and the router has updated its routing state.
    /// It does not wait for SwiftUI to mount or display the destination view.
    public func present(_ route: any Route) async {
        await requestRoute(route)
    }

    /// Dismisses route scopes.
    ///
    /// This method returns after the unwind request has resolved, the router path has been updated,
    /// and any removed mounted route scopes have left the view hierarchy.
    ///
    /// - Parameter target: The target to unwind to, or `nil` for the route to just dismiss itself.
    /// - Returns: `false` when an explicit target was requested but not found.
    @discardableResult
    public func unwind(to target: UnwindTarget? = nil) async -> Bool {
        await unwindAndWait(to: target)
    }

    /// Performs an action from the current route scope.
    public func perform(_ action: any Action) async {
        await performAction(action)
    }

    public static func == (lhs: Router, rhs: Router) -> Bool {
        lhs.id == rhs.id
    }
}
