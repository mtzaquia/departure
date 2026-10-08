import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SpaceAuthorityTests {
    @Test(arguments: [RoutePriority.high, .critical])
    func externalNormalHandleCannotActInOrDismissACoveringSpace(priority: RoutePriority) async throws {
        let owner = fixture()
        await owner.normal.present(SettingsRoute())
        let normalScope = try #require(owner.engine.normalSpace.rootPath.last)
        if priority == .high { await owner.current.present(LoginRoute()) }
        else { await owner.current.present(LockRoute()) }
        let elevated = try #require(owner.engine.spaces.space(for: priority))
        let probe = AuthorityProbe()
        normalScope.installHookDeclarations(hookDeclarations: [
            ActionInterceptor(AuthorityAction.self) { invocation in
                probe.events.append("interceptor")
                try? await invocation()
            }.declaration,
        ])

        // Capture after the covering space appears, as an external callback would.
        let external = owner.normal
        await external.perform(AuthorityAction(probe: probe))
        await external.present(HomeDetailRoute())
        await external.present(LockRoute())
        #expect(!((await external.unwind(to: .root))))
        #expect(!((await external.unwind(to: .topmostAncestor))))
        #expect(!((await external.dismissSpace())))
        #expect(probe.events.isEmpty)
        #expect(owner.engine.normalSpace.rootPath.last === normalScope)
        #expect(owner.engine.spaces.activeSpace === elevated)

        await owner.current.perform(AuthorityAction(probe: probe))
        #expect(probe.events == ["body"])
        #expect(await owner.dismissSpace(priority))
        await external.perform(AuthorityAction(probe: probe))
        #expect(probe.events == ["body", "interceptor", "body"])
    }

    @Test func deferredInvocationCannotExecuteAfterItsSourceIsCovered() async throws {
        let owner = fixture()
        let probe = AuthorityProbe()
        owner.engine.root.installHookDeclarations(hookDeclarations: [
            ActionInterceptor(AuthorityAction.self) { invocation in probe.invocation = invocation }.declaration,
        ])
        await owner.normal.perform(AuthorityAction(probe: probe))
        let invocation = try #require(probe.invocation)
        probe.invocation = nil
        await owner.current.present(LockRoute())
        do {
            try await invocation()
            Issue.record("A covered action invocation executed")
        } catch { #expect(error is CancellationError) }
        #expect(probe.events.isEmpty)
        #expect(owner.engine.spaces.criticalSpace?.root.route is LockRoute)
    }

    @Test func rerouteBlockedDuringResolutionCannotRetryThroughTheLockscreen() async throws {
        let owner = fixture()
        let probe = AuthorityProbe()
        let gate = AuthorityGate()
        await owner.normal.perform(AuthorityRerouteAction(probe: probe, gate: gate))
        await gate.waitUntilEntered()
        await owner.current.present(LockRoute())
        let lock = try #require(owner.engine.spaces.criticalSpace?.root)
        lock.installHookDeclarations(hookDeclarations: [
            ActionInterceptor(AuthorityRerouteAction.self) { _ in probe.events.append("lock-interceptor") }.declaration,
        ])
        owner.engine.routeScopeDidInstallInView(lock)
        gate.release()
        for _ in 0..<1000 { await Task.yield() }
        #expect(probe.events == ["reroute"])
        #expect(owner.engine.normalSpace.rootPath.isEmpty)
        #expect(owner.engine.spaces.criticalSpace?.root === lock)
    }

    @Test func intentionalRerouteIntoHigherPriorityStillRetriesAtItsDestination() async throws {
        let owner = fixture()
        let probe = AuthorityProbe()
        await owner.normal.perform(AuthorityElevatedAction(probe: probe))
        for _ in 0..<1000 where owner.engine.spaces.highSpace == nil { await Task.yield() }
        let destination = try #require(owner.engine.spaces.highSpace?.root)
        #expect(probe.events == ["reroute"])
        destination.installHookDeclarations(hookDeclarations: [
            ActionInterceptor(AuthorityElevatedAction.self) { invocation in
                probe.events.append("destination")
                try? await invocation()
            }.declaration,
        ])
        owner.engine.routeScopeDidInstallInView(destination)
        for _ in 0..<1000 where probe.events.count < 3 { await Task.yield() }
        #expect(probe.events == ["reroute", "destination", "body"])
    }

    private func fixture() -> RootRouter {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Push(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
            Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() })
            Push(RouteDestination(AuthorityDestination.self) { _, _ in EmptyView() })
        } highPriority: {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() })
        } criticalPriority: {
            Cover(RouteDestination(LockRoute.self) { _, _ in EmptyView() })
        }, router: owner) { EmptyView() }
        return owner
    }
}

@MainActor private final class AuthorityProbe {
    var events: [String] = []
    var invocation: ActionInvocation<Void>?
}

@MainActor private struct AuthorityAction: Action {
    let probe: AuthorityProbe
    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        probe.events.append("body")
    }
}

@MainActor private struct AuthorityRerouteAction: Action {
    let probe: AuthorityProbe
    let gate: AuthorityGate
    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        if context.isRunning(in: AuthorityDestination.self) { probe.events.append("body"); return }
        probe.events.append("reroute")
        throw .reroute(AuthorityDestination(gate: gate))
    }
}

@MainActor private struct AuthorityElevatedAction: Action {
    let probe: AuthorityProbe
    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        if context.isRunning(in: LoginRoute.self) { probe.events.append("body"); return }
        probe.events.append("reroute")
        throw .reroute(LoginRoute())
    }
}

private struct AuthorityDestination: Route {
    let gate: AuthorityGate
    func resolveRoute() async -> RouteResolution { await gate.enter(); return .allow }
}

@MainActor private final class AuthorityGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func enter() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilEntered() async {
        for _ in 0..<1000 where !entered { await Task.yield() }
        #expect(entered)
    }
    func release() { continuation?.resume(); continuation = nil }
}
