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
/// Consumer views send commands through ``EnvironmentValues/routing``.
@Observable
public final class Router {
    struct PendingRoute {
        let route: any Route
        let match: DeclarationMatch
        let startsHighPrioritySegment: Bool
    }

    struct UnwindPresentationSnapshot {
        let preservedPath: [RouteScope]
        let highPrioritySegmentStartIndex: [RouteScope].Index?
    }

    /// A destination for ``RoutingAction/Request/unwind(to:thenPresent:)``.
    public enum UnwindTarget {
        /// Unwinds every presented route.
        case root

        /// Unwinds to the scope that was declared with a matching ``View/routes(id:_:)`` ID.
        case id(AnyHashable)
    }

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
}
