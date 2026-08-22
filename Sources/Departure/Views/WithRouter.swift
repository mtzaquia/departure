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
            .background {
                WindowDestinationBuilderRegistration(
                    router: router,
                    windowDestinationBuilder: windowDestinationBuilder
                )
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
        let router = router ?? Router()
        router.windowDestinationBuilder = .passthrough
        self._router = State(wrappedValue: router)
        self.content = content()
        self.windowDestinationBuilder = .passthrough
    }

    /// Creates a router host with a detached presentation customizer.
    ///
    /// Pass a ``Router`` when app code needs to keep an explicit reference.
    ///
    /// `windowDestination` customizes destinations that Departure renders in a detached
    /// SwiftUI host, including elevated-priority presentations and normal-priority fade
    /// covers. Use it to explicitly forward environment values those destinations need.
    public init<WindowContent: View>(
        router: Router? = nil,
        @ViewBuilder _ content: () -> Content,
        @ViewBuilder windowDestination: @escaping (RouteView, EnvironmentValues) -> WindowContent
    ) {
        let router = router ?? Router()
        let windowDestinationBuilder = WindowDestinationBuilder(windowDestination)
        router.windowDestinationBuilder = windowDestinationBuilder
        self._router = State(wrappedValue: router)
        self.content = content()
        self.windowDestinationBuilder = windowDestinationBuilder
    }
}

private struct WindowDestinationBuilderRegistration: View {
    let router: Router
    let windowDestinationBuilder: WindowDestinationBuilder

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onLifecycleEvent { event in
                switch event {
                case .installedInWindow, .updated:
                    router.windowDestinationBuilder = windowDestinationBuilder

                case .dismantled, .deinitialized:
                    break
                }
            }
    }
}
