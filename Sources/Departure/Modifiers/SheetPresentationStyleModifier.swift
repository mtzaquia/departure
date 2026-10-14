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

import Observation
import SwiftUI

struct SheetPresentationStyleModifier: ViewModifier {
    let presentationHostID: RoutePresentationHostID

    @Environment(RouterEngine.self) private var router
    @Environment(\.routeScope) private var routeScope

    @State private var presentationState = SheetPresentationState()

    func body(content: Content) -> some View {
        let presentation = router.routePresentationBinding(
            from: routeScope,
            matching: .sheet,
            hostedBy: presentationHostID
        )
        // Read the retained route here so the first presentation receives populated content.
        let route = presentationState.route
        let isPresented = Binding(
            get: { presentationState.isPresented },
            set: { value in
                guard !value, presentationState.beginDismissal(id: route?.id) else { return }
                dismissRoute(route, through: presentation)
            }
        )

        return content
            .onChange(of: presentation.wrappedValue, initial: true) { _, route in
                presentationState.synchronize(route)
            }
            .sheet(isPresented: isPresented, onDismiss: {
                // Native dismissal may arrive without a binding write (for example, host removal).
                // A completed older presentation must never clear a successor in the route graph.
                if presentationState.beginDismissal(id: route?.id) {
                    dismissRoute(route, through: presentation)
                }
                guard presentationState.completeDismissal(id: route?.id) else { return }
                presentationState.synchronize(presentation.wrappedValue)
            }) {
                if let route {
                    RouteView(scope: route.scope, providesNavigation: route.providesNavigation,
                        lifecycleHandler: { event in
                            switch event {
                            case .created:
                                presentationState.didCreateDestination(id: route.id)
                            case .installedInWindow, .updated(isInstalledInWindow: true):
                                presentationState.didAdmitDestination(id: route.id)
                            case .updated(isInstalledInWindow: false): break
                            case .dismantled, .deinitialized:
                                if presentationState.didDismantleDestination(id: route.id) {
                                    // Read the live slot, rather than a route captured by an earlier update.
                                    presentationState.synchronize(presentation.wrappedValue)
                                }
                            }
                        })
                        .id(route.id)
                }
            }
    }

    private func dismissRoute(_ route: PresentedRoute?, through presentation: Binding<PresentedRoute?>) {
        guard let route, presentation.wrappedValue?.id == route.id else { return }
        presentation.wrappedValue = nil
    }
}

/// Retains the exiting destination until native dismissal finishes, before admitting a successor.
@Observable
final class SheetPresentationState {
    private(set) var route: PresentedRoute?
    private(set) var isPresented = false
    @ObservationIgnored private var hasCreatedDestination = false
    @ObservationIgnored private var hasAdmittedPresentation = false

    func synchronize(_ incoming: PresentedRoute?) {
        guard let route else {
            replaceUnadmittedDestination(with: incoming)
            return
        }
        guard isPresented else { return }
        guard incoming?.id == route.id else {
            // A created off-window destination must dismantle before its successor is admitted.
            // Content never created has no native completion callback to wait for.
            guard hasCreatedDestination || hasAdmittedPresentation || route.scope.isInstalledInView else {
                replaceUnadmittedDestination(with: incoming)
                return
            }
            isPresented = false
            return
        }
        self.route = incoming
    }

    func didCreateDestination(id: AnyHashable) {
        guard route?.id == id else { return }
        hasCreatedDestination = true
    }

    func didAdmitDestination(id: AnyHashable) {
        guard route?.id == id else { return }
        hasAdmittedPresentation = true
    }

    @discardableResult
    func didDismantleDestination(id: AnyHashable) -> Bool {
        guard let route, route.id == id, !isPresented,
              !hasAdmittedPresentation, !route.scope.isInstalledInView else { return false }
        return completeDismissal(id: id)
    }

    private func replaceUnadmittedDestination(with incoming: PresentedRoute?) {
        hasCreatedDestination = false
        hasAdmittedPresentation = false
        route = incoming
        isPresented = incoming != nil
    }

    func beginDismissal(id: AnyHashable?) -> Bool {
        guard let route, route.id == id, isPresented else { return false }
        isPresented = false
        return true
    }

    func completeDismissal(id: AnyHashable?) -> Bool {
        guard let route, route.id == id else { return false }
        self.route = nil
        isPresented = false
        return true
    }
}

struct ElevatedPrioritySheetHost: View {
    @Environment(RouterEngine.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    let priority: RoutePriority
    let windowDestinationBuilder: WindowDestinationBuilder

    var body: some View {
        let presentation = router.elevatedRoutePresentationBinding(priority: priority, matching: .sheet)

        ElevatedPriorityPresentationWindowBridge(
            priority: priority,
            route: presentation,
            sourceScenePhase: scenePhase,
            windowDestinationBuilder: windowDestinationBuilder
        ) { presentation, onDismiss in
            ElevatedPrioritySheetPresenter(
                onDismiss: onDismiss,
                destination: presentation.destination
            )
            .environment(router)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Private

struct ElevatedPrioritySheetPresenter: View {
    let onDismiss: @MainActor () -> Void
    let destination: AnyView

    @State private var isPresented = false

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                destination
            }
            .onLifecycleEvent { _, _, event in
                if case .installedInWindow(isInitial: true) = event {
                    isPresented = true
                }
            }
    }
}
