import Observation
import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ScopedRouterTests {
    @Test func environmentDefaultIsInactiveAndStable() async {
        let environment = EnvironmentValues()
        #expect(environment.router == EnvironmentValues().router)
        await environment.router.present(SettingsRoute())
        #expect(await environment.router.unwind(to: .root) == false)
    }

    @Test func localPresentationDoesNotUseAnotherBranchsDeeperDeclaration() async throws {
        let fixture = Fixture(concurrent: true)
        let deeper = RouteScope(id: "deeper", route: NumberedRoute(number: 1))
        deeper.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
        ])
        fixture.engine.mutateRouteGraph { fixture.detail.path.append(deeper) }
        fixture.content.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
        ])
        await fixture.local(fixture.content).present(SettingsRoute())
        let selected = try #require(fixture.content.path.last)
        #expect(selected.presentationDeclaration?.presentationKind == .push)
        #expect(fixture.detail.path.last === deeper)
        #expect(fixture.selection.value == "content")
    }

    @Test func explicitTargetRevealsInactiveBranchAndPreservesSiblings() async {
        let fixture = Fixture(concurrent: true)
        let sibling = RouteScope(id: "sibling", route: NumberedRoute(number: 1))
        fixture.engine.mutateRouteGraph { fixture.content.path.append(sibling) }
        let target = fixture.root.branch("detail")
        #expect(fixture.selection.value == "sidebar")
        await target.present(SettingsRoute())
        #expect(fixture.selection.value == "detail")
        #expect(fixture.detail.path.last?.route is SettingsRoute)
        #expect(fixture.content.path.last === sibling)
        #expect(fixture.engine.normalTree.activeBranchPaths().count == 3)
    }

    @Test func exclusiveTargetSelectsOnlyOneParticipatingBranch() async {
        let fixture = Fixture(concurrent: false)
        await fixture.root.branch("detail").present(SettingsRoute())
        #expect(fixture.selection.value == "detail")
        #expect(fixture.engine.normalTree.activeBranchPaths().count == 1)
        #expect(fixture.engine.routePhase(for: fixture.sidebar) == .inactive)
    }

    @Test func exclusiveTargetModalWaitsForActivatedHost() async {
        let fixture = Fixture(concurrent: false)
        await fixture.root.branch("detail").present(MessageRoute())
        #expect(fixture.selection.value == "detail")
        #expect(fixture.detail.path.isEmpty)
        #expect(fixture.engine.pendingRoute?.append?.match.branchID == AnyHashable("detail"))
        fixture.engine.resumePendingRoute(for: "detail", in: fixture.engine.root)
        #expect(fixture.detail.path.last?.route is MessageRoute)
        #expect(fixture.engine.pendingRoute == nil)
    }

    @Test func equalDestinationStillRevealsTargetedBranch() async {
        let fixture = Fixture(concurrent: true)
        await fixture.root.branch("detail").present(HomeDetailRoute())
        fixture.selection.value = "sidebar"
        await fixture.root.branch("detail").present(HomeDetailRoute())
        #expect(fixture.selection.value == "detail")
        #expect(fixture.detail.path.count == 1)
    }

    @Test func rejectedAndMissingRoutesDoNotRevealTarget() async {
        let fixture = Fixture(concurrent: true)
        await fixture.root.branch("detail").present(DroppedRoute())
        await fixture.root.branch("missing").present(SettingsRoute())
        await fixture.root.branch("detail").present(NonEquatableRoute(value: 1))
        #expect(fixture.selection.value == "sidebar")
        #expect(fixture.detail.path.isEmpty)
        #expect(fixture.engine.pendingRoute == nil)
    }

    @Test(arguments: [true, false], [true, false])
    func plainPresentationDiscoversAndSelectsSibling(concurrent: Bool, fromRoot: Bool) async {
        let fixture = Fixture(concurrent: concurrent)
        let router = fromRoot ? fixture.root : fixture.local(fixture.sidebar)
        await router.present(SettingsRoute())
        #expect(fixture.selection.value == "detail")
        fixture.engine.resumePendingRoute(for: "detail", in: fixture.engine.root)
        #expect(fixture.detail.path.last?.route is SettingsRoute)
        #expect(fixture.sidebar.path.isEmpty)
        #expect(fixture.engine.pendingRoute == nil)
    }

    @Test func enclosingLocalDeclarationWinsBeforeSiblingDiscovery() async {
        let fixture = Fixture(concurrent: true)
        fixture.sidebar.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
        ])
        let pushed = RouteScope(id: "pushed", route: NumberedRoute(number: 1))
        fixture.engine.mutateRouteGraph { fixture.sidebar.path.append(pushed) }
        await fixture.local(pushed).present(SettingsRoute())
        #expect(fixture.selection.value == "sidebar")
        #expect(fixture.sidebar.path.last?.presentationDeclaration?.presentationKind == .sheet)
        #expect(fixture.detail.path.isEmpty)
    }

    @Test(arguments: [true, false], [true, false])
    func explicitTargetDoesNotFallBackToSibling(concurrent: Bool, mounted: Bool) async {
        let fixture = Fixture(concurrent: concurrent)
        if !mounted {
            fixture.engine.mutateRouteGraph {
                fixture.engine.root.unregisterBranchScope(fixture.content, for: "content")
            }
        }
        // SettingsRoute is declared only in detail, not the explicitly targeted content branch.
        await fixture.root.branch("content").present(SettingsRoute())
        #expect(fixture.selection.value == "sidebar")
        #expect(fixture.content.path.isEmpty)
        #expect(fixture.detail.path.isEmpty)
        #expect(fixture.engine.normalTree.rootPath.isEmpty)
        #expect(fixture.engine.pendingRoute == nil)
    }

    @Test func localLookupDoesNotSearchSiblingDestinationScopes() async {
        let fixture = Fixture(concurrent: true)
        let pushed = RouteScope(id: "sibling-destination", route: NumberedRoute(number: 1))
        pushed.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(NonEquatableRoute.self)._routeDeclarations),
        ])
        fixture.engine.mutateRouteGraph { fixture.detail.path.append(pushed) }
        await fixture.local(fixture.sidebar).present(NonEquatableRoute(value: 1))
        #expect(fixture.selection.value == "sidebar")
        #expect(fixture.detail.path.last === pushed)
        #expect(fixture.sidebar.path.isEmpty)
    }

    @Test(arguments: [true, false])
    func ancestorRerouteDoesNotRevealOriginalTarget(mounted: Bool) async {
        let router = Router()
        let engine = router.engine!
        @Bindable var selection = PaneSelection()
        engine.root.installRouteDeclarations(id: nil,
            branchSelection: AnyRouteBranchSelection($selection.value, concurrent: true),
            routeDeclarations: [RouteScopeDeclaration(routes: Cover(ScopedLoginRoute.self)._routeDeclarations)]
                + Branch("sidebar") { Push(NumberedRoute.self) }.routeScopeDeclarations
                + Branch("detail") { Push(ScopedGuardedRoute.self) }.routeScopeDeclarations)
        let sidebar = RouteScope(id: "sidebar", route: nil)
        let detail = RouteScope(id: "detail", route: nil)
        engine.mutateRouteGraph {
            engine.root.registerBranchScope(sidebar, for: "sidebar")
            if mounted { engine.root.registerBranchScope(detail, for: "detail") }
        }
        await router.branch("detail").present(ScopedGuardedRoute())
        #expect(selection.value == "sidebar")
        #expect(engine.currentRouteScope.route is ScopedLoginRoute)
        #expect(detail.path.isEmpty)
        #expect(engine.pendingRoute == nil)
    }

    @Test func targetedCoverKeepsOtherBranchPushPaths() async {
        let fixture = Fixture(concurrent: true)
        let sibling = RouteScope(id: "sibling", route: NumberedRoute(number: 1))
        fixture.engine.mutateRouteGraph { fixture.content.path.append(sibling) }
        await fixture.root.branch("detail").present(MessageRoute())
        #expect(fixture.engine.routePresentation(from: fixture.detail, matching: .cover(.slide)) != nil)
        #expect(fixture.content.path.last === sibling)
        #expect(fixture.engine.routePhase(for: fixture.content) == .inactive)
    }

    @Test func concurrentBranchesShareModalArbitration() async {
        let fixture = Fixture(concurrent: true)
        await fixture.root.branch("content").present(LoginRoute())
        await fixture.root.branch("detail").present(MessageRoute())
        #expect(fixture.content.path.isEmpty)
        #expect(fixture.detail.path.last?.route is MessageRoute)
    }

    @Test func branchDeclaredCoverFromPushedScopeKeepsBranchHostAndPush() async throws {
        let fixture = Fixture(concurrent: true)
        await fixture.root.branch("detail").present(SettingsRoute())
        let destination = try #require(fixture.detail.path.last)
        await fixture.local(destination).present(MessageRoute())
        #expect(fixture.detail.path.scopes.first === destination)
        #expect(fixture.detail.path.last?.route is MessageRoute)
        #expect(fixture.engine.routePresentation(from: fixture.detail, matching: .cover(.slide)) != nil)
        #expect(fixture.engine.pendingRoute == nil)
    }

    @Test func unwindNearestBranchIsLocalAndRootIsContainerWide() async {
        let fixture = Fixture(concurrent: true)
        await fixture.root.branch("detail").present(SettingsRoute())
        await fixture.root.branch("content").present(HomeDetailRoute())
        #expect(await fixture.root.branch("detail").unwind(to: .nearestBranch))
        #expect(fixture.detail.path.isEmpty)
        #expect(fixture.content.path.count == 1)
        #expect(await fixture.root.unwind(to: .root))
        #expect(fixture.content.path.isEmpty)
    }

    @Test func capturedDismissalRemovesItsScopeAndLeavesSiblingAlone() async throws {
        let fixture = Fixture(concurrent: true)
        await fixture.root.branch("detail").present(SettingsRoute())
        let destination = try #require(fixture.detail.path.last)
        let dismissal = UnwindRouteAction(router: fixture.engine, routeScope: destination)
        await fixture.root.branch("content").present(HomeDetailRoute())
        #expect(await dismissal())
        #expect(fixture.detail.path.isEmpty)
        #expect(fixture.content.path.count == 1)
    }

    @Test func removedScopeHandleCannotRedirectToAnotherBranch() async throws {
        let fixture = Fixture(concurrent: true)
        await fixture.root.branch("detail").present(SettingsRoute())
        let removed = try #require(fixture.detail.path.last)
        let stored = fixture.local(removed)
        #expect(await fixture.root.branch("detail").unwind(to: .nearestBranch))
        await stored.present(HomeDetailRoute())
        #expect(await stored.unwind(to: .root) == false)
        #expect(fixture.content.path.isEmpty)
        #expect(fixture.detail.path.isEmpty)
    }

    @Test func removedBranchContainerDoesNotRedirectStoredTargetToAncestor() async {
        let fixture = Fixture(concurrent: true)
        fixture.detail.installRouteDeclarations(sourceID: "inner", id: nil, branchSelection: nil,
            routeDeclarations: Branch("content") { Push(SettingsRoute.self) }.routeScopeDeclarations)
        let stored = fixture.local(fixture.detail).branch("content")
        fixture.engine.mutateRouteGraph { fixture.detail.uninstallRouteDeclarations(sourceID: "inner") }
        await stored.present(HomeDetailRoute())
        #expect(await stored.unwind(to: .root) == false)
        #expect(fixture.selection.value == "sidebar")
        #expect(fixture.content.path.isEmpty)
        #expect(fixture.engine.pendingRoute == nil)
    }

    @Test(arguments: [true, false], [true, false])
    func lazyTargetActivatesBeforeHostRegistrationThenResumesLocally(concurrent: Bool, explicit: Bool) async {
        let fixture = Fixture(concurrent: concurrent)
        fixture.engine.mutateRouteGraph {
            fixture.engine.root.unregisterBranchScope(fixture.detail, for: "detail")
        }
        let router = explicit ? fixture.root.branch("detail") : fixture.local(fixture.sidebar)
        await router.present(SettingsRoute())
        #expect(fixture.selection.value == "detail")
        #expect(fixture.engine.pendingRoute != nil)
        #expect(fixture.engine.normalTree.rootPath.isEmpty)
        fixture.engine.mutateRouteGraph {
            fixture.engine.root.registerBranchScope(fixture.detail, for: "detail")
        }
        fixture.engine.resumePendingRoute(for: "detail", in: fixture.engine.root)
        #expect(fixture.engine.pendingRoute == nil)
        #expect(fixture.detail.path.last?.route is SettingsRoute)
    }

    @Test func nestedTargetActivatesEnclosingExclusiveBranches() async {
        let fixture = Fixture(concurrent: false)
        let nested = RouteScope(id: "nested", route: nil)
        fixture.detail.installRouteDeclarations(id: nil, branchSelection: nil,
            routeDeclarations: Branch("nested") { Push(SettingsRoute.self) }.routeScopeDeclarations)
        fixture.engine.mutateRouteGraph { fixture.detail.registerBranchScope(nested, for: "nested") }
        await fixture.root.branch("detail").branch("nested").present(SettingsRoute())
        #expect(fixture.selection.value == "detail")
        #expect(fixture.detail.activeBranch == AnyHashable("nested"))
        fixture.engine.resumePendingRoute(for: "nested", in: fixture.detail)
        #expect(nested.path.last?.route is SettingsRoute)
        await fixture.root.branch("detail").branch("nested").present(SettingsRoute())
        #expect(nested.path.count == 1)
    }

    @Test func concurrentRoutePhasesRemainLocalWhenForegroundChanges() async {
        let fixture = Fixture(concurrent: true)
        #expect(fixture.engine.routePhase(for: fixture.sidebar) == .active)
        #expect(fixture.engine.routePhase(for: fixture.content) == .active)
        #expect(fixture.engine.routePhase(for: fixture.detail) == .active)
        await fixture.root.branch("detail").present(SettingsRoute())
        #expect(fixture.engine.routePhase(for: fixture.sidebar) == .active)
        #expect(fixture.engine.routePhase(for: fixture.detail) == .inactive)
        #expect(fixture.engine.routePhase(for: fixture.detail.path.last!) == .active)
    }

    @Test func actionInterceptionUsesOriginatingScope() async {
        let fixture = Fixture(concurrent: true)
        let recorder = ActionRecorder()
        fixture.content.installHookDeclarations(hookDeclarations: [
            ActionInterceptor(ContextProbeAction.self) { invocation in
                recorder.labels.append("content")
                _ = try? await invocation()
            }.declaration,
        ])
        fixture.detail.installHookDeclarations(hookDeclarations: [
            ActionInterceptor(ContextProbeAction.self) { _ in recorder.labels.append("detail") }.declaration,
        ])
        fixture.selection.value = "detail"
        await fixture.local(fixture.content).perform(ContextProbeAction())
        #expect(recorder.labels == ["content"])
        #expect(fixture.selection.value == "detail")
    }

    @Test func scopedRequestRetainsOriginAcrossNavigationReadiness() async {
        let fixture = Fixture(concurrent: true)
        let transaction = fixture.engine.beginNavigationTransaction()
        let request = Task { await fixture.local(fixture.content).present(HomeDetailRoute()) }
        for _ in 0..<100 where fixture.engine.pendingRoute == nil { await Task.yield() }
        #expect(fixture.engine.pendingRoute != nil)
        fixture.selection.value = "detail"
        await fixture.engine.finishNavigationTransaction(transaction)
        await request.value
        #expect(fixture.content.path.last?.route is HomeDetailRoute)
        #expect(fixture.detail.path.isEmpty)
    }

    @Test func branchHandleOutlivesItsRequestingDestination() async throws {
        let fixture = Fixture(concurrent: true)
        await fixture.root.branch("detail").present(SettingsRoute())
        let destination = try #require(fixture.detail.path.last)
        let content = fixture.local(destination).branch("content")
        #expect(await UnwindRouteAction(router: fixture.engine, routeScope: destination)())
        await content.present(HomeDetailRoute())
        #expect(fixture.content.path.last?.route is HomeDetailRoute)
        #expect(fixture.detail.path.isEmpty)
    }

    @Test func localAncestorUnwindDismissesCapturedScopeRatherThanDeepestChild() async throws {
        let fixture = Fixture(concurrent: true)
        await fixture.root.branch("detail").present(SettingsRoute())
        let destination = try #require(fixture.detail.path.last)
        destination.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(NumberedRoute.self)._routeDeclarations),
        ])
        let local = fixture.local(destination)
        await local.present(NumberedRoute(number: 2))
        #expect(fixture.detail.path.count == 2)
        #expect(await local.unwind(to: .topmostAncestor))
        #expect(fixture.detail.path.isEmpty)
    }

    @Test func delayedResolutionKeepsOriginWhenForegroundChanges() async {
        let fixture = Fixture(concurrent: true)
        let gate = ScopedResolutionGate()
        fixture.content.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(ScopedDelayedRoute.self)._routeDeclarations),
        ])
        let request = Task { await fixture.local(fixture.content).present(ScopedDelayedRoute(gate: gate)) }
        await gate.waitForStart()
        fixture.selection.value = "detail"
        await gate.release()
        await request.value
        #expect(fixture.content.path.last?.route is ScopedDelayedRoute)
        #expect(fixture.detail.path.isEmpty)
        #expect(fixture.selection.value == "content")
        #expect(await gate.count == 1)
    }

    @Test func delayedResolutionDropsWhenItsOriginLeavesTheGraph() async throws {
        let fixture = Fixture(concurrent: true)
        await fixture.root.branch("detail").present(SettingsRoute())
        let destination = try #require(fixture.detail.path.last)
        let gate = ScopedResolutionGate()
        destination.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(ScopedDelayedRoute.self)._routeDeclarations),
        ])
        let request = Task { await fixture.local(destination).present(ScopedDelayedRoute(gate: gate)) }
        await gate.waitForStart()
        #expect(await fixture.root.branch("detail").unwind(to: .nearestBranch))
        await gate.release()
        await request.value
        #expect(fixture.detail.path.isEmpty)
        #expect(fixture.engine.pendingRoute == nil)
    }

    @Test func detachedModalRouterFindsItsDeclaringAncestor() async throws {
        let fixture = Fixture(concurrent: true)
        fixture.engine.root.installRouteDeclarations(id: nil,
            branchSelection: AnyRouteBranchSelection(Binding.constant("sidebar"), concurrent: true),
            routeDeclarations: [RouteScopeDeclaration(routes: Cover(LockRoute.self, priority: .high)._routeDeclarations)])
        await fixture.root.present(LockRoute())
        let modal = try #require(fixture.engine.currentRouteScope.route is LockRoute ? fixture.engine.currentRouteScope : nil)
        fixture.engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Cover(LockRoute.self, priority: .high)._routeDeclarations),
            RouteScopeDeclaration(routes: Cover(ChallengeRoute.self, priority: .high)._routeDeclarations),
        ])
        await fixture.local(modal).present(ChallengeRoute())
        #expect(fixture.engine.currentRouteScope.route is ChallengeRoute)
    }

    @Test func concurrentBranchesInsideAModalRemainIndependentlyActive() async throws {
        let root = Router()
        let engine = try #require(root.engine)
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Cover(RootRoute.self, providesNavigation: false)._routeDeclarations),
        ])
        await root.present(RootRoute())
        let modal = try #require(engine.normalTree.rootPath.last)
        modal.installRouteDeclarations(id: nil,
            branchSelection: AnyRouteBranchSelection(Binding.constant("a"), concurrent: true),
            routeDeclarations: Branch("a") { Push(SettingsRoute.self) }.routeScopeDeclarations
                + Branch("b") { Push(HomeDetailRoute.self) }.routeScopeDeclarations)
        let a = RouteScope(id: "a", route: nil)
        let b = RouteScope(id: "b", route: nil)
        engine.mutateRouteGraph {
            modal.registerBranchScope(a, for: "a")
            modal.registerBranchScope(b, for: "b")
        }
        #expect(engine.routePhase(for: a) == .active)
        #expect(engine.routePhase(for: b) == .active)
        #expect(engine.routePhase(for: engine.root) == .inactive)
    }

    @Test func handleIdentityIncludesScopeAndTarget() {
        let fixture = Fixture(concurrent: true)
        #expect(fixture.local(fixture.content) == fixture.local(fixture.content))
        #expect(fixture.local(fixture.content) != fixture.local(fixture.detail))
        #expect(fixture.root.branch("detail") == fixture.root.branch("detail"))
        #expect(fixture.root.branch("detail") != fixture.root.branch("content"))
    }
}

