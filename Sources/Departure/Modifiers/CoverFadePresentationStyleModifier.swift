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

struct HighPriorityCoverFadeHost: View {
    @Environment(Router.self) private var router
    let windowDestinationBuilder: WindowDestinationBuilder

    var body: some View {
        let presentation = router.highPriorityRoutePresentationBinding(matching: .cover(.fade))

        HighPriorityPresentationWindowBridge(
            route: presentation,
            windowDestinationBuilder: windowDestinationBuilder
        ) { presentation, onDismiss in
            HighPriorityCoverFadePresenter(
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
    let router: Router

    var body: some View {
        CrossDissolveModalPresenter(
            presentation: route.map(RouteDestinationSnapshot.init(route:)),
            router: router,
            onDismiss: {
                route = nil
            }
        )
    }
}

private struct HighPriorityCoverFadePresenter: View {
    let presentation: RouteDestinationSnapshot
    let router: Router
    let onDismiss: @MainActor () -> Void

    var body: some View {
        CrossDissolveModalPresenter(
            presentation: presentation,
            router: router,
            onDismiss: onDismiss
        )
    }
}

private struct CrossDissolveModalPresenter: UIViewControllerRepresentable {
    let presentation: RouteDestinationSnapshot?
    let router: Router
    let onDismiss: @MainActor () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(
            presentation: presentation,
            router: router,
            onDismiss: onDismiss
        )
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.dismissPresentedRoute(animated: false)
    }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        private var pendingPresentation: RouteDestinationSnapshot?
        private var router: Router?
        private var onDismiss: (@MainActor () -> Void)?
        private var presentedRouteID: RoutePresentation.ID?
        private var hostingController: UIHostingController<AnyView>?

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
            onDismiss: @escaping @MainActor () -> Void
        ) {
            self.router = router
            self.onDismiss = onDismiss

            guard let presentation else {
                pendingPresentation = nil
                dismissPresentedRoute(animated: true)
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
                let router
            else {
                return
            }

            if presentedRouteID == pendingPresentation.route.id {
                hostingController?.rootView = rootView(
                    router: router,
                    destination: pendingPresentation.destination
                )
                self.pendingPresentation = nil
                return
            }

            if hostingController != nil {
                dismissPresentedRoute(animated: true)
                return
            }

            let hostingController = UIHostingController(
                rootView: rootView(
                    router: router,
                    destination: pendingPresentation.destination
                )
            )
            hostingController.view.backgroundColor = .clear
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve
            hostingController.presentationController?.delegate = self

            self.hostingController = hostingController
            self.presentedRouteID = pendingPresentation.route.id
            self.pendingPresentation = nil

            present(hostingController, animated: true)
        }

        private func rootView(
            router: Router,
            destination: AnyView
        ) -> AnyView {
            AnyView(
                destination
                .environment(router)
                .environment(\.routing, RoutingAction(router: router))
            )
        }

        private func finishDismiss() {
            hostingController = nil
            presentedRouteID = nil
            onDismiss?()
            presentPendingRouteIfNeeded()
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            finishDismiss()
        }
    }
}
#else
private struct HighPriorityCoverFadePresenter: View {
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
