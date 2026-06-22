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
    @Test func currentRouteScopeUsesSelectedInstalledBranchScopeForHooks() async {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let recorder = ActionRecorder()

        router.rootPath.scopes.append(parentScope)
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

        router.rootPath.scopes.append(parentScope)
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

        router.rootPath.scopes.append(scope)
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

    @Test func selectedBranchScopeChangesWhenActiveBranchChanges() {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)

        router.rootPath.scopes.append(parentScope)
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
