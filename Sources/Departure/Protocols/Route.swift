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
/// Declare route types with ``View/routes(id:_:)``, then request instances with
/// ``RoutingAction``.
///
/// ```swift
/// struct SettingsRoute: Route {
///     func destination() -> some View {
///         SettingsView()
///     }
/// }
///
/// routing(.present(SettingsRoute()))
/// ```
public protocol Route: Identifiable, Sendable where ID == ObjectIdentifier {
    /// Returns the route that should be matched.
    ///
    /// Return `self` for ordinary routing, another ``Route`` to redirect, or `nil` to
    /// drop the request.
    ///
    /// ```swift
    /// func resolveRoute() async -> (any Route)? {
    ///     isLoggedIn ? self : LoginRoute()
    /// }
    /// ```
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

    func resolveRoute() async -> (any Route)? {
        self
    }
}
