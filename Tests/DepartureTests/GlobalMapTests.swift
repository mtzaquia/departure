import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite(.timeLimit(.minutes(1)))
struct GlobalMapTests {
    private func fixture(transition: Cover.Transition = .fade) -> RootRouter {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Push(Outside.self)
            Sheet(AppModal.self) { Push(AppDetail.self) }
            GlobalMap {
                Cover(Lock.self, transition: transition) {
                    Sheet(Help.self)
                    Push(Child.self)
                }
                Sheet(SecondFactor.self)
                Cover(SecondLock.self)
            }
        } destinations: {
            RouteDestination(Outside.self) { _, _ in Text("Outside") }
            RouteDestination(AppModal.self) { _, _ in Text("App modal") }
            RouteDestination(AppDetail.self) { _, _ in Text("App detail") }
            RouteDestination(Lock.self) { _, _ in Text("Lock") }
            RouteDestination(Help.self) { _, _ in Text("Help") }
            RouteDestination(Child.self) { _, _ in Text("Child") }
            RouteDestination(SecondFactor.self) { _, _ in Text("2FA") }
            RouteDestination(SecondLock.self) { _, _ in Text("Second lock") }
        }, router: owner) { EmptyView() }
        return owner
    }

    @Test func oneMapProvidesSeveralGlobalRoutesWithoutLocalAttachments() async {
        let owner = fixture()
        #expect(owner.engine.root.routeAttachments.count == 2)
        #expect(owner.engine.root.definitions.globals?.routeAttachments.count == 3)
        await owner.root.present(SecondFactor())
        #expect(owner.engine.currentRouteScope.route is SecondFactor)
        #expect(owner.engine.currentRouteScope.routePresentation?.isGlobal == true)
    }

    @Test(arguments: Cover.Transition.allCases)
    func globalCoverStacksOverAnExistingModalAndPush(transition: Cover.Transition) async throws {
        let owner = fixture(transition: transition), engine = owner.engine
        await owner.current.present(AppModal())
        await owner.current.present(AppDetail())
        let detail = engine.currentRouteScope
        await owner.root.present(Lock())
        let lock = engine.currentRouteScope
        #expect(lock.route is Lock)
        #expect(lock.presentationOrigin === detail)
        #expect(lock.lane !== detail.lane)
        #expect(detail.belongs(to: engine.tree))
        #expect(engine.routePhase(for: lock) == .active)
        #expect(engine.routePhase(for: detail) == .inactive)
        #expect(await owner.current.unwind(.current))
        #expect(engine.currentRouteScope === detail)
    }

    @Test func coveredRootCanPresentLocalRoutesWithoutBuffering() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.root.present(Outside())
        #expect(engine.currentRouteScope.route is Outside)
        #expect(!lock.belongs(to: engine.tree))
        #expect(engine.pendingRoute == nil)
        #expect(engine.bufferedPresentationRequest == nil)
        #expect(!engine.isNavigating)
    }

    @Test func coveredSourceCanPresentGlobalOverTheForeground() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.root.present(SecondFactor())
        #expect(engine.currentRouteScope.route is SecondFactor)
        #expect(engine.currentRouteScope.presentationOrigin === lock)
        #expect(lock.belongs(to: engine.tree))
    }

    @Test(arguments: [false, true])
    func localLookupUsesTheRequestingScope(coveredSource: Bool) async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        let requester = coveredSource ? owner.root : owner.current
        await requester.present(Help())
        if coveredSource {
            #expect(engine.currentRouteScope === lock)
        } else {
            #expect(engine.currentRouteScope.route is Help)
            #expect(engine.currentRouteScope.presentationOrigin === lock)
            #expect(engine.currentRouteScope.routePresentation?.isGlobal == false)
        }
    }

    @Test func globalOverlayAllowsCrawlbackToTheApp() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.current.present(SecondFactor())
        await owner.current.present(Outside())
        #expect(engine.currentRouteScope.route is Outside)
        #expect(!lock.belongs(to: engine.tree))
    }

    @Test func localChildAllowsCrawlbackToTheApp() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.current.present(Help())
        #expect(engine.routePhase(for: lock) == .inactive)
        await owner.current.present(Outside())
        #expect(engine.currentRouteScope.route is Outside)
        #expect(!lock.belongs(to: engine.tree))
    }

    @Test func pushedChildCanResetTheTree() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.current.present(Child())
        #expect(engine.currentRouteScope.route is Child)
        #expect(engine.routePhase(for: lock) == .inactive)
        #expect(await owner.current.resetToRoot())
        #expect(engine.root.path.isEmpty)
    }

    @Test(arguments: [false, true])
    func returningToAGlobalDoesNotRestrictSubsequentNavigation(global: Bool) async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        if global { await owner.current.present(SecondFactor()) }
        else { await owner.current.present(Child()) }
        #expect(await owner.current.unwind(.current))
        #expect(engine.currentRouteScope === lock)
        #expect(engine.routePhase(for: lock) == .active)
        await owner.root.present(Outside())
        #expect(engine.currentRouteScope.route is Outside)
        #expect(!lock.belongs(to: engine.tree))
    }

    @Test func anotherGlobalCanCoverAnExistingGlobal() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let first = engine.currentRouteScope
        await owner.root.present(SecondLock())
        let second = engine.currentRouteScope
        #expect(second.route is SecondLock)
        #expect(second.presentationOrigin === first)
        #expect(first.belongs(to: engine.tree))
        #expect(engine.routePhase(for: first) == .inactive)
        #expect(engine.routePhase(for: second) == .active)
        #expect(await owner.current.unwind(.current))
        #expect(engine.currentRouteScope === first)
    }

    @Test func capturedDismissalKeepsExactInstanceIdentity() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        let dismiss = engine.unwindRouteAction(from: lock)
        #expect(await dismiss())
        #expect(engine.root.path.isEmpty)
        await owner.root.present(Lock())
        let replacement = engine.currentRouteScope
        #expect(!((await dismiss())))
        #expect(engine.currentRouteScope === replacement)
    }

    @Test(arguments: [false, true])
    func coveredSourceCanResetOrUnwindItsAncestor(reset: Bool) async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(AppModal())
        let lower = owner.current
        await owner.current.present(Lock())
        if reset { #expect(await lower.resetToRoot()) }
        else { #expect(await lower.unwind(.current)) }
        #expect(engine.root.path.isEmpty)
    }

    @Test func ancestorUnwindIncludesGlobalDescendants() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(AppModal())
        let lower = owner.current
        await owner.current.present(Lock())
        await owner.current.present(SecondFactor())
        #expect(await lower.unwind(.current))
        #expect(engine.root.path.isEmpty)
    }

    @Test func nativeAncestorWritebackReconcilesGlobalDescendants() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(AppModal())
        let binding = engine.routePresentationBinding(from: engine.root, matching: .sheet)
        await owner.current.present(Lock())
        binding.wrappedValue = nil
        #expect(engine.root.path.isEmpty)
    }

    @Test func nativeAncestorDismissalNotifiesBeforeRemovingGlobalDescendants() async throws {
        let owner = fixture(), engine = owner.engine
        var notified = false
        engine.root.installHookDeclarations(hookDeclarations: [UnwindHandler(AppModal.self) { [weak engine] in
            #expect(engine?.currentRouteScope.route is Lock)
            notified = true
        }.declaration])
        await owner.current.present(AppModal())
        let modal = engine.currentRouteScope
        await owner.current.present(Lock())

        engine.nativePresentationDidDismiss(modal)
        try await waitUntil { engine.root.path.isEmpty && !engine.isNavigating }
        #expect(notified)
    }

    @Test func equalActiveGlobalRequestRetainsTheExactInstance() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        let result = await engine.requestRouteWhenReady(Lock(), origin: RouteRequestOrigin(scope: engine.root))
        #expect(result === lock)
        #expect(engine.currentRouteScope === lock)
        #expect(engine.root.path.count == 1)
    }

    @Test func newValueForTheCurrentGlobalReplacesItsExistingSlot() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(AppModal())
        let caller = engine.currentRouteScope
        await owner.current.present(SecondFactor(challenge: 1))
        let first = engine.currentRouteScope
        await owner.current.present(SecondFactor(challenge: 2))
        #expect((engine.currentRouteScope.route as? SecondFactor)?.challenge == 2)
        #expect(engine.currentRouteScope.presentationOrigin === caller)
        #expect(!first.belongs(to: engine.tree))
        #expect(await owner.current.unwind(.current))
        #expect(engine.currentRouteScope === caller)
    }

    @Test func equalGlobalAncestorReusesTheInstanceAndRemovesDescendants() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.current.present(Help())
        await owner.current.present(Lock())
        #expect(engine.currentRouteScope === lock)
        #expect(engine.root.path.count == 1)
    }

    @Test func equalGlobalAncestorRemovesAnotherActiveGlobal() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(SecondFactor())
        let first = engine.currentRouteScope
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.current.present(SecondFactor())
        #expect(engine.currentRouteScope === first)
        #expect(engine.root.path.count == 1)
        #expect(!lock.belongs(to: engine.tree))
    }

    @Test func coveredLiveScopeCanDispatchActionsAndInvokeStoredInterceptors() async throws {
        let owner = fixture(), engine = owner.engine
        let recorder = GlobalActionRecorder()
        var captured: ActionInvocation<Void>?
        engine.root.installHookDeclarations(hookDeclarations: [ActionInterceptor(GlobalProbeAction.self) {
            captured = $0
        }.declaration])
        await owner.root.perform(GlobalProbeAction(recorder: recorder))
        let first = try #require(captured)
        await owner.root.present(Lock())
        try await first()
        #expect(recorder.calls == 1)
        captured = nil
        await owner.root.perform(GlobalProbeAction(recorder: recorder))
        let second = try #require(captured)
        try await second()
        #expect(recorder.calls == 2)
        #expect(engine.currentRouteScope.route is Lock)
    }

    @Test func removedRequestSourceCannotPresentAGlobal() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Outside())
        let captured = owner.current
        #expect(await captured.unwind(.current))
        await captured.present(SecondFactor())
        #expect(engine.root.path.isEmpty)
    }

    @Test func globalAndLocalCollisionDisablesBothDeclarations() async {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Sheet(SecondFactor.self)
            GlobalMap { Sheet(SecondFactor.self) }
        } destinations: { RouteDestination(SecondFactor.self) { _, _ in EmptyView() } }, router: owner) { EmptyView() }
        await owner.root.present(SecondFactor())
        #expect(owner.engine.root.path.isEmpty)
    }

    @Test func composedModalMapKeepsDestinationsAndGlobalMetadata() async {
        let owner = RootRouter()
        let feature = ModalRouteMap { Sheet(SecondFactor.self) } destinations: {
            RouteDestination(SecondFactor.self) { _, _ in EmptyView() }
        }
        _ = WithRouter(routes: RootRouteMap { GlobalMap { feature } }, router: owner) { EmptyView() }
        await owner.root.present(SecondFactor())
        #expect(owner.engine.currentRouteScope.routePresentation?.isGlobal == true)
    }

    @Test func globalsDoNotActivateTheRequestersInactiveBranch() async {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Branches {
                Branch("home") {}
                Branch("settings") {}
            }
            GlobalMap { Sheet(SecondFactor.self) }
        } destinations: { RouteDestination(SecondFactor.self) { _, _ in EmptyView() } }, router: owner) { EmptyView() }
        let selection = owner.engine.root.activeBranch
        await owner.root.branch("settings").present(SecondFactor())
        #expect(owner.engine.root.activeBranch == selection)
        #expect(owner.engine.currentRouteScope.route is SecondFactor)
    }

    @Test func globalRequestUsesTheVisibleBranchWhileAnOldModalAwaitsReconciliation() async {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Branches {
                Branch("home") { Sheet(AppModal.self) }
                Branch("settings") {}
            }
            GlobalMap { Sheet(SecondFactor.self) }
        } destinations: {
            RouteDestination(AppModal.self) { _, _ in EmptyView() }
            RouteDestination(SecondFactor.self) { _, _ in EmptyView() }
        }, router: owner) { EmptyView() }
        await owner.root.branch("home").present(AppModal())
        let outgoing = owner.engine.currentRouteScope
        #expect(owner.engine.activateBranch("settings", in: owner.engine.root))
        let settings = owner.engine.root.branchScopes["settings"]!
        #expect(owner.engine.currentRouteScope === settings)
        await owner.root.present(SecondFactor())
        #expect(owner.engine.currentRouteScope.presentationOrigin === settings)
        #expect(!outgoing.belongs(to: owner.engine.tree))
        #expect(owner.engine.root.activeBranch == AnyHashable("settings"))
    }

    @Test func suspendedResolutionNavigatesAfterReturningToAnActiveGlobal() async throws {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.current.present(Help())
        let gate = GlobalResolutionGate()
        let request = Task { await owner.root.present(SuspendedOutside(gate: gate)) }
        try await waitUntil { gate.continuation != nil }
        #expect(await owner.current.unwind(.current))
        #expect(engine.currentRouteScope === lock)
        gate.release()
        await request.value
        #expect(engine.currentRouteScope.route is Outside)
        #expect(!lock.belongs(to: engine.tree))
        #expect(engine.pendingRoute == nil)
    }

    @Test func suspendedRootResolutionSurvivesExplicitGlobalDismissal() async throws {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let gate = GlobalResolutionGate()
        let request = Task { await owner.root.present(SuspendedOutside(gate: gate)) }
        try await waitUntil { gate.continuation != nil }
        #expect(await owner.current.unwind(.current))
        gate.release()
        await request.value
        #expect(engine.currentRouteScope.route is Outside)
    }

    @Test func nativeLifetimeReconcilesAncestorDismissalWithGlobalDescendants() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(AppModal())
        let modal = engine.currentRouteScope
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: modal))
        lifetime.didAdmitPresentation(of: ObjectIdentifier(modal))
        await owner.current.present(Lock())
        lifetime.requestDismissal(of: ObjectIdentifier(modal), in: engine)
        #expect(!lifetime.isPresented)
        #expect(engine.root.path.isEmpty)
        lifetime.completeDismissal(of: ObjectIdentifier(modal), in: engine)
    }

    @Test func coveredBranchRequestCanActivateItsTargetAndPresentAnotherGlobal() async {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Branches {
                Branch("home") {}
                Branch("settings") { Push(Outside.self) }
            }
            GlobalMap { Cover(Lock.self); Sheet(SecondFactor.self) }
        } destinations: {
            RouteDestination(Outside.self) { _, _ in EmptyView() }
            RouteDestination(Lock.self) { _, _ in EmptyView() }
            RouteDestination(SecondFactor.self) { _, _ in EmptyView() }
        }, router: owner) { EmptyView() }
        await owner.root.present(Lock())
        let lock = owner.engine.currentRouteScope
        await owner.root.branch("settings").present(Outside())
        #expect(owner.engine.root.activeBranch == AnyHashable("settings"))
        #expect(owner.engine.currentRouteScope.route is Outside)
        #expect(owner.engine.routePhase(for: lock) == .inactive)
        // Ordinary branch selection retains the old branch's path. The next
        // modal request reconciles the shared lane before presenting over Settings.
        let detail = owner.engine.currentRouteScope
        await owner.root.present(SecondFactor())
        #expect(owner.engine.currentRouteScope.presentationOrigin === detail)
        #expect(!lock.belongs(to: owner.engine.tree))
    }

    @Test(arguments: [false, true])
    func declaredChildrenOfAGlobalRemainAvailableInsideABranch(push: Bool) async {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Branches {
                Branch("home") {}
                Branch("settings") {}
            }
            GlobalMap {
                Cover(Lock.self) { Sheet(Help.self); Push(Child.self) }
            }
        } destinations: {
            RouteDestination(Lock.self) { _, _ in EmptyView() }
            RouteDestination(Help.self) { _, _ in EmptyView() }
            RouteDestination(Child.self) { _, _ in EmptyView() }
        }, router: owner) { EmptyView() }
        await owner.root.present(Lock())
        let lock = owner.engine.currentRouteScope
        if push { await owner.current.present(Child()) }
        else { await owner.current.present(Help()) }
        #expect(owner.engine.root.activeBranch == AnyHashable("home"))
        #expect(owner.engine.currentRouteScope !== lock)
        #expect(lock.belongs(to: owner.engine.tree))
        #expect(owner.engine.routePhase(for: lock) == .inactive)
    }

    @Test func aGlobalOwningBranchesCanBeRemovedThroughOrdinaryNavigation() async {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Push(Outside.self)
            GlobalMap {
                Cover(Lock.self) {
                    Branches(concurrent: true) {
                        Branch("leading") {}
                        Branch("trailing") {}
                    }
                }
            }
        } destinations: {
            RouteDestination(Outside.self) { _, _ in EmptyView() }
            RouteDestination(Lock.self) { _, _ in EmptyView() }
        }, router: owner) { EmptyView() }
        await owner.root.present(Lock())
        let lock = owner.engine.root.path.last!
        #expect(owner.engine.routePhase(for: lock) == .inactive)
        #expect(lock.branchScopes.values.allSatisfy { owner.engine.routePhase(for: $0) == .active })
        await owner.root.present(Outside())
        #expect(!lock.belongs(to: owner.engine.tree))
    }

    #if DEBUG
    @Test func adoptedMapTraceShowsGlobalsWithoutBuildingViews() {
        var builds = 0
        let engine = RouterEngine(routes: RootRouteMap {
            GlobalMap { Cover(Lock.self) }
        } destinations: {
            RouteDestination(Lock.self) { _, _ in builds += 1; return EmptyView() }
        })
        #expect(engine.root.definitions.departureMapTrace.contains("global"))
        #expect(builds == 0)
    }

    #endif

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(condition())
    }
}

private struct Lock: Route, Equatable {}
private struct SecondLock: Route, Equatable {}
private struct SecondFactor: Route, Equatable { var challenge = 0 }
private struct Help: Route, Equatable {}
private struct Child: Route, Equatable {}
private struct Outside: Route, Equatable {}
private struct AppModal: Route, Equatable {}
private struct AppDetail: Route, Equatable {}

@MainActor private final class GlobalActionRecorder { var calls = 0 }

private struct GlobalProbeAction: Action {
    let recorder: GlobalActionRecorder
    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        recorder.calls += 1
    }
}

@MainActor private final class GlobalResolutionGate {
    var continuation: CheckedContinuation<Void, Never>?
    func pause() async { await withCheckedContinuation { continuation = $0 } }
    func release() { let pending = continuation; continuation = nil; pending?.resume() }
}

private struct SuspendedOutside: Route {
    let gate: GlobalResolutionGate
    func resolveRoute() async -> RouteResolution {
        await gate.pause()
        return .reroute(Outside())
    }
}
