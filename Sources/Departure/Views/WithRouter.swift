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

/// Installs a ``Router`` and the root route scope.
///
/// ```swift
/// WithRouter {
///     AppView()
/// }
/// ```
public struct WithRouter<Content: View>: View {
    @State var router: Router
    @ViewBuilder let content: Content
    let windowDestinationBuilder: WindowDestinationBuilder

    public var body: some View {
        content
            .routeScopeEnvironment(router.root, router: router)
            .environment(\.routing, RoutingAction(router: router))
            .background {
                ElevatedPrioritySheetHost(priority: .high, windowDestinationBuilder: windowDestinationBuilder)
                ElevatedPriorityCoverSlideHost(priority: .high, windowDestinationBuilder: windowDestinationBuilder)
                ElevatedPriorityCoverFadeHost(priority: .high, windowDestinationBuilder: windowDestinationBuilder)
                ElevatedPrioritySheetHost(priority: .critical, windowDestinationBuilder: windowDestinationBuilder)
                ElevatedPriorityCoverSlideHost(priority: .critical, windowDestinationBuilder: windowDestinationBuilder)
                ElevatedPriorityCoverFadeHost(priority: .critical, windowDestinationBuilder: windowDestinationBuilder)
            }
            .environment(router)
    }

    /// Creates a router host.
    ///
    /// Pass a ``Router`` when app code needs to keep an explicit reference.
    public init(router: Router? = nil, @ViewBuilder content: () -> Content) {
        self._router = State(wrappedValue: router ?? Router())
        self.content = content()
        self.windowDestinationBuilder = WindowDestinationBuilder { destination, _ in
            destination
        }
    }

    /// Creates a router host with an elevated-priority window destination customizer.
    ///
    /// Pass a ``Router`` when app code needs to keep an explicit reference.
    ///
    /// `windowDestination` customizes destinations presented through Departure's
    /// separate elevated-priority windows. Use it to explicitly forward environment
    /// values that should cross the `UIWindow` boundary.
    public init<WindowContent: View>(
        router: Router? = nil,
        @ViewBuilder _ content: () -> Content,
        @ViewBuilder windowDestination: @escaping (RouteView, EnvironmentValues) -> WindowContent
    ) {
        self._router = State(wrappedValue: router ?? Router())
        self.content = content()
        self.windowDestinationBuilder = WindowDestinationBuilder(windowDestination)
    }
}
