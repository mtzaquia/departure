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

import Testing
@testable import Departure

@MainActor
@Suite
struct ActionHookTests {
    @Test func currentScopeInterceptorWinsOverAncestorInterceptor() async {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = ActionRecorder()

        parentScope.installHookDeclarations(
            hookDeclarations: [
                ActionInterceptor(ContextProbeAction.self) { _ in
                    recorder.labels.append("parent")
                }.declaration,
            ]
        )
        childScope.installHookDeclarations(
            hookDeclarations: [
                ActionInterceptor(ContextProbeAction.self) { _ in
                    recorder.labels.append("child")
                }.declaration,
            ]
        )
        router.normalTree.rootPath.scopes = [parentScope, childScope]

        await router.performAction(ContextProbeAction())

        #expect(recorder.labels == ["child"])
    }

    @Test func currentRouteScopeUsesSelectedInstalledBranchScopeForHooks() async {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let recorder = ActionRecorder()

        router.normalTree.rootPath.scopes.append(parentScope)
        parentScope.setActiveBranch(AnyHashable(AppTab.home))

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installHookDeclarations(
            hookDeclarations: [
                ActionInterceptor(ContextProbeAction.self) { invocation in
                    recorder.bools.append((try? await invocation()) ?? false)
                }.declaration,
            ]
        )

        parentScope.registerBranchScope(homeScope, for: AppTab.home)

        await router.performAction(ContextProbeAction())

        #expect(router.currentRouteScope === homeScope)
        #expect(recorder.bools == [true])
    }

    @Test func inactiveBranchHooksDoNotInterceptActions() async {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let recorder = ActionRecorder()

        router.normalTree.rootPath.scopes.append(parentScope)
        parentScope.setActiveBranch(AnyHashable(AppTab.wallet))

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installHookDeclarations(
            hookDeclarations: [
                ActionInterceptor(ContextProbeAction.self) { invocation in
                    recorder.bools.append((try? await invocation()) ?? false)
                }.declaration,
            ]
        )

        parentScope.registerBranchScope(homeScope, for: AppTab.home)

        await router.performAction(ContextProbeAction())

        #expect(router.currentRouteScope === parentScope)
        #expect(recorder.bools.isEmpty)
    }

    @Test func clearingHooksRemovesInterceptorsFromScope() async {
        let router = Router()
        let scope = RouteScope(id: RootRoute().id, route: RootRoute())
        let sourceID = AnyHashable("hooks")
        let recorder = ActionRecorder()

        router.normalTree.rootPath.scopes.append(scope)
        scope.installHookDeclarations(
            sourceID: sourceID,
            hookDeclarations: [
                ActionInterceptor(ContextProbeAction.self) { invocation in
                    recorder.bools.append((try? await invocation()) ?? false)
                }.declaration,
            ]
        )

        await router.performAction(ContextProbeAction())
        scope.uninstallHookDeclarations(sourceID: sourceID)
        await router.performAction(ContextProbeAction())

        #expect(recorder.bools == [true])
    }

    @Test func actionReroutePresentsRouteAndRetriesOnce() async throws {
        let router = Router()
        let recorder = ActionEventRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )

        await router.performAction(ReroutingProbeAction(recorder: recorder))
        await recorder.waitForEvent("reroute")
        let settingsScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(settingsScope)
        await recorder.waitForEvent("ran")

        #expect(await recorder.values() == ["reroute", "ran"])
        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is SettingsRoute)
    }

    @Test func actionRerouteWaitsForInstalledDestinationInterceptorsBeforeRetrying() async throws {
        let router = Router()
        let recorder = ActionEventRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )

        await router.performAction(ReroutingProbeAction(recorder: recorder))
        await recorder.waitForEvent("reroute")
        await Task.yield()

        #expect(await recorder.values() == ["reroute"])

        let settingsScope = try #require(router.normalTree.rootPath.last)
        settingsScope.installHookDeclarations(
            hookDeclarations: [
                ActionInterceptor(ReroutingProbeAction.self) { _ in
                    await recorder.append("intercepted")
                }.declaration,
            ]
        )

        router.routeScopeDidInstallInView(settingsScope)
        await recorder.waitForEvent("intercepted")

        #expect(await recorder.values() == ["reroute", "intercepted"])
    }

    @Test func actionRerouteLoopIsDroppedAfterRetry() async {
        let router = Router()
        let recorder = ActionEventRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )

        await router.performAction(LoopingRerouteAction(recorder: recorder))
        await recorder.waitForEventCount(1)
        if let settingsScope = router.normalTree.rootPath.last {
            router.routeScopeDidInstallInView(settingsScope)
        }
        await recorder.waitForEventCount(2)

        #expect(await recorder.values() == ["attempt", "attempt"])
        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is SettingsRoute)
    }

    @Test func selectedBranchScopeChangesWhenActiveBranchChanges() {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)

        router.normalTree.rootPath.scopes.append(parentScope)
        parentScope.registerBranchScope(homeScope, for: AppTab.home)
        parentScope.registerBranchScope(walletScope, for: AppTab.wallet)

        parentScope.setActiveBranch(AnyHashable(AppTab.home))
        #expect(router.currentRouteScope === homeScope)

        parentScope.setActiveBranch(AnyHashable(AppTab.wallet))
        #expect(router.currentRouteScope === walletScope)

        parentScope.unregisterBranchScope(walletScope, for: AppTab.wallet)
        #expect(router.currentRouteScope === parentScope)
    }
}

private actor ActionEventRecorder {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func values() -> [String] {
        events
    }

    func waitForEvent(_ event: String) async {
        for _ in 0..<100 {
            if events.contains(event) {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func waitForEventCount(_ count: Int) async {
        for _ in 0..<100 where events.count < count {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private struct ReroutingProbeAction: Action {
    let recorder: ActionEventRecorder

    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        if context.isRunning(in: SettingsRoute.self) {
            await recorder.append("ran")
            return
        }

        await recorder.append("reroute")
        throw .reroute(SettingsRoute())
    }
}

private struct LoopingRerouteAction: Action {
    let recorder: ActionEventRecorder

    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        _ = context
        await recorder.append("attempt")
        throw .reroute(SettingsRoute())
    }
}
