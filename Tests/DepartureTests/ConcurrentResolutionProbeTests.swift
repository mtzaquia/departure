import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ConcurrentResolutionProbeTests {
    @Test
    func olderResolutionCannotOvertakeANewerPresentation() async {
        let engine = RouterEngine(routes: RootRouteMap {
            testSheet(testDestination(SlowProbeRoute.self))
            testSheet(testDestination(SettingsRoute.self))
        })
        let router = Router(engine: engine, scope: engine.root)
        let gate = ProbeResolutionGate()
        let first = Task { await router.present(SlowProbeRoute(gate: gate)) }
        await gate.waitForStart()

        var latestFinished = false
        let latest = Task {
            await router.present(SettingsRoute())
            latestFinished = true
        }
        for _ in 0..<1000 where !latestFinished && engine.pendingRoute == nil {
            await Task.yield()
        }
        #expect(!latestFinished)
        #expect(engine.defaultSpace.rootPath.count == 0)

        gate.release()
        await first.value
        await latest.value
        #expect(engine.defaultSpace.rootPath.count == 1)
        #expect(engine.defaultSpace.rootPath.last?.route is SettingsRoute)
    }

    @Test func latestWaitingRequestSupersedesWithoutResolvingAndReturnsTheExactScope() async throws {
        let engine = fixture()
        let origin = RouteRequestOrigin(scope: engine.root)
        let gate = ProbeResolutionGate()
        let recorder = ResolutionRecorder()
        let first = Task { await engine.requestRouteWhenReady(SlowProbeRoute(gate: gate), origin: origin) }
        await gate.waitForStart()
        let middle = Task { await engine.requestRouteWhenReady(CountingProbeRoute(name: "middle", recorder: recorder), origin: origin) }
        try await waitUntil { engine.bufferedPresentationRequest?.route is CountingProbeRoute }
        let latest = Task { await engine.requestRouteWhenReady(SettingsRoute(), origin: origin) }
        try await waitUntil { engine.bufferedPresentationRequest?.route is SettingsRoute }
        #expect(await middle.value == nil)
        #expect(recorder.names.isEmpty)
        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(!engine.isNavigating)
        gate.release()
        let firstScope = try #require(await first.value)
        #expect(firstScope.route is SlowProbeRoute)
        let latestScope = try #require(await latest.value)
        #expect(latestScope === engine.defaultSpace.rootPath.last)
        #expect(latestScope !== firstScope)
        #expect(latestScope.route is SettingsRoute)
        #expect(!engine.isPresentationRequestInProgress)
    }

    @Test(arguments: [false, true])
    func cancellationBelongsToTheActiveOrWaitingCaller(cancelActive: Bool) async throws {
        let engine = fixture()
        let gate = ProbeResolutionGate()
        let recorder = ResolutionRecorder()
        let origin = RouteRequestOrigin(scope: engine.root)
        let first = Task { await engine.requestRouteWhenReady(SlowProbeRoute(gate: gate), origin: origin) }
        await gate.waitForStart()
        let next = Task { await engine.requestRouteWhenReady(CountingProbeRoute(name: "next", recorder: recorder), origin: origin) }
        try await waitUntil { engine.bufferedPresentationRequest != nil }
        if cancelActive { first.cancel() }
        else {
            next.cancel()
            #expect(await next.value == nil)
            #expect(engine.bufferedPresentationRequest == nil)
        }
        #expect(recorder.names.isEmpty)
        #expect(engine.isPresentationRequestInProgress)
        gate.release()
        let firstScope = await first.value
        let nextScope = await next.value
        #expect((firstScope == nil) == cancelActive)
        #expect((nextScope == nil) == !cancelActive)
        #expect(recorder.names == (cancelActive ? ["next"] : []))
        #expect(!engine.isPresentationRequestInProgress)
        #expect(engine.bufferedPresentationRequest == nil)
        #expect(await engine.requestRouteWhenReady(SettingsRoute(), origin: origin) === engine.defaultSpace.rootPath.last)
    }

    @Test func reroutingKeepsAdmissionForTheWholeResolutionChain() async throws {
        let engine = fixture()
        let origin = RouteRequestOrigin(scope: engine.root)
        let firstGate = ProbeResolutionGate(), finalGate = ProbeResolutionGate()
        let recorder = ResolutionRecorder()
        let first = Task { await engine.requestRouteWhenReady(SlowReroutingProbeRoute(gate: firstGate, next: finalGate), origin: origin) }
        await firstGate.waitForStart()
        let next = Task { await engine.requestRouteWhenReady(CountingProbeRoute(name: "next", recorder: recorder), origin: origin) }
        try await waitUntil { engine.bufferedPresentationRequest != nil }
        firstGate.release()
        await finalGate.waitForStart()
        #expect(recorder.names.isEmpty)
        #expect(engine.defaultSpace.rootPath.isEmpty)
        finalGate.release()
        #expect(await first.value?.route is SlowProbeRoute)
        #expect(await next.value === engine.defaultSpace.rootPath.last)
        #expect(recorder.names == ["next"])
        #expect(firstGate.resolutionCount == 1)
        #expect(finalGate.resolutionCount == 1)
    }

    @Test func cancellingResolutionDoesNotStartAReroutedResolver() async throws {
        let engine = fixture()
        let firstGate = ProbeResolutionGate(), finalGate = ProbeResolutionGate()
        let first = Task { await engine.requestRouteWhenReady(SlowReroutingProbeRoute(gate: firstGate, next: finalGate)) }
        await firstGate.waitForStart()
        first.cancel()
        firstGate.release()
        #expect(await first.value == nil)
        #expect(finalGate.resolutionCount == 0)
        #expect(!engine.isPresentationRequestInProgress)
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }

    @Test func bufferedResolutionKeepsTheWaitingCallersTaskContext() async throws {
        let engine = fixture()
        let gate = ProbeResolutionGate()
        let recorder = ResolutionRecorder()
        let first = Task {
            await ProbeTaskContext.$name.withValue("active") { await engine.requestRouteWhenReady(SlowProbeRoute(gate: gate)) }
        }
        await gate.waitForStart()
        let next = Task {
            await ProbeTaskContext.$name.withValue("waiting") {
                await engine.requestRouteWhenReady(CountingProbeRoute(name: "next", recorder: recorder))
            }
        }
        try await waitUntil { engine.bufferedPresentationRequest != nil }
        gate.release()
        _ = await first.value
        #expect(await next.value === engine.defaultSpace.rootPath.last)
        #expect(recorder.contexts == ["waiting"])
    }

    @Test func droppingAnActiveRequestReleasesAdmissionForItsLatestWaiter() async throws {
        let engine = fixture()
        let gate = ProbeResolutionGate()
        let first = Task { await engine.requestRouteWhenReady(SlowProbeRoute(gate: gate, outcome: .drop)) }
        await gate.waitForStart()
        let latest = Task { await engine.requestRouteWhenReady(SettingsRoute()) }
        try await waitUntil { engine.bufferedPresentationRequest != nil }
        gate.release()
        #expect(await first.value == nil)
        #expect(await latest.value === engine.defaultSpace.rootPath.last)
        #expect(engine.defaultSpace.rootPath.last?.route is SettingsRoute)
        #expect(!engine.isPresentationRequestInProgress)
    }

    @Test(arguments: [false, true])
    func grantedWaiterKeepsItsTurnAndItsOwnCancellation(cancelGranted: Bool) async throws {
        let engine = fixture()
        let origin = RouteRequestOrigin(scope: engine.root)
        let gate = ProbeResolutionGate()
        let recorder = ResolutionRecorder()
        var waiting: Task<RouteScope?, Never>?
        var newest: Task<RouteScope?, Never>?
        let first = Task {
            let scope = await engine.requestRouteWhenReady(SlowProbeRoute(gate: gate), origin: origin)
            if cancelGranted { waiting?.cancel() }
            newest = Task { await engine.requestRouteWhenReady(CountingProbeRoute(name: "newest", recorder: recorder), origin: origin) }
            return scope
        }
        await gate.waitForStart()
        waiting = Task { await engine.requestRouteWhenReady(CountingProbeRoute(name: "granted", recorder: recorder), origin: origin) }
        try await waitUntil { engine.bufferedPresentationRequest != nil }
        gate.release()
        #expect(await first.value?.route is SlowProbeRoute)
        let grantedResult = await waiting?.value
        #expect((grantedResult == nil) == cancelGranted)
        let latest = try #require(newest)
        #expect(await latest.value === engine.defaultSpace.rootPath.last)
        #expect(recorder.names == (cancelGranted ? ["newest"] : ["granted", "newest"]))
        #expect(!engine.isPresentationRequestInProgress)
    }

    @Test func waitingRequestFromARemovedScopeNeverResolves() async throws {
        let engine = fixture()
        let root = Router(engine: engine, scope: engine.root)
        await root.present(HomeDetailRoute())
        let old = try #require(engine.defaultSpace.rootPath.last)
        let gate = ProbeResolutionGate()
        let recorder = ResolutionRecorder()
        let first = Task { await engine.requestRouteWhenReady(SlowProbeRoute(gate: gate), origin: RouteRequestOrigin(scope: engine.root)) }
        await gate.waitForStart()
        let next = Task { await engine.requestRouteWhenReady(CountingProbeRoute(name: "removed", recorder: recorder), origin: RouteRequestOrigin(scope: old)) }
        try await waitUntil { engine.bufferedPresentationRequest != nil }
        #expect(await root.unwind(to: .root))
        gate.release()
        #expect(await first.value?.route is SlowProbeRoute)
        #expect(await next.value == nil)
        #expect(recorder.names.isEmpty)
        #expect(!engine.isPresentationRequestInProgress)
    }

    @Test func waitingRequestRechecksCoverageAfterAnElevatedPresentation() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            HighPriority {
                testSheet(testDestination(LoginRoute.self)) {
                    testSheet(testDestination(CountingProbeRoute.self))
                }
            }
            CriticalPriority { testSheet(testDestination(SlowProbeRoute.self)) }
        })
        await engine.present(LoginRoute())
        let high = try #require(engine.spaces.highSpace?.root)
        let gate = ProbeResolutionGate()
        let recorder = ResolutionRecorder()
        let first = Task { await engine.requestRouteWhenReady(SlowProbeRoute(gate: gate), origin: RouteRequestOrigin(scope: high)) }
        await gate.waitForStart()
        let next = Task { await engine.requestRouteWhenReady(CountingProbeRoute(name: "covered", recorder: recorder), origin: RouteRequestOrigin(scope: high)) }
        try await waitUntil { engine.bufferedPresentationRequest != nil }
        gate.release()
        #expect(await first.value === engine.spaces.criticalSpace?.root)
        #expect(await next.value == nil)
        #expect(recorder.names.isEmpty)
        #expect(high.path.isEmpty)
    }

    @Test func coveredCallerCannotReplaceAnEligibleAdmissionWaiter() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
 testSheet(testDestination(SettingsRoute.self))
            HighPriority {
                testSheet(testDestination(LoginRoute.self)) {
                    testSheet(testDestination(SlowProbeRoute.self))
                    testSheet(testDestination(CountingProbeRoute.self))
                }
            }
        })
        await engine.present(LoginRoute())
        let high = try #require(engine.spaces.highSpace?.root)
        let origin = RouteRequestOrigin(scope: high)
        let gate = ProbeResolutionGate()
        let recorder = ResolutionRecorder()
        let first = Task { await engine.requestRouteWhenReady(SlowProbeRoute(gate: gate), origin: origin) }
        await gate.waitForStart()
        let next = Task { await engine.requestRouteWhenReady(CountingProbeRoute(name: "eligible", recorder: recorder), origin: origin) }
        try await waitUntil { engine.bufferedPresentationRequest != nil }
        let waiting = engine.bufferedPresentationRequest
        #expect(await engine.requestRouteWhenReady(SettingsRoute(), origin: RouteRequestOrigin(scope: engine.root)) == nil)
        #expect(engine.bufferedPresentationRequest === waiting)
        gate.release()
        _ = await first.value
        #expect(await next.value === high.path.last)
        #expect(recorder.names == ["eligible"])
    }

    @Test(arguments: [RoutePriority.high, .critical])
    func higherPriorityAttemptAlsoWaitsForTheActiveResolver(priority: RoutePriority) async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            testSheet(testDestination(SlowProbeRoute.self))

            HighPriority {
                testSheet(testDestination(LoginRoute.self))
            }
            CriticalPriority {
                testCover(testDestination(LockRoute.self))
            }
        })
        let router = Router(engine: engine, scope: engine.root)
        let gate = ProbeResolutionGate()
        let first = Task { await router.present(SlowProbeRoute(gate: gate)) }
        await gate.waitForStart()
        let next = Task {
            if priority == .high { await router.present(LoginRoute()) }
            else { await router.present(LockRoute()) }
        }
        try await waitUntil { engine.bufferedPresentationRequest != nil }
        #expect(engine.spaces.space(for: priority) == nil)
        #expect(engine.defaultSpace.rootPath.isEmpty)
        gate.release()
        await first.value
        await next.value
        #expect(engine.defaultSpace.rootPath.last?.route is SlowProbeRoute)
        #expect(engine.spaces.activeSpace.priority == priority)
        #expect(engine.routePhase(for: engine.defaultSpace.rootPath.last!) == .inactive)
    }

    @Test func latestRequestsDuringUnwindSupersedeWithoutResolvingOrDelayingUnwind() async throws {
        let engine = fixture()
        let origin = RouteRequestOrigin(scope: engine.root)
        await engine.present(SettingsRoute())
        let old = try #require(engine.defaultSpace.rootPath.last)
        engine.routeScopeDidInstallInView(old)
        let gate = ProbeResolutionGate()
        let recorder = ResolutionRecorder()
        let first = Task { await engine.requestRouteWhenReady(SlowProbeRoute(gate: gate), origin: origin) }
        await gate.waitForStart()
        let unwind = Task { await Router(engine: engine, scope: old).unwind(to: .root) }
        try await waitUntil { engine.defaultSpace.rootPath.isEmpty }
        let middle = Task { await engine.requestRouteWhenReady(CountingProbeRoute(name: "middle", recorder: recorder), origin: origin) }
        try await waitUntil { engine.bufferedPresentationRequest != nil }
        gate.release()
        #expect(await first.value == nil)
        try await waitUntil { engine.pendingRoute?.request != nil }
        let latestGate = ProbeResolutionGate()
        let latest = Task { await engine.requestRouteWhenReady(SlowProbeRoute(gate: latestGate), origin: origin) }
        try await waitUntil { engine.pendingRoute?.request?.route is SlowProbeRoute }
        #expect(await middle.value == nil)
        #expect(recorder.names.isEmpty)
        #expect(latestGate.resolutionCount == 0)
        engine.routeScopeDidLeaveView(old)
        await latestGate.waitForStart()
        #expect(await unwind.value)
        #expect(!engine.isNavigating)
        latestGate.release()
        #expect(await latest.value === engine.defaultSpace.rootPath.last)
        #expect(engine.pendingRoute == nil)
        #expect(engine.bufferedPresentationRequest == nil)
    }

    @Test(arguments: [false, true])
    func deferredHostInsertionKeepsItsExactResultOrIsSuperseded(supersede: Bool) async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            testSheet(testDestination(SettingsRoute.self))
            Branches {
                Branch("first") {}
                Branch("second") { testSheet(testDestination(CountingProbeRoute.self)) }
            }
        })
        engine.routeScopeDidInstallInView(engine.root)
        let branch = try #require(engine.root.branchScopes["second"])
        let recorder = ResolutionRecorder()
        let origin = RouteRequestOrigin(scope: engine.root)
        let first = Task { await engine.requestRouteWhenReady(CountingProbeRoute(name: "staged", recorder: recorder), origin: origin) }
        try await waitUntil { engine.pendingRoute?.operation != nil && !engine.isNavigating }
        #expect(branch.path.isEmpty)
        #expect(engine.isPresentationRequestInProgress)
        if supersede {
            let latest = await engine.requestRouteWhenReady(SettingsRoute(), origin: origin)
            #expect(await first.value == nil)
            #expect(latest === engine.defaultSpace.rootPath.last)
            engine.routeScopeDidInstallInView(branch)
            #expect(branch.path.isEmpty)
        } else {
            engine.routeScopeDidInstallInView(branch)
            #expect(await first.value === branch.path.last)
            #expect(branch.path.count == 1)
        }
        #expect(!engine.isPresentationRequestInProgress)
        #expect(engine.pendingRoute == nil)
    }

    private func fixture() -> RouterEngine {
        RouterEngine(routes: RootRouteMap {
            testSheet(testDestination(SlowProbeRoute.self))
            testSheet(testDestination(SettingsRoute.self))
            testSheet(testDestination(CountingProbeRoute.self))
            testPush(testDestination(HomeDetailRoute.self))
        })
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 where !condition() { await Task.yield() }
        try #require(condition())
    }
}

