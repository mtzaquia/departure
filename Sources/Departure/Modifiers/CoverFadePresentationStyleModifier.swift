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

struct CoverFadePresentationStyleModifier: ViewModifier {
    @Environment(Router.self) private var router
    @Environment(\.routeScope) private var routeScope

    func body(content: Content) -> some View {
        let presentation = router.routePresentationBinding(
            from: routeScope,
            matching: .cover(.fade)
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

private struct CoverFadeModalPresenter: View {
    @Binding var route: RoutePresentation?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.windowDestinationBuilder) private var windowDestinationBuilder
    let router: Router

    var body: some View {
        CrossDissolveModalPresenter(
            presentation: route.map {
                RouteDestinationSnapshot(route: $0, destinationBuilder: windowDestinationBuilder)
            },
            router: router,
            sourceScenePhase: scenePhase,
            onDismiss: {
                route = nil
            }
        )
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
                    .environment(\.routing, RoutingAction(router: router))
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
                .environment(\.routing, RoutingAction(router: router))
        }
    }
}
#endif