@MainActor
private struct Fixture {
    let root = Router()
    var engine: RouterEngine { root.engine! }
    let selection = PaneSelection()
    let sidebar = RouteScope(id: "sidebar", route: nil)
    let content = RouteScope(id: "content", route: nil)
    let detail = RouteScope(id: "detail", route: nil)

    init(concurrent: Bool) {
        @Bindable var selection = selection
        engine.root.installRouteDeclarations(id: nil,
            branchSelection: AnyRouteBranchSelection($selection.value, concurrent: concurrent),
            routeDeclarations:
                Branch("sidebar") { Push(NumberedRoute.self) }.routeScopeDeclarations
                + Branch("content") { Push(HomeDetailRoute.self); Sheet(LoginRoute.self) }.routeScopeDeclarations
                + Branch("detail") {
                    Push(SettingsRoute.self)
                    Push(HomeDetailRoute.self)
                    Push(DroppedRoute.self)
                    Cover(MessageRoute.self)
                }.routeScopeDeclarations)
        engine.mutateRouteGraph {
            engine.root.registerBranchScope(sidebar, for: "sidebar")
            engine.root.registerBranchScope(content, for: "content")
            engine.root.registerBranchScope(detail, for: "detail")
        }
    }

    func local(_ scope: RouteScope) -> Router { Router(engine: engine, scope: scope) }
}

@MainActor
@Observable
private final class PaneSelection { var value = "sidebar" }

private actor ScopedResolutionGate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private(set) var count = 0

    func wait() async {
        count += 1
        await withCheckedContinuation { continuation in
            waiter = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }
    func waitForStart() async {
        if count == 0 { await withCheckedContinuation { startWaiter = $0 } }
    }
    func release() { waiter?.resume(); waiter = nil }
}

private struct ScopedDelayedRoute: Route {
    let gate: ScopedResolutionGate
    func resolveRoute() async -> RouteResolution { await gate.wait(); return .allow }
    func destination() -> some View { Text("Delayed scoped destination") }
}

private struct ScopedGuardedRoute: Route {
    func resolveRoute() async -> RouteResolution { .reroute(ScopedLoginRoute()) }
    func destination() -> some View { Text("Guarded destination") }
}

private struct ScopedLoginRoute: Route {
    func destination() -> some View { Text("Shared login") }
}
