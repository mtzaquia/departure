#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit
@testable import Departure

@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowPresentationLifetimeUIKitTests {
    @Test func windowPreferencesFollowLiveCoveredPresenterAndContainerDelegation() {
        let window = UIWindow()
        let presenter = WindowPolicyController()
        window.rootViewController = presenter
        let host = WindowRootHostingController(rootView: EmptyView())
        host.coveredWindow = window
        expectMatchingPolicy(host, presenter)

        let modal = WindowPolicyController()
        modal.mask = .landscape
        modal.orientation = .landscapeRight
        modal.hidden = false
        modal.style = .darkContent
        modal.animation = .fade
        modal.homeHidden = false
        modal.edges = .bottom
        modal.verticalDisabled = false
        presenter.presented = modal
        expectMatchingPolicy(host, modal)

        // Each appearance preference can be delegated independently by a container.
        let child = WindowPolicyController()
        modal.addChild(child)
        modal.preferenceChild = child
        #expect(host.supportedInterfaceOrientations == modal.supportedInterfaceOrientations)
        #expect(host.prefersStatusBarHidden == child.prefersStatusBarHidden)
        #expect(host.preferredStatusBarStyle == child.preferredStatusBarStyle)
        #expect(host.preferredStatusBarUpdateAnimation == child.preferredStatusBarUpdateAnimation)
        #expect(host.prefersHomeIndicatorAutoHidden == child.prefersHomeIndicatorAutoHidden)
        #expect(host.preferredScreenEdgesDeferringSystemGestures == child.preferredScreenEdgesDeferringSystemGestures)
        if #available(iOS 27.1, *) {
            #expect(host.preferredVerticalBarBehavior == .disabled)
            #expect(host.childForPreferredVerticalBarBehavior == nil)
            child.verticalDisabled = false
            #expect(host.preferredVerticalBarBehavior == .automatic)
            child.verticalDisabled = true
        }
        #expect(host.childForStatusBarHidden == nil)
        #expect(host.childForStatusBarStyle == nil)
        #expect(host.childForHomeIndicatorAutoHidden == nil)
        #expect(host.childForScreenEdgesDeferringSystemGestures == nil)

        // A new root and subsequent changes are read without rebuilding the host.
        window.rootViewController = child
        child.mask = .portraitUpsideDown
        expectMatchingPolicy(host, child)
    }

    @Test func coveredWindowIsWeakAndMissingSourceUsesHostingDefaults() {
        let host = WindowRootHostingController(rootView: EmptyView())
        let defaults = WindowRootHostingController(rootView: EmptyView())
        var window: UIWindow? = UIWindow()
        window?.rootViewController = WindowPolicyController()
        host.coveredWindow = window
        weak let covered = window
        window = nil
        #expect(covered == nil)
        #expect(host.coveredWindow == nil)
        expectMatchingPolicy(host, defaults)
    }

    private func expectMatchingPolicy(_ host: UIViewController, _ source: UIViewController) {
        #expect(host.supportedInterfaceOrientations == source.supportedInterfaceOrientations)
        #expect(host.preferredInterfaceOrientationForPresentation == source.preferredInterfaceOrientationForPresentation)
        #expect(host.prefersStatusBarHidden == source.prefersStatusBarHidden)
        #expect(host.preferredStatusBarStyle == source.preferredStatusBarStyle)
        #expect(host.preferredStatusBarUpdateAnimation == source.preferredStatusBarUpdateAnimation)
        #expect(host.prefersHomeIndicatorAutoHidden == source.prefersHomeIndicatorAutoHidden)
        #expect(host.preferredScreenEdgesDeferringSystemGestures == source.preferredScreenEdgesDeferringSystemGestures)
        if #available(iOS 27.1, *) {
            #expect(host.preferredVerticalBarBehavior == source.preferredVerticalBarBehavior)
        }
    }

    @Test(arguments: [false, true])
    func nativeDismissCallbackDefersWindowAndRouterTeardown(fromViewDidDisappear: Bool) async throws {
        let probe = try await DismissalProbe.make()
        defer { probe.controller?.detach() }
        let root = try #require(probe.window.rootViewController)
        let scope = try #require(probe.engine.spaces.highSpace?.root)
        let onDismiss = try #require(probe.callbacks.first)

        if fromViewDidDisappear {
            let host = WindowRootHostingController(rootView: EmptyView())
            host.onDismiss = onDismiss
            let parent = DismissingParent()
            parent.addChild(host)
            host.viewDidDisappear(false)
            host.removeFromParent()
        } else {
            // Model SwiftUI calling onDismiss while its sheet bridge holds exclusive access.
            onDismiss()
        }
        onDismiss()
        #expect(probe.window.rootViewController === root)
        #expect(!probe.window.isHidden)
        #expect(probe.engine.spaces.highSpace?.root === scope)
        #expect(scope.isAwaitingPresentationEnd)

        try #require(await waitUntil { probe.window.rootViewController == nil })
        #expect(probe.window.isHidden)
        #expect(probe.engine.spaces.highSpace == nil)
        #expect(!scope.isAwaitingPresentationEnd)
    }

    @Test(arguments: [false, true])
    func detachRetainsRemovedControllerThroughDeferredTeardown(afterNativeCallback: Bool) async throws {
        let probe = try await DismissalProbe.make()
        weak let controller = probe.controller
        let scope = try #require(probe.engine.spaces.highSpace?.root)
        if afterNativeCallback {
            let onDismiss = try #require(probe.callbacks.first)
            onDismiss()
        }
        probe.controller?.detach()
        probe.controller?.detach()
        probe.controller = nil

        #expect(controller != nil)
        #expect(probe.window.rootViewController != nil)
        #expect(scope.isAwaitingPresentationEnd)
        try #require(await waitUntil { controller == nil })
        #expect(probe.window.rootViewController == nil)
        #expect(probe.window.isHidden)
        #expect(!scope.isAwaitingPresentationEnd)
    }

    @Test func programmaticDismissalAndLateCallbacksCannotDismissSuccessor() async throws {
        let probe = try await DismissalProbe.make()
        defer { probe.controller?.detach() }
        let oldDismiss = try #require(probe.callbacks.first)
        let first = try #require(probe.engine.spaces.highSpace?.root)
        let replacement = Task { await probe.engine.present(WindowLifetimeRoute()) }
        try #require(await waitUntil { probe.engine.spaces.highSpace?.root !== first })
        probe.synchronize()
        oldDismiss()
        oldDismiss()
        #expect(probe.window.rootViewController != nil)
        #expect(first.isAwaitingPresentationEnd)

        await replacement.value
        try #require(await waitUntil { probe.window.rootViewController == nil })
        let next = try #require(probe.engine.spaces.highSpace?.root)
        #expect(next !== first)
        #expect(probe.callbacks.count == 2)
        #expect(next.isAwaitingPresentationEnd)
        oldDismiss()
        await nextMainQueueTurn()
        #expect(probe.engine.spaces.highSpace?.root === next)
        #expect(next.isAwaitingPresentationEnd)
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test(arguments: [RoutePriority.high, .critical])
    func windowAppearsImmediatelyAndSurvivesUntilNativeDismissalCompletes(priority: RoutePriority) async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            HighPriority {
                if priority == .high { testSheet(destination) }
            }
            CriticalPriority {
                if priority == .critical { testSheet(destination) }
            }
        }, router: owner) { EmptyView() }
        await owner.current.present(WindowLifetimeRoute())
        let engine = owner.engine
        let facts = WindowFacts()
        let notification = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification, object: nil, queue: nil
        ) { notification in
            guard let window = notification.object as? PassThroughWindow else { return }
            MainActor.assumeIsolated {
                facts.window = window
                facts.insertionAnimations = UIView.areAnimationsEnabled
            }
        }
        defer { NotificationCenter.default.removeObserver(notification) }

        // Substitute a controlled native renderer to test the window's completion contract.
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let coveredWindow = UIWindow(windowScene: scene)
        let presenter = WindowPolicyController()
        coveredWindow.rootViewController = presenter
        coveredWindow.makeKeyAndVisible()
        defer {
            coveredWindow.isHidden = true
            originalKeyWindow?.makeKey()
        }
        let controller = ElevatedPriorityPresentationWindowBridge<EmptyView>.Controller { _, _ in EmptyView() }
        func synchronize() {
            controller.update(priority: priority,
                desiredRoute: { engine.presentationBinding(for: .priority(priority)).wrappedValue },
                router: engine, sourceScenePhase: .active, windowDestinationBuilder: .passthrough)
        }
        synchronize()
        let window = try #require(facts.window)
        #expect(!window.isHidden)
        #expect(facts.insertionAnimations == false)
        #expect(window.rootViewController?.presentedViewController == nil)
        expectMatchingPolicy(try #require(window.rootViewController), presenter)
        defer { controller.detach() }

        let root = ProbeRoot(facts: facts)
        window.rootViewController = root
        let modal = UIViewController()
        modal.modalPresentationStyle = .custom
        let transition = HeldDismissal()
        modal.transitioningDelegate = transition
        root.present(modal, animated: false)
        try #require(await waitUntil { root.presentedViewController === modal })

        let removal = Task { await owner.dismissSpace(priority) }
        try #require(await waitUntil { engine.spaces.space(for: priority) == nil })
        synchronize()
        try #require(await waitUntil { transition.context != nil })
        #expect(engine.isNavigating)
        #expect(!window.isHidden)
        #expect(window.rootViewController === root)
        #expect(root.presentedViewController === modal)
        #expect(transition.dismissalCount == 1)
        #expect(facts.teardownAnimations == nil)

        transition.complete()
        // The UIKit completion must return before the native window is destroyed.
        #expect(window.rootViewController === root)
        #expect(!window.isHidden)
        #expect(engine.isNavigating)
        #expect(await removal.value)
        #expect(window.isHidden)
        #expect(window.rootViewController == nil)
        #expect(facts.teardownAnimations == false)
        #expect(!engine.isNavigating)
    }

    private var destination: RouteDestination<WindowLifetimeRoute> {
        testDestination(WindowLifetimeRoute.self)
    }
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }
}

