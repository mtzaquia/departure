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

struct HighPriorityPresentationWindowBridge<HostedContent: View>: UIViewControllerRepresentable {
    @Binding var route: RoutePresentation?
    let windowDestinationBuilder: WindowDestinationBuilder
    let content: (RouteDestinationSnapshot, @escaping @MainActor () -> Void) -> HostedContent

    func makeUIViewController(context: Context) -> Controller {
        Controller(content: content)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.content = content
        controller.update(
            route: route,
            windowDestinationBuilder: windowDestinationBuilder,
            clearRoute: {
                route = nil
            }
        )
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.detach()
    }

    final class Controller: UIViewController {
        var content: (RouteDestinationSnapshot, @escaping @MainActor () -> Void) -> HostedContent

        private weak var previousKeyWindow: UIWindow?
        private var window: PassThroughWindow?
        private var hostingController: UIHostingController<HostedContent>?
        private var presentedRouteID: RoutePresentation.ID?
        private var pendingPresentation: RouteDestinationSnapshot?
        private var clearRoute: (@MainActor () -> Void)?
        private var isDismissingWindow = false
        private var ignoresHostDismiss = false

        init(content: @escaping (RouteDestinationSnapshot, @escaping @MainActor () -> Void) -> HostedContent) {
            self.content = content
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func update(
            route: RoutePresentation?,
            windowDestinationBuilder: WindowDestinationBuilder,
            clearRoute: @escaping @MainActor () -> Void
        ) {
            self.clearRoute = clearRoute

            guard isDismissingWindow == false else {
                guard let route else {
                    pendingPresentation = nil
                    return
                }

                if pendingPresentation?.route.id != route.id {
                    pendingPresentation = RouteDestinationSnapshot(
                        route: route,
                        destinationBuilder: windowDestinationBuilder
                    )
                }

                return
            }

            guard let route else {
                pendingPresentation = nil
                dismissWindow(callClearRoute: false)
                return
            }

            if route.id == presentedRouteID {
                return
            }

            let presentation = RouteDestinationSnapshot(
                route: route,
                destinationBuilder: windowDestinationBuilder
            )

            if presentedRouteID != nil {
                pendingPresentation = presentation
                dismissWindow(callClearRoute: false, presentsPendingRoute: true)
                return
            }

            present(presentation)
        }

        func detach() {
            dismissWindow(callClearRoute: false)
        }

        private func present(_ presentation: RouteDestinationSnapshot) {
            guard let scene = resolveScene() else {
                clearRoute?()
                return
            }

            let window = PassThroughWindow(windowScene: scene)
            previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
            window.windowLevel = UIWindow.Level(rawValue: resolveHighestWindowLevel(in: scene).rawValue + 1)
            window.backgroundColor = .clear

            let hostingController = UIHostingController(rootView: makeHost(for: presentation))
            hostingController.view.backgroundColor = .clear
            window.rootViewController = hostingController

            self.window = window
            self.hostingController = hostingController
            self.presentedRouteID = presentation.route.id

            window.makeKeyAndVisible()
        }

        private func makeHost(for presentation: RouteDestinationSnapshot) -> HostedContent {
            let routeID = presentation.route.id
            return content(
                presentation,
                { [weak self] in
                    guard self?.presentedRouteID == routeID else {
                        return
                    }

                    guard self?.ignoresHostDismiss == false else {
                        return
                    }

                    self?.clearRoute?()
                    self?.dismissWindow(callClearRoute: false)
                }
            )
        }

        private func dismissWindow(
            callClearRoute: Bool,
            presentsPendingRoute: Bool = false
        ) {
            guard let window else {
                finishDismissWindow(
                    window: nil,
                    callClearRoute: callClearRoute,
                    presentsPendingRoute: presentsPendingRoute
                )
                return
            }

            isDismissingWindow = true
            ignoresHostDismiss = true

            let rootViewController = window.rootViewController

            let completion: () -> Void = { [weak self, weak window] in
                self?.finishDismissWindow(
                    window: window,
                    callClearRoute: callClearRoute,
                    presentsPendingRoute: presentsPendingRoute
                )
            }

            if rootViewController?.presentedViewController != nil {
                rootViewController?.dismiss(animated: true, completion: completion)
            } else {
                completion()
            }
        }

        private func finishDismissWindow(
            window dismissedWindow: PassThroughWindow?,
            callClearRoute: Bool,
            presentsPendingRoute: Bool
        ) {
            dismissedWindow?.isHidden = true
            dismissedWindow?.rootViewController = nil

            if window === dismissedWindow {
                previousKeyWindow?.makeKey()

                previousKeyWindow = nil
                window = nil
                hostingController = nil
                presentedRouteID = nil
            }

            isDismissingWindow = false
            ignoresHostDismiss = false

            if callClearRoute {
                clearRoute?()
            }

            if presentsPendingRoute, let pendingPresentation {
                self.pendingPresentation = nil
                present(pendingPresentation)
            }
        }

        private func resolveScene() -> UIWindowScene? {
            if let scene = view.window?.windowScene {
                return scene
            }

            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }

            return scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first(where: { $0.activationState == .foregroundInactive })
                ?? scenes.first
        }

        private func resolveHighestWindowLevel(in scene: UIWindowScene) -> UIWindow.Level {
            scene.windows
                .filter { $0.isHidden == false }
                .map(\.windowLevel)
                .max(by: { $0.rawValue < $1.rawValue })
                ?? .normal
        }
    }
}
#else
struct HighPriorityPresentationWindowBridge<HostedContent: View>: View {
    @Binding var route: RoutePresentation?
    @ViewBuilder let content: (
        RouteDestinationSnapshot,
        @escaping @MainActor () -> Void
    ) -> HostedContent

    init(
        route: Binding<RoutePresentation?>,
        windowDestinationBuilder _: WindowDestinationBuilder,
        @ViewBuilder content: @escaping (
            RouteDestinationSnapshot,
            @escaping @MainActor () -> Void
        ) -> HostedContent
    ) {
        self._route = route
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if let route {
            content(
                RouteDestinationSnapshot(route: route),
                {
                    self.route = nil
                }
            )
        }
    }
}
#endif
