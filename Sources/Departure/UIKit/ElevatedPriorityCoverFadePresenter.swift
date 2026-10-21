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

#if canImport(UIKit)
import UIKit

struct ElevatedPriorityCoverFadePresenter: View {
    let presentation: RouteDestinationSnapshot
    let router: RouterEngine
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
    let presentation: RouteDestinationSnapshot
    let router: RouterEngine
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
        private var presentation: RouteDestinationSnapshot?
        private var router: RouterEngine?
        private var sourceScenePhase: ScenePhase?
        private var onDismiss: (@MainActor () -> Void)?
        private var hasPresented = false
        private var presentedScenePhase: ScenePhase?
        private var hostingController: PassThroughModalHostingController<AnyView>?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentIfNeeded()
        }

        func update(
            presentation: RouteDestinationSnapshot,
            router: RouterEngine,
            sourceScenePhase: ScenePhase,
            onDismiss: @escaping @MainActor () -> Void
        ) {
            self.router = router
            self.sourceScenePhase = sourceScenePhase
            self.onDismiss = onDismiss

            self.presentation = presentation
            if hostingController != nil {
                updatePresentedScenePhaseIfNeeded(presentation: presentation, router: router, sourceScenePhase: sourceScenePhase)
            } else {
                presentIfNeeded()
            }
        }

        func dismissPresentedRoute(animated: Bool) {
            hostingController?.dismiss(animated: animated) { [self] in finishDismiss() }
        }

        private func presentIfNeeded() {
            guard !hasPresented, view.window != nil, let presentation, let router, let sourceScenePhase else { return }
            let hostingController = PassThroughModalHostingController(rootView: rootView(
                router: router, destination: presentation.destination, sourceScenePhase: sourceScenePhase))
            hostingController.view.backgroundColor = .clear
            hostingController.presentationController?.delegate = self
            hostingController.onDismiss = { [weak self] in self?.finishDismiss() }
            self.hostingController = hostingController
            hasPresented = true
            presentedScenePhase = sourceScenePhase
            present(hostingController, animated: true)
        }

        private func updatePresentedScenePhaseIfNeeded(
            presentation: RouteDestinationSnapshot,
            router: RouterEngine,
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
            router: RouterEngine,
            destination: AnyView,
            sourceScenePhase: ScenePhase
        ) -> AnyView {
            AnyView(
                destination
                    .environment(\.routerEngine, router)
                    .environment(\.scenePhase, sourceScenePhase)
            )
        }

        private func finishDismiss() {
            guard hostingController != nil else {
                return
            }

            hostingController = nil
            presentedScenePhase = nil
            onDismiss?()
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            finishDismiss()
        }
    }
}
#endif