@MainActor
private final class ProbeResolutionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var started = false
    private(set) var resolutionCount = 0

    func wait() async {
        resolutionCount += 1
        started = true
        await withCheckedContinuation {
            continuation = $0
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitForStart() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private struct SlowProbeRoute: Route {
    let gate: ProbeResolutionGate
    let outcome: RouteResolution

    init(gate: ProbeResolutionGate, outcome: RouteResolution = .allow) {
        self.gate = gate
        self.outcome = outcome
    }

    func resolveRoute() async -> RouteResolution {
        await gate.wait()
        return outcome
    }
}

private struct SlowReroutingProbeRoute: Route {
    let gate: ProbeResolutionGate
    let next: ProbeResolutionGate
    func resolveRoute() async -> RouteResolution {
        await gate.wait()
        return .reroute(SlowProbeRoute(gate: next))
    }
}

@MainActor private final class ResolutionRecorder {
    var names: [String] = []
    var contexts: [String] = []
}

private struct CountingProbeRoute: Route {
    let name: String
    let recorder: ResolutionRecorder
    func resolveRoute() async -> RouteResolution {
        recorder.names.append(name)
        recorder.contexts.append(ProbeTaskContext.name)
        return .allow
    }
}

private enum ProbeTaskContext {
    @TaskLocal static var name = "none"
}
