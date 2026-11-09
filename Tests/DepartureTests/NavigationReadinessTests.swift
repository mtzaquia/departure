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
@Suite(.timeLimit(.minutes(1)))
struct NavigationReadinessTests {
    @Test func awakenedRequestCanStillBeSupersededBeforeClaimingItsTurn() async {
        let engine = queuedRequestFixture()
        let operation = engine.beginNavigationOperation()
        let original = Task { await engine.requestRouteWhenReady(SettingsRoute()) }
        for _ in 0..<1000 where engine.pendingRoute == nil { await Task.yield() }
        engine.finishNavigationOperation(operation)
        #expect(engine.pendingRoute?.request != nil)
        let latest = await engine.requestRouteWhenReady(LoginRoute())
        #expect(await original.value == nil)
        #expect(latest === engine.tree.rootPath.last)
        #expect(engine.tree.rootPath.last?.route is LoginRoute)
        #expect(engine.pendingRoute == nil)
    }

    @Test func anotherUnwindBeforeAnAwakenedCallerRunsKeepsItSuspended() async {
        let engine = queuedRequestFixture()
        let first = engine.beginNavigationOperation()
        var finished = false
        let presentation = Task {
            let scope = await engine.requestRouteWhenReady(SettingsRoute())
            finished = true
            return scope
        }
        for _ in 0..<1000 where engine.pendingRoute == nil { await Task.yield() }
        let request = engine.pendingRoute?.request
        engine.finishNavigationOperation(first)
        let next = engine.beginNavigationOperation()
        for _ in 0..<1000 where request?.continuation == nil { await Task.yield() }
        #expect(request?.continuation != nil)
        #expect(engine.pendingRoute?.request === request)
        #expect(!finished)
        #expect(engine.tree.rootPath.isEmpty)
        engine.finishNavigationOperation(next)
        #expect(await presentation.value === engine.tree.rootPath.last)
        #expect(engine.tree.rootPath.last?.route is SettingsRoute)
        #expect(engine.pendingRoute == nil)
    }

    @Test func cancellingAnAwakenedRequestPreventsItsPresentation() async {
        let engine = queuedRequestFixture()
        let operation = engine.beginNavigationOperation()
        let presentation = Task { await engine.requestRouteWhenReady(SettingsRoute()) }
        for _ in 0..<1000 where engine.pendingRoute == nil { await Task.yield() }
        engine.finishNavigationOperation(operation)
        presentation.cancel()
        #expect(await presentation.value == nil)
        #expect(engine.tree.rootPath.isEmpty)
        #expect(engine.pendingRoute == nil)
    }

