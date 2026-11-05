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
                }.dismissalProtection()
                Sheet(SecondFactor.self)
                Cover(SecondLock.self).dismissalProtection()
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
        #expect(owner.engine.currentRouteScope.routePresentation?.isDismissalProtected == false)
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

    @Test func activeProtectionRejectsUnrelatedPresentationWithoutBuffering() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.root.present(Outside())
        #expect(engine.currentRouteScope === lock)
        #expect(engine.pendingRoute == nil)
        #expect(engine.bufferedPresentationRequest == nil)
        #expect(!engine.isNavigating)
    }

    @Test func coveredSourceCanPresentGlobalWithoutRemovingTheLock() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.root.present(SecondFactor())
        #expect(engine.currentRouteScope.route is SecondFactor)
        #expect(engine.currentRouteScope.presentationOrigin === lock)
        #expect(lock.belongs(to: engine.tree))
        #expect(engine.protectedScopes.isEmpty)
    }

    @Test(arguments: [false, true])
    func localDeclarationExceptionUsesTheProtectedForeground(coveredSource: Bool) async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        let requester = coveredSource ? owner.root : owner.current
        await requester.present(Help())
        #expect(engine.currentRouteScope.route is Help)
        #expect(engine.currentRouteScope.presentationOrigin === lock)
        #expect(engine.currentRouteScope.routePresentation?.isGlobal == false)
        #expect(engine.protectedScopes.isEmpty)
    }

    @Test func unprotectedGlobalAllowsCrawlbackToRemoveInactiveLock() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.current.present(SecondFactor())
        await owner.current.present(Outside())
        #expect(engine.currentRouteScope.route is Outside)
        #expect(!lock.belongs(to: engine.tree))
    }

    @Test func unprotectedDeclaredChildAllowsCrawlbackToRemoveInactiveLock() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.current.present(Help())
        #expect(engine.routePhase(for: lock) == .inactive)
        await owner.current.present(Outside())
        #expect(engine.currentRouteScope.route is Outside)
        #expect(!lock.belongs(to: engine.tree))
    }

    @Test func pushedChildDoesNotInheritItsParentsProtection() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.current.present(Child())
        #expect(engine.currentRouteScope.route is Child)
        #expect(engine.routePhase(for: lock) == .inactive)
        #expect(engine.protectedScopes.isEmpty)
        #expect(await owner.current.resetToRoot())
        #expect(engine.root.path.isEmpty)
    }

    @Test(arguments: [false, true])
    func protectionResumesWhenTheSameInstanceBecomesActive(global: Bool) async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        if global { await owner.current.present(SecondFactor()) }
        else { await owner.current.present(Child()) }
        #expect(engine.protectedScopes.isEmpty)
        #expect(await owner.current.unwind(.current))
        #expect(engine.currentRouteScope === lock)
        #expect(engine.protectedScopes.first === lock)
        await owner.root.present(Outside())
        #expect(engine.currentRouteScope === lock)
    }

    @Test func anotherProtectedGlobalIsAdmittedAndBecomesTheOnlyProtection() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let first = engine.currentRouteScope
        await owner.root.present(SecondLock())
        let second = engine.currentRouteScope
        #expect(second.route is SecondLock)
        #expect(first.belongs(to: engine.tree))
        #expect(engine.protectedScopes.count == 1)
        #expect(engine.protectedScopes.first === second)
        #expect(await owner.current.unwind(.current))
        #expect(engine.protectedScopes.first === first)
    }

    @Test func explicitCapturedDismissalClosesTheActiveProtectedInstance() async {
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

    @Test func resetAndAncestorUnwindCannotRemoveActiveProtection() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(AppModal())
        let modal = engine.currentRouteScope
        let lower = owner.current
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        #expect(!((await owner.root.resetToRoot())))
        #expect(!((await owner.current.resetToRoot())))
        #expect(!((await lower.unwind(.current))))
        #expect(!((await owner.current.unwind(from: AppModal.self))))
        #expect(engine.currentRouteScope === lock)
        #expect(modal.belongs(to: engine.tree))
    }

    @Test func inactiveProtectionDoesNotPreventAncestorUnwind() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(AppModal())
        let lower = owner.current
        await owner.current.present(Lock())
        await owner.current.present(SecondFactor())
        #expect(await lower.unwind(.current))
        #expect(engine.root.path.isEmpty)
    }

    @Test func nativeAncestorWritebackCannotRemoveAnActiveProtectedDescendant() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(AppModal())
        let binding = engine.routePresentationBinding(from: engine.root, matching: .sheet)
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        binding.wrappedValue = nil
        #expect(engine.currentRouteScope === lock)
        #expect(engine.protectsNativePresentation(engine.root.path.first!))
        await owner.current.present(SecondFactor())
        #expect(!engine.protectsNativePresentation(lock))
        binding.wrappedValue = nil
        #expect(engine.root.path.isEmpty)
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

    @Test func equalGlobalAncestorReusesTheInstanceAndRemovesUnprotectedDescendants() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.current.present(Help())
        await owner.current.present(Lock())
        #expect(engine.currentRouteScope === lock)
        #expect(engine.root.path.count == 1)
        #expect(engine.protectedScopes.first === lock)
    }

    @Test func equalGlobalAncestorCannotRemoveAnActiveProtectedDescendant() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(SecondFactor())
        let first = engine.currentRouteScope
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        await owner.current.present(SecondFactor())
        #expect(engine.currentRouteScope.route is SecondFactor)
        #expect(engine.currentRouteScope !== first)
        #expect(engine.currentRouteScope.presentationOrigin === lock)
        #expect(first.belongs(to: engine.tree))
        #expect(lock.belongs(to: engine.tree))
    }

    @Test func removedRequestSourceCannotPresentAGlobal() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(Outside())
        let captured = owner.current
        #expect(await captured.unwind(.current))
        await captured.present(SecondFactor())
        #expect(engine.root.path.isEmpty)
    }

    @Test func modifierIsIdempotentAndDoesNotProtectChildDeclarations() {
        let declaration = Cover(Lock.self) { Sheet(Help.self) }.dismissalProtection().dismissalProtection()
        #expect(declaration.declaration.isDismissalProtected)
        #expect(!declaration.declaration.children.flatMap(\.routes)[0].isDismissalProtected)
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

    @Test func localProtectedModalUsesTheSameActivePhaseRule() async {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Sheet(Lock.self) { Sheet(Help.self) }.dismissalProtection()
            Push(Outside.self)
        } destinations: {
            RouteDestination(Lock.self) { _, _ in EmptyView() }
            RouteDestination(Help.self) { _, _ in EmptyView() }
            RouteDestination(Outside.self) { _, _ in EmptyView() }
        }, router: owner) { EmptyView() }
        await owner.current.present(Lock())
        let lock = owner.engine.currentRouteScope
        await owner.root.present(Outside())
        #expect(owner.engine.currentRouteScope === lock)
        await owner.current.present(Help())
        await owner.current.present(Outside())
        #expect(!lock.belongs(to: owner.engine.tree))
    }

    @Test func suspendedResolutionRechecksProtectionWhenItResumes() async throws {
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
        #expect(engine.currentRouteScope === lock)
        #expect(engine.pendingRoute == nil)
    }

    @Test func suspendedResolutionDoesNotRetainProtectionAfterExplicitDismissal() async throws {
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

    @Test func nativeLifetimeRejectsAncestorDismissalBeforeChangingRenderedState() async {
        let owner = fixture(), engine = owner.engine
        await owner.current.present(AppModal())
        let modal = engine.currentRouteScope
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: modal)) { .init(route: $0) }
        lifetime.didAdmitPresentation(of: ObjectIdentifier(modal))
        await owner.current.present(Lock())
        let lock = engine.currentRouteScope
        lifetime.requestDismissal(of: ObjectIdentifier(modal), in: engine)
        #expect(lifetime.isPresented)
        #expect(engine.currentRouteScope === lock)
        #expect(await owner.current.unwind(.current))
        lifetime.requestDismissal(of: ObjectIdentifier(modal), in: engine)
        #expect(!lifetime.isPresented)
        lifetime.completeDismissal(of: ObjectIdentifier(modal), in: engine)
    }

    @Test func rejectedBranchRequestCannotDeactivateTheProtectedRoute() async {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Branches {
                Branch("home") {}
                Branch("settings") { Push(Outside.self) }
            }
            GlobalMap { Cover(Lock.self).dismissalProtection() }
        } destinations: {
            RouteDestination(Outside.self) { _, _ in EmptyView() }
            RouteDestination(Lock.self) { _, _ in EmptyView() }
        }, router: owner) { EmptyView() }
        await owner.root.present(Lock())
        let lock = owner.engine.currentRouteScope
        await owner.root.branch("settings").present(Outside())
        #expect(owner.engine.root.activeBranch == AnyHashable("home"))
        #expect(owner.engine.currentRouteScope === lock)
    }

    @Test(arguments: [false, true])
    func declaredChildrenOfAProtectedGlobalRemainAvailableInsideABranch(push: Bool) async {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Branches {
                Branch("home") {}
                Branch("settings") {}
            }
            GlobalMap {
                Cover(Lock.self) { Sheet(Help.self); Push(Child.self) }.dismissalProtection()
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

    @Test func aGlobalOwningBranchesDoesNotProtectItsInactiveRoot() async {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Push(Outside.self)
            GlobalMap {
                Cover(Lock.self) {
                    Branches(concurrent: true) {
                        Branch("leading") {}
                        Branch("trailing") {}
                    }
                }.dismissalProtection()
            }
        } destinations: {
            RouteDestination(Outside.self) { _, _ in EmptyView() }
            RouteDestination(Lock.self) { _, _ in EmptyView() }
        }, router: owner) { EmptyView() }
        await owner.root.present(Lock())
        let lock = owner.engine.root.path.last!
        #expect(owner.engine.routePhase(for: lock) == .inactive)
        #expect(lock.branchScopes.values.allSatisfy { owner.engine.routePhase(for: $0) == .active })
        #expect(owner.engine.protectedScopes.isEmpty)
        await owner.root.present(Outside())
        #expect(!lock.belongs(to: owner.engine.tree))
    }

    #if DEBUG
    @Test func adoptedMapTraceShowsGlobalsAndProtectionWithoutBuildingViews() {
        var builds = 0
        let engine = RouterEngine(routes: RootRouteMap {
            GlobalMap { Cover(Lock.self).dismissalProtection() }
        } destinations: {
            RouteDestination(Lock.self) { _, _ in builds += 1; return EmptyView() }
        })
        #expect(engine.root.definitions.departureMapTrace.contains("global"))
        #expect(engine.root.definitions.departureMapTrace.contains("[dismissal protection]"))
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
