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

/// Binds a domain route to a feature view without extending the route type.
///
/// Pass this value to ``Push``, ``Replace``, ``Sheet``, or ``Cover`` in a route map.
/// Its builder runs on the main actor with the requested route and the destination's
/// own routing context. The same route type can use different builders at different
/// map locations.
///
/// ```swift
/// let profile = RouteDestination(ProfileRoute.self) { route, context in
///     ProfileView(userID: route.userID)
/// }
///
/// let routes = RootRouteMap { Push(profile) }
/// ```
public struct RouteDestination<R: Route>: Sendable {
    let build: @MainActor @Sendable (R, RouteContext) -> AnyView

    /// Creates a reusable destination builder for a route type.
    ///
    /// - Parameters:
    ///   - route: The domain route type bound to this destination.
    ///   - destination: Builds a view from typed route data and the current rendering context.
    public init<Content: View>(_ route: R.Type, @ViewBuilder destination: @escaping @MainActor @Sendable (R, RouteContext) -> Content) {
        build = { AnyView(destination($0, $1)) }
    }
}

/// Presentation metadata for the particular destination being rendered.
///
/// Style describes this destination; priority describes its enclosing priority space.
/// A push inside a high-priority cover has ``Style/push`` style and ``RoutePriority/high`` priority.
public struct RoutePresentation: Hashable, Sendable {
    /// The presentation style used for this destination.
    public enum Style: Hashable, Sendable {
        /// Pushes onto a navigation stack.
        case push
        /// Replaces the declaring scope's content without a Back entry.
        case replace
        /// Presents a sheet.
        case sheet
        /// Presents a cover with the declared transition.
        case cover(Cover.Transition)
        var isModal: Bool {
            switch self { case .sheet, .cover: true; case .push, .replace: false }
        }
    }
    /// The matched presentation style, including a cover's transition.
    public let style: Style
    /// The effective priority, including priority inherited from an enclosing flow.
    public let priority: RoutePriority
}

/// Values supplied by Departure for a destination's own scope during view construction.
///
/// Contexts are created on the main actor. Routing actions retain their scope identity:
/// they do not retarget another destination after that scope leaves navigation state.
/// Read environment values during builder evaluation, including the destination's own
/// routing values. SwiftUI environment changes reevaluate the builder. Copy individual
/// environment values for later use; retained contexts do not provide an environment
/// lookup contract outside view construction.
public struct RouteContext {
    /// The router bound to this destination's scope.
    public let router: Router
    /// Unwinds this exact scope, optionally delivering a payload.
    public let unwindRoute: UnwindRouteAction
    /// The destination's actual style and effective priority after route resolution.
    public let presentation: RoutePresentation
    /// The environment visible to this destination during the current builder evaluation.
    public let environment: EnvironmentValues
}
