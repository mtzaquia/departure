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

struct CoverFadePresentationStyleModifier: ViewModifier {
    let presentationHostID: RoutePresentationHostID

    @Environment(Router.self) private var router
    @Environment(\.routeScope) private var routeScope

    func body(content: Content) -> some View {
        let presentation = router.routePresentationBinding(
            from: routeScope,
            matching: .cover(.fade),
            hostedBy: presentationHostID
        )

        content
#if canImport(UIKit)
            .background {
                CoverFadeModalPresenter(
                    route: presentation,
                    router: router
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

struct ElevatedPriorityCoverFadeHost: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    let priority: RoutePriority
    let windowDestinationBuilder: WindowDestinationBuilder

    var body: some View {
        let presentation = router.elevatedRoutePresentationBinding(priority: priority, matching: .cover(.fade))

        ElevatedPriorityPresentationWindowBridge(
            priority: priority,
            route: presentation,
            sourceScenePhase: scenePhase,
            windowDestinationBuilder: windowDestinationBuilder
        ) { presentation, onDismiss in
            ElevatedPriorityCoverFadePresenter(
                presentation: presentation,
                router: router,
                onDismiss: onDismiss
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Private

#if canImport(UIKit)
import UIKit

@Observable
private final class CoverFadePresentationState {
    enum SystemPresentationProjection {
        case value
    }

    var systemPresentation: RouteDestinationSnapshot?
    var isContentVisible = false
    var isDismissing = false
    var fadeInTaskID: RoutePresentation.ID?
    var dismissalTaskID: RoutePresentation.ID?

    subscript(systemPresentation _: SystemPresentationProjection) -> RouteDestinationSnapshot? {
        get {
            systemPresentation
        }
        set {
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else {
                    return
                }

                guard let newValue else {
                    dismissWithFade()
                    return
                }

                setSystemPresentation(newValue)
            }
        }
    }

    func dismissWithFade() {
        guard systemPresentation != nil, isDismissing == false else {
            return
        }

        isDismissing = true
        fadeInTaskID = nil
        dismissalTaskID = systemPresentation?.id
    }

    func setSystemPresentation(_ presentation: RouteDestinationSnapshot?) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            systemPresentation = presentation
        }
    }
}

private struct CoverFadeModalPresenter: View {
    @Binding var route: RoutePresentation?
    @Environment(\.scenePhase) private var scenePhase
    let router: Router
    @State private var presentationState = CoverFadePresentationState()

    var body: some View {
        @Bindable var presentationState = presentationState

        Color.clear
            .fullScreenCover(item: $presentationState[systemPresentation: .value], onDismiss: {
                scheduleStateMutation {
                    finishSystemDismissal()
                }
            }) { presentation in
                destination(for: presentation)
                    .id(presentation.id)
                    .opacity(presentationState.isContentVisible ? 1 : 0)
                    .presentationBackground(.clear)
                    .onLifecycleEvent { event in
                        if case .installedInWindow(isInitial: true) = event {
                            scheduleStateMutation {
                                fadeInContentIfNeeded(for: presentation.id)
                            }
                        }
                    }
            }
            .transaction { transaction in
                transaction.disablesAnimations = true
            }
            .task(id: presentationState.fadeInTaskID) {
                await fadeInContent(for: presentationState.fadeInTaskID)
            }
            .task(id: presentationState.dismissalTaskID) {
                await finishDismissal(for: presentationState.dismissalTaskID)
            }
            .onLifecycleEvent { event in
                switch event {
                case .installedInWindow, .updated(isInstalledInWindow: true):
                    scheduleStateMutation {
                        syncPresentation()
                    }

                case .updated(isInstalledInWindow: false), .dismantled, .deinitialized:
                    break
                }
            }
            .onChange(of: route?.id) { _, _ in
                scheduleStateMutation {
                    syncPresentation()
                }
            }
            .onChange(of: scenePhase) { _, _ in
                scheduleStateMutation {
                    syncPresentation()
                }
            }
    }

    private func scheduleStateMutation(_ mutation: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await Task.yield()
            mutation()
        }
    }

    private func syncPresentation() {
        if presentationState.isDismissing {
            guard let route, route.id != presentationState.systemPresentation?.id else {
                return
            }

            presentationState.dismissalTaskID = nil
            presentationState.fadeInTaskID = nil
            presentationState.isDismissing = false
        }

        guard let route else {
            presentationState.dismissWithFade()
            return
        }

        let presentation = RouteDestinationSnapshot(
            route: route,
            destinationBuilder: router.windowDestinationBuilder
        )

        guard presentationState.systemPresentation?.id != presentation.id else {
            return
        }

        presentationState.dismissalTaskID = nil
        presentationState.fadeInTaskID = nil
        presentationState.isContentVisible = false
        presentationState.setSystemPresentation(presentation)
    }

    private func fadeInContentIfNeeded(for id: RoutePresentation.ID) {
        guard presentationState.isDismissing == false,
              presentationState.systemPresentation?.id == id
        else {
            return
        }

        presentationState.fadeInTaskID = id
    }

    private func fadeInContent(for id: RoutePresentation.ID?) async {
        guard let id else {
            return
        }

        await Task.yield()
        guard
            Task.isCancelled == false,
            presentationState.isDismissing == false,
            presentationState.systemPresentation?.id == id
        else {
            return
        }

        withAnimation(.easeInOut(duration: presentationFadeDuration)) {
            presentationState.isContentVisible = true
        }
    }

    private func finishDismissal(for id: RoutePresentation.ID?) async {
        guard let id else {
            return
        }

        withAnimation(.easeInOut(duration: dismissalFadeDuration)) {
            presentationState.isContentVisible = false
        }

        try? await Task.sleep(for: .seconds(dismissalFadeDuration))
        guard
            Task.isCancelled == false,
            presentationState.isDismissing,
            presentationState.systemPresentation?.id == id
        else {
            return
        }

        presentationState.setSystemPresentation(nil)
        route = nil
        presentationState.isDismissing = false
        presentationState.dismissalTaskID = nil
    }

    private func finishSystemDismissal() {
        guard presentationState.isDismissing
            || route == nil
            || presentationState.systemPresentation == nil
        else {
            return
        }

        presentationState.fadeInTaskID = nil
        presentationState.dismissalTaskID = nil
        presentationState.isDismissing = false
        presentationState.isContentVisible = false
        presentationState.systemPresentation = nil
        route = nil
    }

    private func destination(for presentation: RouteDestinationSnapshot) -> some View {
        presentation.destination
            .environment(router)
            .environment(\.scenePhase, scenePhase)
    }

    private var presentationFadeDuration: TimeInterval {
        0.35
    }

    private var dismissalFadeDuration: TimeInterval {
        0.25
    }
}

private struct ElevatedPriorityCoverFadePresenter: View {
    let presentation: RouteDestinationSnapshot
    let router: Router
    let onDismiss: @MainActor () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        CrossDissolveModalPresenter(
            presentation: presentation,
            router: router,
            sourceScenePhase: scenePhase,
            onDismiss: onDismiss
        )
    }
}

private struct CrossDissolveModalPresenter: UIViewControllerRepresentable {
    let presentation: RouteDestinationSnapshot?
    let router: Router
    let sourceScenePhase: ScenePhase
    let onDismiss: @MainActor () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(
            presentation: presentation,
            router: router,
            sourceScenePhase: sourceScenePhase,
            onDismiss: onDismiss
        )
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.dismissPresentedRoute(animated: false)
    }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        private var pendingPresentation: RouteDestinationSnapshot?
        private var router: Router?
        private var sourceScenePhase: ScenePhase?
        private var onDismiss: (@MainActor () -> Void)?
        private var presentedRouteID: RoutePresentation.ID?
        private var presentedScenePhase: ScenePhase?
        private var hostingController: PassThroughModalHostingController<AnyView>?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentPendingRouteIfNeeded()
        }

