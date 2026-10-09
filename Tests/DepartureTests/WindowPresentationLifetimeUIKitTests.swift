#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit
@testable import Departure

@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
struct WindowPresentationLifetimeUIKitTests {
    @Test(arguments: [RoutePriority.high, .critical])
    func windowAppearsImmediatelyAndSurvivesUntilNativeDismissalCompletes(priority: RoutePriority) async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {} highPriority: {
            if priority == .high { Sheet(destination) }
        } criticalPriority: {
            if priority == .critical { Sheet(destination) }
        }, router: owner) { EmptyView() }
        await owner.current.present(WindowLifetimeRoute())
        let engine = owner.engine
        let facts = WindowFacts()
        let notification = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification, object: nil, queue: nil
        ) { notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? PassThroughWindow else { return }
                facts.window = window
                facts.insertionAnimations = UIView.areAnimationsEnabled
            }
        }
        defer { NotificationCenter.default.removeObserver(notification) }

        // Substitute a controlled native renderer to test the window's completion contract.
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
        #expect(facts.teardownAnimations == nil)

        transition.complete()
        #expect(await removal.value)
        #expect(window.isHidden)
        #expect(window.rootViewController == nil)
        #expect(facts.teardownAnimations == false)
        #expect(!engine.isNavigating)
    }

    private var destination: RouteDestination<WindowLifetimeRoute> {
        RouteDestination(WindowLifetimeRoute.self) { _, _ in EmptyView() }
    }
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }
}

private struct WindowLifetimeRoute: Route {}
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
    func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { self }
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval { 0.25 }
    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) { context = transitionContext }
    func complete() {
        context?.completeTransition(true)
        context = nil
    }
}
#endif
