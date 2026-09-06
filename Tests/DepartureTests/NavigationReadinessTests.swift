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
    @Test(arguments: [false, true])
    func resolutionFinishingDuringUnwindWaitsWithoutResolvingAgain(cancel: Bool) async throws {
        let router = Router()
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

    func resolveRoute() async -> RouteResolution {
        await gate.wait()
        return .allow
    }

    func destination() -> some View { Text("Delayed resolution") }
}
