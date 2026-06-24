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

struct SheetPresentationStyleModifier: ViewModifier {
    @Environment(Router.self) private var router
    @Environment(\.routeScope) private var routeScope

    func body(content: Content) -> some View {
        let presentation = router.routePresentationBinding(from: routeScope, matching: .sheet)

        content
            .sheet(item: presentation) { route in
                RouteView(
                    scope: route.scope,
                    providesNavigation: route.providesNavigation
                )
            }
    }
}

struct HighPrioritySheetHost: View {
    @Environment(Router.self) private var router
    let windowDestinationBuilder: WindowDestinationBuilder

    var body: some View {
        let presentation = router.highPriorityRoutePresentationBinding(matching: .sheet)

        HighPriorityPresentationWindowBridge(
            priority: .high,
            route: presentation,
            windowDestinationBuilder: windowDestinationBuilder
        ) { presentation, onDismiss in
            HighPrioritySheetPresenter(
                onDismiss: onDismiss,
                destination: presentation.destination
            )
                .environment(router)
                .environment(\.routing, RoutingAction(router: router))
        }
        .allowsHitTesting(false)
    }
}

struct CriticalPrioritySheetHost: View {
    @Environment(Router.self) private var router
    let windowDestinationBuilder: WindowDestinationBuilder

    var body: some View {
        let presentation = router.elevatedRoutePresentationBinding(priority: .critical, matching: .sheet)

        HighPriorityPresentationWindowBridge(
            priority: .critical,
            route: presentation,
            windowDestinationBuilder: windowDestinationBuilder
        ) { presentation, onDismiss in
            HighPrioritySheetPresenter(
                onDismiss: onDismiss,
                destination: presentation.destination
            )
                .environment(router)
                .environment(\.routing, RoutingAction(router: router))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Private

private struct HighPrioritySheetPresenter: View {
    let onDismiss: @MainActor () -> Void
    let destination: AnyView

    @State private var isPresented = false

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                destination
            }
            .onLifecycleEvent { event in
                if case .installedInWindow(isInitial: true) = event {
                    isPresented = true
                }
            }
    }
}