@MainActor private final class DismissalProbe {
    let engine = RouterEngine(routes: RootRouteMap {
        HighPriority { Sheet(WindowLifetimeRoute.self) }
    } destinations: {
        RouteDestination(WindowLifetimeRoute.self) { _, _ in EmptyView() }
    })
    var controller: ElevatedPriorityPresentationWindowBridge<EmptyView>.Controller?
    var callbacks: [@MainActor () -> Void] = []
    private(set) var window: UIWindow!

    static func make() async throws -> DismissalProbe {
        let probe = DismissalProbe()
        await probe.engine.present(WindowLifetimeRoute())
        probe.controller = ElevatedPriorityPresentationWindowBridge<EmptyView>.Controller { [weak probe] _, onDismiss in
            probe?.callbacks.append(onDismiss)
            return EmptyView()
        }
        let notification = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification, object: nil, queue: nil
        ) { notification in
            guard let window = notification.object as? PassThroughWindow else { return }
            MainActor.assumeIsolated { probe.window = window }
        }
        defer { NotificationCenter.default.removeObserver(notification) }
        probe.synchronize()
        _ = try #require(probe.window)
        return probe
    }

    func synchronize() {
        controller?.update(priority: .high,
            desiredRoute: { [engine] in engine.presentationBinding(for: .priority(.high)).wrappedValue },
            router: engine, sourceScenePhase: .active, windowDestinationBuilder: .passthrough)
    }
}

