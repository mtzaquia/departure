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

struct CoverSlidePresentationStyleModifier: ViewModifier {
    @Environment(Router.self) private var router
    @Environment(\.routeScope) private var routeScope

    func body(content: Content) -> some View {
        let presentation = router.routePresentationBinding(
            from: routeScope,
            matching: .cover(.slide)
        )

        content
#if canImport(UIKit)
            .fullScreenCover(item: presentation) { route in
                RouteView(
                    scope: route.scope,
                    providesNavigation: route.providesNavigation
                )
            }
#else
            .sheet(item: presentation) { route in
                RouteView(
                    scope: route.scope,
                    providesNavigation: route.providesNavigation
                )
            }
#endif
    }
}

struct ElevatedPriorityCoverSlideHost: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    let priority: RoutePriority
    let windowDestinationBuilder: WindowDestinationBuilder

    var body: some View {
        let presentation = router.elevatedRoutePresentationBinding(priority: priority, matching: .cover(.slide))

        ElevatedPriorityPresentationWindowBridge(
            priority: priority,
            route: presentation,
            sourceScenePhase: scenePhase,
            windowDestinationBuilder: windowDestinationBuilder
        ) { presentation, onDismiss in
            ElevatedPriorityCoverSlidePresenter(
                onDismiss: onDismiss,
                destination: presentation.destination
            )
                .environment(router)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Private

private struct ElevatedPriorityCoverSlidePresenter: View {
    let onDismiss: @MainActor () -> Void
    let destination: AnyView

    @State private var isPresented = false

    var body: some View {
        Color.clear
            .ignoresSafeArea()
#if canImport(UIKit)
            .fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) {
                destination
            }
#else
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                destination
            }
#endif
            .onLifecycleEvent { event in
                if case .installedInWindow(isInitial: true) = event {
                    isPresented = true
                }
            }
    }
}
