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
    @Test func cancellingCommittedUnwindDoesNotCancelAnUnrelatedQueuedPresentation() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() })
        }, router: owner) { EmptyView() }
        let root = owner.current
        await root.present(SettingsRoute())
        let old = try #require(owner.engine.defaultSpace.rootPath.last)
        owner.engine.routeScopeDidInstallInView(old)
        let unwind = Task { await owner.current.unwind(to: .root) }
        for _ in 0..<1000 where !owner.engine.defaultSpace.rootPath.isEmpty { await Task.yield() }
        unwind.cancel()
        let request = Task { await root.present(LoginRoute()) }
        for _ in 0..<1000 where owner.engine.pendingRoute == nil { await Task.yield() }
        #expect(owner.engine.pendingRoute != nil)
        owner.engine.routeScopeDidLeaveView(old)
        #expect(await unwind.value)
        await request.value
        #expect(owner.engine.pendingRoute == nil)
        #expect(!owner.engine.isNavigating)
        #expect(owner.engine.defaultSpace.rootPath.last?.route is LoginRoute)
    }

    @Test func cancellingDequeuedRequestStillCancelsItsResolution() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
            Sheet(RouteDestination(DelayedResolutionRoute.self) { _, _ in EmptyView() })
        }, router: owner) { EmptyView() }
        let root = owner.current
        await root.present(SettingsRoute())
        let old = try #require(owner.engine.defaultSpace.rootPath.last)
        owner.engine.routeScopeDidInstallInView(old)
        let unwind = Task { await owner.current.unwind(to: .root) }
        for _ in 0..<1000 where !owner.engine.defaultSpace.rootPath.isEmpty { await Task.yield() }
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
        #expect(owner.engine.defaultSpace.rootPath.isEmpty)
        #expect(!owner.engine.isNavigating)
        await root.present(SettingsRoute())
        #expect(owner.engine.defaultSpace.rootPath.last?.route is SettingsRoute)
    }

    @Test(arguments: [false, true])
    func resolutionFinishingDuringUnwindWaitsWithoutResolvingAgain(cancel: Bool) async throws {
        let router = RouterEngine()
        router.root.defineTestMap(id: nil, selection: nil, definitions: [
            RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, kind: .sheet(priority: .default))._routeDeclarations),
            RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(DelayedResolutionRoute.self) { route, _ in EmptyView() }, kind: .sheet(priority: .default))._routeDeclarations),
        ])
        await router.present(SettingsRoute())
        let old = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(old)
        let gate = ResolutionGate()
        let surviving = Router(engine: router, scope: router.root)
        let request = Task { await surviving.present(DelayedResolutionRoute(gate: gate)) }
        await gate.waitForResolutionToStart()

        let unwind = Task { await router.unwind(to: .root) }
        for _ in 0..<100 where !router.defaultSpace.rootPath.isEmpty { await Task.yield() }
        #expect(router.isNavigating)
        #expect(router.defaultSpace.rootPath.isEmpty)
        gate.release()
        for _ in 0..<100 where router.pendingRoute == nil { await Task.yield() }
        #expect(router.pendingRoute != nil)
        #expect(router.defaultSpace.rootPath.isEmpty)
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
        #expect(router.defaultSpace.rootPath.count == (cancel ? 0 : 1))
        if !cancel {
            #expect(router.defaultSpace.rootPath.last?.route is DelayedResolutionRoute)
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

    func resolveRoute() async -> RouteResolution {
        await gate.wait()
        return .allow
    }

    func destination() -> some View { Text("Delayed resolution") }
}
