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

    var body: some View {
        let presentation = router.highPriorityRoutePresentationBinding(matching: .cover(.fade))

        HighPriorityPresentationWindowBridge(route: presentation) { route, onDismiss in
            HighPriorityCoverFadePresenter(
                route: route,
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
            route: route,
            router: router,
            onDismiss: {
                route = nil
            }
        )
    }
}

private struct HighPriorityCoverFadePresenter: View {
    let route: RoutePresentation
    let router: Router
    let onDismiss: @MainActor () -> Void

    var body: some View {
        CrossDissolveModalPresenter(
            route: route,
            router: router,
            onDismiss: onDismiss
        )
    }
}

private struct CrossDissolveModalPresenter: UIViewControllerRepresentable {
    let route: RoutePresentation?
    let router: Router
    let onDismiss: @MainActor () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(
            route: route,
            router: router,
            onDismiss: onDismiss
        )
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.dismissPresentedRoute(animated: false)
    }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        private var pendingRoute: RoutePresentation?
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
            route: RoutePresentation?,
            router: Router,
            onDismiss: @escaping @MainActor () -> Void
        ) {
            self.router = router
            self.onDismiss = onDismiss

            guard let route else {
                pendingRoute = nil
                dismissPresentedRoute(animated: true)
                return
            }

            pendingRoute = route

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
                let pendingRoute,
                let router
            else {
                return
            }

            if presentedRouteID == pendingRoute.id {
                hostingController?.rootView = rootView(for: pendingRoute, router: router)
                self.pendingRoute = nil
                return
            }

            if hostingController != nil {
                dismissPresentedRoute(animated: true)
                return
            }

            let hostingController = UIHostingController(
                rootView: rootView(for: pendingRoute, router: router)
            )
            hostingController.view.backgroundColor = .clear
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve
            hostingController.presentationController?.delegate = self

            self.hostingController = hostingController
            self.presentedRouteID = pendingRoute.id
            self.pendingRoute = nil

            present(hostingController, animated: true)
        }

        private func rootView(for route: RoutePresentation, router: Router) -> AnyView {
            AnyView(
                RouteView(
                    scope: route.scope,
                    providesNavigation: route.providesNavigation
                )
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
    let route: RoutePresentation
    let router: Router

    init(
        route: RoutePresentation,
        router: Router,
        onDismiss _: @escaping @MainActor () -> Void
    ) {
        self.route = route
        self.router = router
    }

    var body: some View {
        CrossDissolveModalPresenter(
            route: route,
            router: router
        )
    }
}

private struct CrossDissolveModalPresenter: View {
    let route: RoutePresentation?
    let router: Router

    var body: some View {
        if let route {
            RouteView(
                scope: route.scope,
                providesNavigation: route.providesNavigation
            )
            .environment(router)
            .environment(\.routing, RoutingAction(router: router))
        }
    }
}
#endif
