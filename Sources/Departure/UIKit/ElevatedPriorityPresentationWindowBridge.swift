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

#if canImport(UIKit)
import UIKit

@Observable
final class ElevatedPriorityCascadedScenePhase {
    var value: ScenePhase

    init(_ value: ScenePhase) {
        self.value = value
    }
}

struct ElevatedPriorityPresentationWindowBridge<HostedContent: View>: UIViewControllerRepresentable {
    let priority: RoutePriority
    let router: RouterEngine
    @Binding var route: PresentedRoute?
    let sourceScenePhase: ScenePhase
    let windowDestinationBuilder: WindowDestinationBuilder
    let content: (RouteDestinationSnapshot, @escaping @MainActor () -> Void) -> HostedContent

    func makeUIViewController(context: Context) -> Controller {
        Controller(content: content)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.content = content
        controller.update(
            priority: priority,
            desiredRoute: { route },
            router: router,
            sourceScenePhase: sourceScenePhase,
            windowDestinationBuilder: windowDestinationBuilder
        )
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.detach()
    }

    private struct CascadedScenePhaseHost: View {
        @State private var scenePhase: ElevatedPriorityCascadedScenePhase
        let content: HostedContent

        init(scenePhase: ElevatedPriorityCascadedScenePhase, content: HostedContent) {
            self._scenePhase = State(initialValue: scenePhase)
            self.content = content
        }

        var body: some View {
            content
                .environment(\.scenePhase, scenePhase.value)
        }
    }

    final class Controller: UIViewController {
        var content: (RouteDestinationSnapshot, @escaping @MainActor () -> Void) -> HostedContent

        private weak var previousKeyWindow: UIWindow?
        private var window: PassThroughWindow?
        private var hostingController: WindowRootHostingController<CascadedScenePhaseHost>?
        private var cascadedScenePhase: ElevatedPriorityCascadedScenePhase?
        private let lifetime = NativePresentationLifetime()
        private var desiredRoute: (() -> PresentedRoute?)?
        private var router: RouterEngine?
        private var priority: RoutePriority?
        private var latestSourceScenePhase: ScenePhase?
        private var windowDestinationBuilder = WindowDestinationBuilder.passthrough

        init(content: @escaping (RouteDestinationSnapshot, @escaping @MainActor () -> Void) -> HostedContent) {
            self.content = content
            super.init(nibName: nil, bundle: nil)
        }

        // Work around swiftlang/swift#90385.
        @_optimize(none)
        deinit {}

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func update(
            priority: RoutePriority,
            desiredRoute: @escaping () -> PresentedRoute?,
            router: RouterEngine,
            sourceScenePhase: ScenePhase,
            windowDestinationBuilder: WindowDestinationBuilder
        ) {
            self.priority = priority
            self.desiredRoute = desiredRoute
            self.router = router
            self.latestSourceScenePhase = sourceScenePhase
            self.windowDestinationBuilder = windowDestinationBuilder
            synchronize()
        }

        private func synchronize() {
            let wasPresented = lifetime.isPresented
            lifetime.synchronize(desiredRoute?()) {
                RouteDestinationSnapshot(route: $0, destinationBuilder: windowDestinationBuilder)
            }
            guard let presentation = lifetime.presentation else { return }
            if !lifetime.isPresented {
                if wasPresented { dismissWindow() }
                return
            }
            if window != nil {
                cascadedScenePhase?.value = latestSourceScenePhase ?? presentation.route.sourceEnvironment.scenePhase
            } else if let priority {
                present(presentation, priority: priority,
                    sourceScenePhase: latestSourceScenePhase ?? presentation.route.sourceEnvironment.scenePhase)
            }
        }

        func detach() {
            desiredRoute = nil
            guard let id = lifetime.presentation?.id else { return }
            if lifetime.beginDismissal(of: id) { dismissWindow() }
        }

        private func present(
            _ presentation: RouteDestinationSnapshot,
            priority: RoutePriority,
            sourceScenePhase: ScenePhase
        ) {
            guard let scene = resolveScene() else {
                if let router { lifetime.completeDismissal(of: presentation.id, in: router) }
                return
            }

            let window = PassThroughWindow(windowScene: scene)
            previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
            window.windowLevel = windowLevel(for: priority, in: scene)
            window.backgroundColor = .clear

            let cascadedScenePhase = ElevatedPriorityCascadedScenePhase(sourceScenePhase)
            let hostingController = WindowRootHostingController(
                rootView: makeHost(for: presentation, scenePhase: cascadedScenePhase)
            )
            hostingController.view.backgroundColor = .clear
            hostingController.onDismiss = { [weak self] in
                self?.dismissFromPresentedHost(id: presentation.id)
            }
            window.rootViewController = hostingController

            self.window = window
            self.hostingController = hostingController
            self.cascadedScenePhase = cascadedScenePhase

            lifetime.didAdmitPresentation(of: presentation.id)
            // Install the transparent native base immediately. The SwiftUI presenter
            // starts its own animation after this base enters the window hierarchy.
            UIView.performWithoutAnimation { window.makeKeyAndVisible() }
        }

        private func makeHost(
            for presentation: RouteDestinationSnapshot,
            scenePhase: ElevatedPriorityCascadedScenePhase
        ) -> CascadedScenePhaseHost {
            CascadedScenePhaseHost(scenePhase: scenePhase,
                content: content(presentation, { [weak self] in
                    self?.dismissFromPresentedHost(id: presentation.id)
                }))
        }

        private func dismissFromPresentedHost(id: PresentedRoute.ID) {
            guard lifetime.beginDismissal(of: id) else { return }
            if let scope = lifetime.presentation?.route.scope, scope.isNativePresentationOwned(by: lifetime) {
                router?.nativePresentationDidDismiss(scope)
            }
            dismissWindow()
        }

        private func dismissWindow() {
            guard let presentation = lifetime.presentation else { return }
            hostingController?.onDismiss = nil
            let dismissedWindow = window
            let completion: () -> Void = { [self] in
                // Retain the native owner through destruction, even if its representable is gone.
                guard lifetime.presentation?.id == presentation.id else { return }
                let restoresKeyWindow = dismissedWindow?.isKeyWindow == true
                UIView.performWithoutAnimation {
                    dismissedWindow?.isHidden = true
                    dismissedWindow?.rootViewController = nil
                    if restoresKeyWindow, previousKeyWindow?.isHidden == false { previousKeyWindow?.makeKey() }
                }
                previousKeyWindow = nil
                window = nil
                hostingController = nil
                cascadedScenePhase = nil
                if let router { lifetime.completeDismissal(of: presentation.id, in: router) }
                synchronize()
            }
            if let root = dismissedWindow?.rootViewController, root.presentedViewController != nil {
                root.dismiss(animated: true, completion: completion)
            } else {
                completion()
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

        private func windowLevel(for priority: RoutePriority, in scene: UIWindowScene) -> UIWindow.Level {
            switch priority {
            case .critical:
                return .alert

            case .high:
                return UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 1)

            case .default:
                return UIWindow.Level(rawValue: resolveHighestWindowLevel(in: scene).rawValue + 1)
            }
        }
    }
}
#endif