        func update(
            presentation: RouteDestinationSnapshot?,
            router: Router,
            sourceScenePhase: ScenePhase,
            onDismiss: @escaping @MainActor () -> Void
        ) {
            self.router = router
            self.sourceScenePhase = sourceScenePhase
            self.onDismiss = onDismiss

            guard let presentation else {
                pendingPresentation = nil
                dismissPresentedRoute(animated: true)
                return
            }

            if presentedRouteID == presentation.route.id {
                updatePresentedScenePhaseIfNeeded(
                    presentation: presentation,
                    router: router,
                    sourceScenePhase: sourceScenePhase
                )
                return
            }

            if pendingPresentation?.route.id != presentation.route.id {
                pendingPresentation = presentation
            }

            guard view.window != nil else {
                return
            }

            presentPendingRouteIfNeeded()
        }

        func dismissPresentedRoute(animated: Bool) {
            guard let hostingController else {
                return
            }

            hostingController.dismiss(animated: animated) { [weak self] in
                self?.finishDismiss()
            }
        }

        private func presentPendingRouteIfNeeded() {
            guard
                let pendingPresentation,
                let router,
                let sourceScenePhase
            else {
                return
            }

            if presentedRouteID == pendingPresentation.route.id {
                hostingController?.rootView = rootView(
                    router: router,
                    destination: pendingPresentation.destination,
                    sourceScenePhase: sourceScenePhase
                )
                self.pendingPresentation = nil
                return
            }

            if hostingController != nil {
                dismissPresentedRoute(animated: true)
                return
            }

            let hostingController = PassThroughModalHostingController(
                rootView: rootView(
                    router: router,
                    destination: pendingPresentation.destination,
                    sourceScenePhase: sourceScenePhase
                )
            )
            hostingController.view.backgroundColor = .clear
            hostingController.presentationController?.delegate = self
            hostingController.onDismiss = { [weak self] in
                self?.finishDismiss()
            }

            self.hostingController = hostingController
            self.presentedRouteID = pendingPresentation.route.id
            self.presentedScenePhase = sourceScenePhase
            self.pendingPresentation = nil

            present(hostingController, animated: true)
        }

