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
struct IOS17NavigationStackPushWorkaroundTests {
    @Test func installedPushDismissalWaitsForViewExitBeforeTrimmingPath() async throws {
        let router = makeRouterWithWorkaround()

        installPushDeclaration(in: router)
        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(pushedScope)

        let presentation = router.routePresentationBinding(from: router.root, matching: .push)
        presentation.wrappedValue = nil
        await Task.yield()

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === pushedScope)
        #expect(presentation.wrappedValue?.scope === pushedScope)

        router.routeScopeDidLeaveView(pushedScope)
        for _ in 0..<10 where router.normalTree.rootPath.isEmpty == false {
            await Task.yield()
        }

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(presentation.wrappedValue == nil)
    }

    @Test func disabledWorkaroundRetainsImmediatePushDismissalSemantics() async throws {
        let router = Router()
        router.ios17NavigationStackPushWorkaround = nil

        installPushDeclaration(in: router)
        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(pushedScope)

        router.routePresentationBinding(from: router.root, matching: .push).wrappedValue = nil

        #expect(router.normalTree.rootPath.isEmpty)
    }

    @Test func transientViewReinstallationDoesNotCompleteDeferredPushDismissal() async throws {
        let router = makeRouterWithWorkaround()

        installPushDeclaration(in: router)
        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(pushedScope)

        let presentation = router.routePresentationBinding(from: router.root, matching: .push)
        presentation.wrappedValue = nil
        router.routeScopeDidLeaveView(pushedScope)
        router.routeScopeDidInstallInView(pushedScope)
        for _ in 0..<3 {
            await Task.yield()
        }

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === pushedScope)
        #expect(presentation.wrappedValue?.scope === pushedScope)
    }

    @Test func routePathMutationInvalidatesDismissalWriteBackBeforeLaterViewExit() async throws {
        let router = makeRouterWithWorkaround()

        installPushDeclaration(in: router)
        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(pushedScope)

        let presentation = router.routePresentationBinding(from: router.root, matching: .push)
        presentation.wrappedValue = nil
        let laterScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        router.mutateRouteGraph {
            router.normalTree.rootPath.append(laterScope)
        }
        router.routeScopeDidLeaveView(pushedScope)

        #expect(router.normalTree.rootPath.count == 2)
        #expect(router.normalTree.rootPath.first === pushedScope)
        #expect(router.normalTree.rootPath.last === laterScope)
        #expect(presentation.wrappedValue?.scope === pushedScope)
    }

    @Test func unrelatedGraphMutationPreservesPendingPushDismissal() async throws {
        let router = makeRouterWithWorkaround()

        installPushDeclaration(in: router)
        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(pushedScope)

        let presentation = router.routePresentationBinding(from: router.root, matching: .push)
        presentation.wrappedValue = nil

        let unrelatedBranch = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let unrelatedScope = RouteScope(id: TransactionRoute().id, route: TransactionRoute())
        router.mutateRouteGraph {
            router.root.registerBranchScope(unrelatedBranch, for: AppTab.wallet)
            unrelatedBranch.path.append(unrelatedScope)
        }

        router.routeScopeDidLeaveView(pushedScope)
        for _ in 0..<10 where router.normalTree.rootPath.isEmpty == false {
            await Task.yield()
        }

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(unrelatedBranch.path.last === unrelatedScope)
    }

    @Test func branchMutationInvalidatesDismissalWriteBackAfterSwitchingBack() async throws {
        let router = makeRouterWithWorkaround()
        let (selection, _) = tabSelection(.home)

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Push(HomeDetailRoute.self)
                    }
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Push(TransactionRoute.self)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)
        router.root.registerBranchScope(
            RouteScope(id: AnyHashable(AppTab.wallet), route: nil),
            for: AppTab.wallet
        )

        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(homeScope.path.last)
        router.routeScopeDidInstallInView(pushedScope)

        let presentation = router.routePresentationBinding(from: homeScope, matching: .push)
        presentation.wrappedValue = nil
        router.mutateRouteGraph {
            router.root.setActiveBranch(AnyHashable(AppTab.wallet))
        }
        router.mutateRouteGraph {
            router.root.setActiveBranch(AnyHashable(AppTab.home))
        }
        router.routeScopeDidLeaveView(pushedScope)

        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last === pushedScope)
        #expect(presentation.wrappedValue?.scope === pushedScope)
    }

    @Test func viewExitWatchdogForcesReconciliationWhenLifecycleCallbackIsMissing() async {
        let workaround = IOS17NavigationStackPushWorkaround()
        workaround.viewExitTimeout = .milliseconds(10)
        let router = Router()
        router.ios17NavigationStackPushWorkaround = workaround
        let scope = RouteScope(id: HomeDetailRoute().id, route: HomeDetailRoute())
        router.routeScopeDidInstallInView(scope)

        await router.waitForRouteScopesToLeaveView([scope])

        #expect(scope.isInstalledInView == false)
    }

    private func makeRouterWithWorkaround() -> Router {
        let router = Router()
        router.ios17NavigationStackPushWorkaround = IOS17NavigationStackPushWorkaround()
        return router
    }

    private func installPushDeclaration(in router: Router) {
        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )
    }
}
