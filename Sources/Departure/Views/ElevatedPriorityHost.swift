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

/// One detached presentation owner for each root priority, independent of style.
struct ElevatedPriorityHost: View {
    @RouterEnvironment private var router
    @Environment(\.scenePhase) private var scenePhase
    let priority: RoutePriority
    let windowDestinationBuilder: WindowDestinationBuilder

    var body: some View {
        #if canImport(UIKit)
        ElevatedPriorityPresentationWindowBridge(priority: priority, router: router,
            route: router.presentationBinding(for: .priority(priority)), sourceScenePhase: scenePhase,
            windowDestinationBuilder: windowDestinationBuilder) { presentation, onDismiss in
                presenter(for: presentation, onDismiss: onDismiss).environment(\.routerEngine, router)
            }
            .allowsHitTesting(false)
        #else
        Color.clear.frame(width: 0, height: 0)
            .modifier(SystemModalPresentationModifier(style: .sheet,
                route: router.presentationBinding(for: .priority(priority)).wrappedValue,
                destinationBuilder: windowDestinationBuilder))
        #endif
    }

    #if canImport(UIKit)
    @ViewBuilder
    private func presenter(for presentation: RouteDestinationSnapshot, onDismiss: @escaping @MainActor () -> Void) -> some View {
        if let style = presentation.route.scope.routePresentation?.style {
            switch style {
            case .sheet, .cover(.slide):
                ElevatedSystemPresenter(style: style, destination: presentation.destination, onDismiss: onDismiss)
            case .cover(.fade):
                ElevatedPriorityCoverFadePresenter(presentation: presentation, router: router, onDismiss: onDismiss)
            case .push, .replace:
                EmptyView()
            }
        }
    }
    #endif
}

#if canImport(UIKit)
private struct ElevatedSystemPresenter: View {
    let style: RoutePresentationKind
    let destination: AnyView
    let onDismiss: @MainActor () -> Void
    @State private var isPresented = false

    var body: some View {
        systemPresentation.onLifecycleEvent { _, _, event in
            if case .installedInWindow(isInitial: true) = event { isPresented = true }
        }
    }

    @ViewBuilder
    private var systemPresentation: some View {
        if style != .sheet {
            Color.clear.ignoresSafeArea()
                .fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) { destination }
        } else {
            Color.clear.ignoresSafeArea()
                .sheet(isPresented: $isPresented, onDismiss: onDismiss) { destination }
        }
    }
}
#endif
