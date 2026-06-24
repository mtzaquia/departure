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

/// A request to present a destination view.
///
/// Declare route types with ``SwiftUICore/View/routes(id:_:)``, then request instances with
/// ``Router``.
///
/// ```swift
/// struct SettingsRoute: Route {
///     func destination() -> some View {
///         SettingsView()
///     }
/// }
///
/// await router.present(SettingsRoute())
/// ```
public protocol Route: Identifiable, Equatable, Sendable where ID == ObjectIdentifier {
    /// Returns the resolution result whenever attempting to present this route.
    ///
    /// Despite asynchronous, routing is suspended until this function returns. On a re-route, the target route is also evaluated.
    /// Provide a quick resolution to avoid the app standing idle. The implementer is also responsible for ensuring no recursion occurs.
    ///
    /// ```swift
    /// func resolveRoute() async -> RouteResolution {
    ///     isLoggedIn ? .allow : .reroute(LoginRoute())
    /// }
    /// ```
    ///
    /// - Returns: A route evaluation resolution.
    func resolveRoute() async -> RouteResolution

    /// Resolves the final route that should be used.
    ///
    /// - Important: this function is deprecated, prefer  ``Route/resolveRoute()-56snl`` returning ``RouteResolution`` instead.
    ///
    /// - Returns: The route to be used, or `nil` to drop the request.
    @available(*, deprecated, message: "Use `resolveRoute()` returning `RouteResolution`.")
    func resolveRoute() async -> (any Route)?

    /// The view shown for this route.
    associatedtype Destination: View

    /// Builds this route's destination.
    @ViewBuilder func destination() -> Destination
}

public extension Route {
    /// A type-based identity for routes that do not need instance identity.
    ///
    /// - Important: Override this when multiple instances of the same ``Route`` type should
    ///   be treated as different presentations.
    nonisolated var id: ObjectIdentifier {
        ObjectIdentifier(Self.self)
    }

    @available(*, deprecated, message: "Use `resolveRoute()` returning `RouteResolution`.")
    func resolveRoute() async -> (any Route)? {
        self
    }

    func resolveRoute() async -> RouteResolution {
        let result: (any Route)? = await resolveRoute()
        
        return switch result {
        case .some(let route) where route.id == self.id: .allow
        case .some(let route): .reroute(route)
        case .none: .drop
        }
    }
}

// MARK: - Supporting types

/// The result of a ``Route/resolveRoute()-56snl`` evaluation.
public enum RouteResolution {
    /// The router is allowed to present the requested route.
    case allow
    /// The router should present a different route instead.
    case reroute(any Route)
    /// The router should ignore the request.
    case drop
}