    @Test func unwindCompletesWhileItsFollowupIsStillResolving() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            testSheet(testDestination(SettingsRoute.self))
            testSheet(testDestination(DelayedResolutionRoute.self))
        }, router: owner) { EmptyView() }
        let root = owner.root
        await root.present(SettingsRoute())
        let outgoing = try #require(owner.engine.tree.rootPath.last)
        owner.engine.routeScopeDidInstallInView(outgoing)
        var unwindFinished = false, presentationFinished = false
        let unwind = Task {
            let result = await owner.current.resetToRoot()
            unwindFinished = true
            return result
        }
        for _ in 0..<1000 where !owner.engine.isNavigating { await Task.yield() }
        let gate = ResolutionGate()
        let presentation = Task {
            await root.present(DelayedResolutionRoute(gate: gate))
            presentationFinished = true
        }
        for _ in 0..<1000 where owner.engine.pendingRoute == nil { await Task.yield() }
        #expect(!unwindFinished)
        #expect(!presentationFinished)
        #expect(gate.resolutionCount == 0)
        owner.engine.routeScopeDidLeaveView(outgoing)
        await gate.waitForResolutionToStart()
        for _ in 0..<1000 where !unwindFinished { await Task.yield() }
        #expect(unwindFinished)
        #expect(!presentationFinished)
        #expect(!owner.engine.isNavigating)
        gate.release()
        #expect(await unwind.value)
        await presentation.value
        #expect(owner.engine.tree.rootPath.last?.route is DelayedResolutionRoute)
    }

    @Test func bufferedResolutionRunsInItsOriginalCallersTaskContext() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            testSheet(testDestination(SettingsRoute.self))
            testSheet(testDestination(CallerContextRoute.self))
        }, router: owner) { EmptyView() }
        let root = owner.root
        await root.present(SettingsRoute())
        let outgoing = try #require(owner.engine.tree.rootPath.last)
        owner.engine.routeScopeDidInstallInView(outgoing)
        let unwind = Task {
            await CallerContext.$name.withValue("unwind") { await owner.current.resetToRoot() }
        }
        for _ in 0..<1000 where !owner.engine.isNavigating { await Task.yield() }
        var context: String?
        let presentation = Task {
            await CallerContext.$name.withValue("presentation") {
                await root.present(CallerContextRoute { context = $0 })
            }
        }
        for _ in 0..<1000 where owner.engine.pendingRoute == nil { await Task.yield() }
        #expect(context == nil)
        owner.engine.routeScopeDidLeaveView(outgoing)
        #expect(await unwind.value)
        await presentation.value
        #expect(context == "presentation")
    }

    @Test func cancellingCommittedUnwindDoesNotCancelAnUnrelatedQueuedPresentation() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            testSheet(testDestination(SettingsRoute.self))
            testSheet(testDestination(LoginRoute.self))
        }, router: owner) { EmptyView() }
        let root = owner.current
        await root.present(SettingsRoute())
        let old = try #require(owner.engine.tree.rootPath.last)
        owner.engine.routeScopeDidInstallInView(old)
        let unwind = Task { await owner.current.resetToRoot() }
        for _ in 0..<1000 where !owner.engine.tree.rootPath.isEmpty { await Task.yield() }
        unwind.cancel()
        let request = Task { await root.present(LoginRoute()) }
        for _ in 0..<1000 where owner.engine.pendingRoute == nil { await Task.yield() }
        #expect(owner.engine.pendingRoute != nil)
        owner.engine.routeScopeDidLeaveView(old)
        #expect(await unwind.value)
        await request.value
        #expect(owner.engine.pendingRoute == nil)
        #expect(!owner.engine.isNavigating)
        #expect(owner.engine.tree.rootPath.last?.route is LoginRoute)
    }

    @Test func cancellingResumedRequestCancelsItsOwnResolution() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            testSheet(testDestination(SettingsRoute.self))
            testSheet(testDestination(DelayedResolutionRoute.self))
        }, router: owner) { EmptyView() }
        let root = owner.current
        await root.present(SettingsRoute())
        let old = try #require(owner.engine.tree.rootPath.last)
        owner.engine.routeScopeDidInstallInView(old)
        let unwind = Task { await owner.current.resetToRoot() }
        for _ in 0..<1000 where !owner.engine.tree.rootPath.isEmpty { await Task.yield() }
        let gate = ResolutionGate()
        let request = Task { await root.present(DelayedResolutionRoute(gate: gate)) }
        for _ in 0..<1000 where owner.engine.pendingRoute == nil { await Task.yield() }
        #expect(owner.engine.pendingRoute != nil)
        owner.engine.routeScopeDidLeaveView(old)
        await gate.waitForResolutionToStart()
        #expect(owner.engine.pendingRoute == nil)
        request.cancel()
        gate.release()
        await request.value
        #expect(await unwind.value)
        #expect(gate.resolutionCount == 1)
        #expect(owner.engine.tree.rootPath.isEmpty)
        #expect(!owner.engine.isNavigating)
        await root.present(SettingsRoute())
        #expect(owner.engine.tree.rootPath.last?.route is SettingsRoute)
    }

    @Test(arguments: [false, true])
    func resolutionFinishingDuringUnwindWaitsWithoutResolvingAgain(cancel: Bool) async throws {
        let router = RouterEngine()
        router.root.defineTestMap(id: nil, selection: nil, definitions: [
            RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            RouteScopeDeclaration(routes: testDeclaration(testDestination(DelayedResolutionRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
        ])
        await router.present(SettingsRoute())
        let old = try #require(router.tree.rootPath.last)
        router.routeScopeDidInstallInView(old)
        let gate = ResolutionGate()
        let surviving = Router(engine: router, scope: router.root)
        let request = Task { await surviving.present(DelayedResolutionRoute(gate: gate)) }
        await gate.waitForResolutionToStart()

        let unwind = Task { await router.resetToRoot() }
        for _ in 0..<100 where !router.tree.rootPath.isEmpty { await Task.yield() }
        #expect(router.isNavigating)
        #expect(router.tree.rootPath.isEmpty)
        gate.release()
        for _ in 0..<100 where router.pendingRoute == nil { await Task.yield() }
        #expect(router.pendingRoute != nil)
        #expect(router.tree.rootPath.isEmpty)
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
        #expect(router.tree.rootPath.count == (cancel ? 0 : 1))
        if !cancel {
            #expect(router.tree.rootPath.last?.route is DelayedResolutionRoute)
        }
    }

    private func queuedRequestFixture() -> RouterEngine {
        RouterEngine(routes: RootRouteMap {
            testSheet(testDestination(SettingsRoute.self))
            testSheet(testDestination(LoginRoute.self))
        })
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

    func resolveRoute() async -> RouteResolution {
        await gate.wait()
        return .allow
    }

    func destination() -> some View { Text("Delayed resolution") }
}

private enum CallerContext {
    @TaskLocal static var name = "none"
}

@MainActor
private struct CallerContextRoute: Route {
    let record: (String) -> Void
    func resolveRoute() async -> RouteResolution {
        record(CallerContext.name)
        return .allow
    }
}
