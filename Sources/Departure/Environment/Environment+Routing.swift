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

/// Performs routing commands from SwiftUI views.
///
/// This compatibility type is deprecated. Use ``Router`` from the SwiftUI environment instead.
///
/// ```swift
/// @Environment(\.routing) private var routing
///
/// Button("Settings") {
///     routing(.present(SettingsRoute()))
/// }
/// ```
@available(*, deprecated, message: "Use `@Environment(Router.self)` and call methods on `Router` instead.")
public struct RoutingAction: Equatable {
    /// A routing command.
    public enum Request {
        /// Requests a route presentation.
        case present(any Route)

        /// Dismisses route scopes, optionally presenting another route after dismissal.
        case unwind(to: Router.UnwindTarget? = nil, thenPresent: (any Route)? = nil)

        /// Performs an action from the current route scope.
        case perform(any Action)
    }

    private let id = UUID()
    private let handle: @MainActor (Request) -> Void

    /// Creates a routing command handler.
    public init(handle: @escaping @MainActor (Request) -> Void) {
        self.handle = handle
    }

    /// Performs a routing command.
    ///
    /// ```swift
    /// routing(.unwind(to: .root))
    /// ```
    public func callAsFunction(_ request: Request) {
        handle(request)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

extension RoutingAction {
    init(router: Router) {
        self.init { request in
            switch request {
            case let .present(route):
                Task {
                    await router.present(route)
                }

            case let .unwind(target, route):
                Task {
                    guard await router.unwind(to: target) else {
                        return
                    }

                    if let route {
                        await router.present(route)
                    }
                }

            case let .perform(action):
                Task {
                    await router.perform(action)
                }
            }
        }
    }
}

public extension EnvironmentValues {
    /// Routes from the nearest ``WithRouter``.
    ///
    /// This compatibility value is deprecated. Use ``Router`` from the SwiftUI environment instead.
    ///
    /// ```swift
    /// @Environment(\.routing) private var routing
    /// ```
    @available(*, deprecated, message: "Use `@Environment(Router.self)` instead.")
    @Entry var routing = RoutingAction { _ in }
}
