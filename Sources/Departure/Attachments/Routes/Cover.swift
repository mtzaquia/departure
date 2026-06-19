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

/// Declares a route as a full-screen cover.
///
/// ```swift
/// .routes {
///     Cover(OnboardingRoute.self)
///     Cover(LoginRoute.self, priority: .high)
///     Cover(NoticeRoute.self, transition: .fade)
/// }
/// ```
public struct Cover: RouteDeclaration, Sendable {
    let declaration: AnyRouteDeclaration

    /// Creates a cover declaration.
    ///
    /// - Important: Set `providesNavigation` to `false` when the route destination
    ///   already provides its own navigation container.
    public init<R: Route>(
        _ routeType: R.Type,
        priority: RoutePriority = .normal,
        transition: Transition = .slide,
        providesNavigation: Bool = true
    ) {
        self.declaration = AnyRouteDeclaration(
            routeType: routeType,
            kind: .cover(priority: priority, transition: transition, providesNavigation: providesNavigation)
        )
    }

    public var _routeDeclarations: [AnyRouteDeclaration] {
        [declaration]
    }
}

extension Cover {
    /// Animation style for ``Cover``.
    public enum Transition: Hashable, Sendable, CaseIterable {
        /// Uses SwiftUI full-screen cover movement.
        case slide

        /// Uses a cross-dissolve presentation.
        case fade
    }
}