        private func updatePresentedScenePhaseIfNeeded(
            presentation: RouteDestinationSnapshot,
            router: Router,
            sourceScenePhase: ScenePhase
        ) {
            guard presentedScenePhase != sourceScenePhase else {
                return
            }

            presentedScenePhase = sourceScenePhase
            hostingController?.rootView = rootView(
                router: router,
                destination: presentation.destination,
                sourceScenePhase: sourceScenePhase
            )
        }

        private func rootView(
            router: Router,
            destination: AnyView,
            sourceScenePhase: ScenePhase
        ) -> AnyView {
            AnyView(
                destination
                    .environment(router)
                    .environment(\.scenePhase, sourceScenePhase)
            )
        }

        private func finishDismiss() {
            guard hostingController != nil || presentedRouteID != nil else {
                return
            }

            hostingController = nil
            presentedRouteID = nil
            presentedScenePhase = nil
            onDismiss?()

            presentPendingRouteIfNeeded()
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            finishDismiss()
        }
    }
}
#else
private struct ElevatedPriorityCoverFadePresenter: View {
    let presentation: RouteDestinationSnapshot
    let router: Router

    init(
        presentation: RouteDestinationSnapshot,
        router: Router,
        onDismiss _: @escaping @MainActor () -> Void
    ) {
        self.presentation = presentation
        self.router = router
    }

    var body: some View {
        CrossDissolveModalPresenter(
            presentation: presentation,
            router: router,
        )
    }
}

private struct CrossDissolveModalPresenter: View {
    let presentation: RouteDestinationSnapshot?
    let router: Router

    var body: some View {
        if let presentation {
            presentation.destination
                .environment(router)
        }
    }
}
#endif
