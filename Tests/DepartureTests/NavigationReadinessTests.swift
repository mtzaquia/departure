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
import Testing
@testable import Departure

@MainActor
@Suite
struct NavigationReadinessTests {
    @Test
    func concurrentPresentationWaitsForResolutionBeforePresentingLatestRequest() async {
        let engine = RouterEngine()
        let router = Router(engine: engine, scope: engine.root)
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(DelayedResolutionRoute.self)._routeDeclarations),
            RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
        ])

        let gate = ResolutionGate()
        let first = Task { await router.present(DelayedResolutionRoute(gate: gate)) }
        await gate.waitForResolutionToStart()

        var latestFinished = false
        let latest = Task {
            await router.present(SettingsRoute())
            latestFinished = true
        }
        for _ in 0..<100 where !latestFinished && engine.bufferedPresentationRequest == nil {
            await Task.yield()
        }

        #expect(!latestFinished)
        #expect(engine.normalTree.rootPath.isEmpty)

        gate.release()
        await first.value
        await latest.value

        #expect(engine.pendingRoute == nil)
        #expect(engine.normalTree.rootPath.count == 1)
        #expect(engine.normalTree.rootPath.last?.route is SettingsRoute)
    }

    @Test(arguments: [false, true])
    func concurrentPresentationsResolveOnlyActiveAndLatestRequests(cancelActive: Bool) async {
        let (engine, router) = makeRouter()
        let otherRouter = Router(engine: engine, scope: engine.root)
        let gate = ResolutionGate()
        let recorder = ResolutionRecorder()
        let first = Task { await router.present(DelayedResolutionRoute(gate: gate)) }
        await gate.waitForResolutionToStart()

        let middle = Task { await otherRouter.present(RecordedRoute(number: 2, recorder: recorder)) }
        for _ in 0..<100 where engine.bufferedPresentationRequest == nil { await Task.yield() }
        #expect(engine.bufferedPresentationRequest != nil)
        let latest = Task { await router.present(RecordedRoute(number: 3, recorder: recorder)) }
        // Superseded callers return immediately, before the active resolver finishes.
        await middle.value
        #expect(recorder.numbers.isEmpty)
        #expect((engine.bufferedPresentationRequest?.route as? RecordedRoute)?.number == 3)

        if cancelActive { first.cancel() }
        gate.release()
        await first.value
        await latest.value

        #expect(recorder.numbers == [3])
        #expect((engine.normalTree.rootPath.last?.route as? RecordedRoute)?.number == 3)
        #expect(!engine.isPresentationRequestInProgress)
        #expect(engine.bufferedPresentationRequest == nil)
    }

    @Test(arguments: [false, true])
    func bufferedPresentationContinuesAfterDroppedOrReroutedRequest(drop: Bool) async {
        let (engine, router) = makeRouter()
        let gate = ResolutionGate()
        let recorder = ResolutionRecorder()
        let resolution: RouteResolution = drop ? .drop : .reroute(SettingsRoute())
        let first = Task {
            await router.present(DelayedResolutionRoute(gate: gate, resolution: resolution))
        }
        await gate.waitForResolutionToStart()
        let latest = Task { await router.present(RecordedRoute(number: 2, recorder: recorder)) }
        for _ in 0..<100 where engine.bufferedPresentationRequest == nil { await Task.yield() }
        #expect(recorder.numbers.isEmpty)

        gate.release()
        await first.value
        await latest.value
        #expect(gate.resolutionCount == 1)
        #expect(recorder.numbers == [2])
        #expect((engine.normalTree.rootPath.last?.route as? RecordedRoute)?.number == 2)
        #expect(!engine.isPresentationRequestInProgress)
    }

    @Test
    func cancelledBufferedPresentationReturnsWithoutResolvingAndReleasesTheBuffer() async {
        let (engine, router) = makeRouter()
        let gate = ResolutionGate()
        let recorder = ResolutionRecorder()
        let first = Task { await router.present(DelayedResolutionRoute(gate: gate)) }
        await gate.waitForResolutionToStart()

        let cancelled = Task { await router.present(RecordedRoute(number: 2, recorder: recorder)) }
        for _ in 0..<100 where engine.bufferedPresentationRequest == nil { await Task.yield() }
        #expect(engine.bufferedPresentationRequest != nil)
        cancelled.cancel()
        await cancelled.value
        #expect(engine.bufferedPresentationRequest == nil)
        #expect(recorder.numbers.isEmpty)

        gate.release()
        await first.value
        await router.present(RecordedRoute(number: 3, recorder: recorder))
        #expect(recorder.numbers == [3])
        #expect(!engine.isPresentationRequestInProgress)
    }

    @Test(arguments: [false, true])
    func bufferedPresentationFollowsActiveResolutionDuringUnwind(cancelActive: Bool) async throws {
        let (engine, router) = makeRouter()
        await router.present(SettingsRoute())
        let old = try #require(engine.normalTree.rootPath.last)
        engine.routeScopeDidInstallInView(old)

        let gate = ResolutionGate()
        let recorder = ResolutionRecorder()
        let first = Task { await router.present(DelayedResolutionRoute(gate: gate)) }
        await gate.waitForResolutionToStart()
        let unwind = Task { await router.unwind(to: .root) }
        for _ in 0..<100 where !engine.normalTree.rootPath.isEmpty { await Task.yield() }
        gate.release()
        for _ in 0..<100 where engine.pendingRoute == nil { await Task.yield() }
        #expect(engine.pendingRoute?.route is DelayedResolutionRoute)

        let latest = Task { await router.present(RecordedRoute(number: 3, recorder: recorder)) }
        for _ in 0..<100 where engine.bufferedPresentationRequest == nil { await Task.yield() }
        #expect(engine.bufferedPresentationRequest != nil)
        #expect(recorder.numbers.isEmpty)

        if cancelActive {
            first.cancel()
            await first.value
        }
        engine.routeScopeDidLeaveView(old)
        #expect(await unwind.value)
        await first.value
        await latest.value

        #expect(gate.resolutionCount == 1)
        #expect(recorder.numbers == [3])
        #expect((engine.normalTree.rootPath.last?.route as? RecordedRoute)?.number == 3)
        #expect(!engine.isPresentationRequestInProgress)
    }

    @Test
    func presentationsWaitingForUnwindKeepOnlyLatestBeforeResolution() async throws {
        let (engine, router) = makeRouter()
        await router.present(SettingsRoute())
        let old = try #require(engine.normalTree.rootPath.last)
        engine.routeScopeDidInstallInView(old)
        let unwind = Task { await router.unwind(to: .root) }
        for _ in 0..<100 where !engine.normalTree.rootPath.isEmpty { await Task.yield() }

        let recorder = ResolutionRecorder()
        let middle = Task { await router.present(RecordedRoute(number: 2, recorder: recorder)) }
        for _ in 0..<100 where engine.pendingRoute == nil { await Task.yield() }
        #expect(engine.pendingRoute != nil)
        let latest = Task { await router.present(RecordedRoute(number: 3, recorder: recorder)) }
        await middle.value
        #expect(recorder.numbers.isEmpty)

        engine.routeScopeDidLeaveView(old)
        #expect(await unwind.value)
        await latest.value
        #expect(recorder.numbers == [3])
        #expect((engine.normalTree.rootPath.last?.route as? RecordedRoute)?.number == 3)
    }

    @Test
    func concurrentPresentationWaitsForActiveReplacementToFinish() async throws {
        let (engine, router) = makeRouter()
        await router.present(SettingsRoute())
        let old = try #require(engine.normalTree.rootPath.last)
        engine.routeScopeDidInstallInView(old)
        let recorder = ResolutionRecorder()
        let first = Task { await router.present(RecordedRoute(number: 2, recorder: recorder)) }
        for _ in 0..<100 where !engine.normalTree.rootPath.isEmpty { await Task.yield() }
        #expect(engine.pendingRoute?.append != nil)

        let latest = Task { await router.present(RecordedRoute(number: 3, recorder: recorder)) }
        for _ in 0..<100 where engine.bufferedPresentationRequest == nil { await Task.yield() }
        #expect(recorder.numbers == [2])
        #expect(engine.normalTree.rootPath.isEmpty)

        engine.routeScopeDidLeaveView(old)
        await first.value
        await latest.value
        #expect(recorder.numbers == [2, 3])
        #expect(engine.normalTree.rootPath.count == 1)
        #expect((engine.normalTree.rootPath.last?.route as? RecordedRoute)?.number == 3)
    }

    @Test
    func bufferedPresentationDropsWhenItsCapturedScopeLeaves() async throws {
        let (engine, router) = makeRouter()
        engine.root.installRouteDeclarations(sourceID: "push", id: nil, branchSelection: nil,
            routeDeclarations: [RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations)])
        await router.present(HomeDetailRoute())
        let old = try #require(engine.normalTree.rootPath.last)
        let scopedRouter = Router(engine: engine, scope: old)
        let gate = ResolutionGate()
        let recorder = ResolutionRecorder()
        let first = Task { await router.present(DelayedResolutionRoute(gate: gate)) }
        await gate.waitForResolutionToStart()
        let latest = Task { await scopedRouter.present(RecordedRoute(number: 2, recorder: recorder)) }
        for _ in 0..<100 where engine.bufferedPresentationRequest == nil { await Task.yield() }

        #expect(await router.unwind(to: .root))
        gate.release()
        await first.value
        await latest.value
        #expect(recorder.numbers.isEmpty)
        await router.present(RecordedRoute(number: 3, recorder: recorder))
        #expect(recorder.numbers == [3])
        #expect(!engine.isPresentationRequestInProgress)
    }

    private func makeRouter() -> (RouterEngine, Router) {
        let engine = RouterEngine()
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations
                + Sheet(DelayedResolutionRoute.self)._routeDeclarations
                + Sheet(RecordedRoute.self)._routeDeclarations),
        ])
        return (engine, Router(engine: engine, scope: engine.root))
    }

    @Test(arguments: [false, true])
    func resolutionFinishingDuringUnwindWaitsWithoutResolvingAgain(cancel: Bool) async throws {
        let router = RouterEngine()
        router.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
            RouteScopeDeclaration(routes: Sheet(DelayedResolutionRoute.self)._routeDeclarations),
        ])
        await router.present(SettingsRoute())
        let old = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(old)
        let gate = ResolutionGate()
        let request = Task { await router.present(DelayedResolutionRoute(gate: gate)) }
        await gate.waitForResolutionToStart()

        let unwind = Task { await router.unwind(to: .root) }
        for _ in 0..<100 where !router.normalTree.rootPath.isEmpty { await Task.yield() }
        #expect(router.navigationTransaction.isInProgress)
        #expect(router.normalTree.rootPath.isEmpty)
        gate.release()
        for _ in 0..<100 where router.pendingRoute == nil { await Task.yield() }
        #expect(router.pendingRoute != nil)
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(gate.resolutionCount == 1)

        if cancel {
            request.cancel()
            await request.value
            #expect(router.pendingRoute == nil)
        }
        router.routeScopeDidLeaveView(old)
        #expect(await unwind.value)
        await request.value

        #expect(router.pendingRoute == nil)
        #expect(gate.resolutionCount == 1)
        #expect(router.normalTree.rootPath.count == (cancel ? 0 : 1))
        if !cancel {
            #expect(router.normalTree.rootPath.last?.route is DelayedResolutionRoute)
        }
    }
}

@MainActor
private final class ResolutionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private(set) var resolutionCount = 0

    func wait() async {
        resolutionCount += 1
        await withCheckedContinuation {
            continuation = $0
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitForResolutionToStart() async {
        guard resolutionCount == 0 else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private struct DelayedResolutionRoute: Route {
    let gate: ResolutionGate
    var resolution: RouteResolution = .allow

    func resolveRoute() async -> RouteResolution {
        await gate.wait()
        return resolution
    }

    func destination() -> some View { Text("Delayed resolution") }
}

@MainActor
private final class ResolutionRecorder {
    var numbers: [Int] = []
}

private struct RecordedRoute: Route {
    let number: Int
    let recorder: ResolutionRecorder

    func resolveRoute() async -> RouteResolution {
        recorder.numbers.append(number)
        return .allow
    }

    func destination() -> some View { Text("Recorded \(number)") }
}