private struct WindowLifetimeRoute: Route {}
@MainActor private final class DismissingParent: UIViewController {
    override var isBeingDismissed: Bool { true }
}
@MainActor private final class WindowFacts {
    var window: UIWindow?
    var insertionAnimations: Bool?
    var teardownAnimations: Bool?
}
@MainActor private final class ProbeRoot: UIViewController {
    let facts: WindowFacts
    init(facts: WindowFacts) { self.facts = facts; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func loadView() { view = WindowProbeView(facts: facts) }
}
@MainActor private final class WindowProbeView: UIView {
    let facts: WindowFacts
    private var hasEnteredWindow = false
    init(facts: WindowFacts) { self.facts = facts; super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { hasEnteredWindow = true }
        else if hasEnteredWindow { facts.teardownAnimations = UIView.areAnimationsEnabled }
    }
}
@MainActor private final class HeldDismissal: NSObject, UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning {
    var context: (any UIViewControllerContextTransitioning)?
    var dismissalCount = 0
    func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { self }
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval { 0.25 }
    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        dismissalCount += 1
        context = transitionContext
    }
    func complete() {
        context?.completeTransition(true)
        context = nil
    }
}
@MainActor private final class WindowPolicyController: UIViewController {
    var mask: UIInterfaceOrientationMask = .portrait
    var orientation: UIInterfaceOrientation = .portrait
    var hidden = true
    var style: UIStatusBarStyle = .lightContent
    var animation: UIStatusBarAnimation = .slide
    var homeHidden = true
    var edges: UIRectEdge = [.left, .right]
    var verticalDisabled = true
    var presented: UIViewController?
    var preferenceChild: UIViewController?

    override var presentedViewController: UIViewController? { presented ?? super.presentedViewController }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { mask }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { orientation }
    override var prefersStatusBarHidden: Bool { hidden }
    override var preferredStatusBarStyle: UIStatusBarStyle { style }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { animation }
    override var prefersHomeIndicatorAutoHidden: Bool { homeHidden }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { edges }
    override var childForStatusBarHidden: UIViewController? { preferenceChild }
    override var childForStatusBarStyle: UIViewController? { preferenceChild }
    override var childForHomeIndicatorAutoHidden: UIViewController? { preferenceChild }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { preferenceChild }
    @available(iOS 27.1, *)
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior { verticalDisabled ? .disabled : .automatic }
    @available(iOS 27.1, *)
    override var childForPreferredVerticalBarBehavior: UIViewController? { preferenceChild }
}
#endif
