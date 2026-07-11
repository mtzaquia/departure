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
import SwiftUI

/// Unwinds the local route scope from SwiftUI views.
///
/// ```swift
/// @Environment(\.unwindRoute) private var unwindRoute
///
/// Button("Done") {
///     Task {
///         await unwindRoute()
///     }
/// }
/// ```
public struct UnwindRouteAction: Equatable {
    private enum Identity: Equatable {
        case inactive
        case routeScope(routerID: UUID, routeScopeID: ObjectIdentifier)
    }

    private let identity: Identity
    private let handle: @MainActor (Any?) async -> Bool

    /// Creates an inactive unwind action.
    public init() {
        self.identity = .inactive
        self.handle = { _ in true }
    }

    init(router: Router, routeScope: RouteScope) {
        self.identity = .routeScope(
            routerID: router.id,
            routeScopeID: ObjectIdentifier(routeScope)
        )
        self.handle = { [weak routeScope] payload in
            guard let routeScope else {
                return true
            }

            return await router.unwindRoute(from: routeScope, payload: payload)
        }
    }

    /// Unwinds this view's local route scope.
    ///
    /// This method returns after the unwind request has resolved, the router path has been updated,
    /// and any removed installed route scopes have left the view hierarchy.
    @discardableResult
    public func callAsFunction() async -> Bool {
        await handle(nil)
    }

    /// Unwinds this view's local route scope and delivers a payload to a matching ``UnwindHandler``.
    ///
    /// This method returns after the unwind request has resolved, the router path has been updated,
    /// and any removed installed route scopes have left the view hierarchy.
    @discardableResult
    public func callAsFunction<Payload>(payload: Payload) async -> Bool {
        await handle(payload)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity
    }
}

/// The current routing phase for a view's local route scope.
public enum RoutePhase: Equatable, Sendable {
    /// This view's route scope is the router's current route scope.
    case active

    /// This view's route scope is installed, but another route scope is current.
    case inactive
}

extension EnvironmentValues {
    @Entry var routeScope: RouteScope?
}

public extension EnvironmentValues {
    /// Unwinds this view's local route scope.
    @Entry var unwindRoute = UnwindRouteAction()

    /// The current routing phase for this view's local route scope.
    ///
    /// This value is local to the view hierarchy it is read from. The current route destination,
    /// branch root, or root content reads ``RoutePhase/active``; installed scopes behind another
    /// route read ``RoutePhase/inactive``.
    @Entry var routePhase = RoutePhase.inactive
}

extension View {
    func routeScopeEnvironment(_ routeScope: RouteScope) -> some View {
        environment(\.routeScope, routeScope)
    }

    func routeScopeEnvironment(_ routeScope: RouteScope, router: Router) -> some View {
        self
            .environment(\.routeScope, routeScope)
            .environment(\.routePhase, router.routePhase(for: routeScope))
            .environment(\.unwindRoute, UnwindRouteAction(router: router, routeScope: routeScope))
    }
}

extension Router {
    func routePhase(for routeScope: RouteScope) -> RoutePhase {
        activeRouteScopeID == ObjectIdentifier(routeScope) ? .active : .inactive
    }
}
