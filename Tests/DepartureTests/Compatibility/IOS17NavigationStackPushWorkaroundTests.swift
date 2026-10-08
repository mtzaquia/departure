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
    @Test func factoryOnlyEnablesTheWorkaroundOnIOS17() {
        #if os(iOS)
        if #available(iOS 18, *) {
            #expect(IOS17NavigationStackPushWorkaroundFactory.makeForCurrentPlatform() == nil)
        } else {
            #expect(IOS17NavigationStackPushWorkaroundFactory.makeForCurrentPlatform() != nil)
        }
        #else
        #expect(IOS17NavigationStackPushWorkaroundFactory.makeForCurrentPlatform() == nil)
        #endif
    }

    @Test func pushHostIdentityChangesOnlyForConcurrentBranchSelection() {
        let router = makeRouterWithWorkaround()
        let workaround = IOS17NavigationStackPushWorkaround()
        router.root.define(RootRouteMap { Branches(concurrent: true) {
            Branch(AppTab.home) {}; Branch(AppTab.wallet) {}
        } }.declarations)

        #expect(workaround.pushHostIdentity(for: AppTab.home, in: router.root, router: router))
        #expect(!workaround.pushHostIdentity(for: AppTab.wallet, in: router.root, router: router))

        router.root.define(RootRouteMap { Branches {
            Branch(AppTab.home) {}; Branch(AppTab.wallet) {}
        } }.declarations)
        #expect(workaround.pushHostIdentity(for: AppTab.wallet, in: router.root, router: router))
    }

    @Test func installedPushDismissalWaitsForViewExitBeforeTrimmingPath() async throws {
        let router = makeRouterWithWorkaround()
        let presentationHostID = RoutePresentationHostID()

        installPushDeclaration(in: router, hostedBy: presentationHostID)
        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(pushedScope)

        let presentation = router.routePresentationBinding(
            from: router.root,
            matching: .push,
            hostedBy: presentationHostID
        )
        presentation.wrappedValue = nil
        await Task.yield()

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === pushedScope)
        #expect(presentation.wrappedValue?.scope === pushedScope)

        router.routeScopeDidLeaveView(pushedScope)
        for _ in 0..<10 where router.defaultSpace.rootPath.isEmpty == false {
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(presentation.wrappedValue == nil)
    }

    @Test func pushWriteBackBeforeFirstMountDoesNotRemovePendingDestination() async throws {
        let router = makeRouterWithWorkaround()
        installPushDeclaration(in: router)
        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.defaultSpace.rootPath.last)
        let presentation = router.routePresentationBinding(from: router.root, matching: .push)

        presentation.wrappedValue = nil

        #expect(router.defaultSpace.rootPath.last === pushedScope)
        #expect(presentation.wrappedValue?.scope === pushedScope)
        #expect(pushedScope.hasEverInstalled == false)
    }

    @Test func disabledWorkaroundRetainsImmediatePushDismissalSemantics() async throws {
        let router = RouterEngine()
        router.ios17NavigationStackPushWorkaround = nil

        installPushDeclaration(in: router)
        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(pushedScope)

        router.routePresentationBinding(from: router.root, matching: .push).wrappedValue = nil

        #expect(router.defaultSpace.rootPath.isEmpty)
    }

    @Test func replacementFromPushedChildContinuesAfterItsOwnStagedPop() async throws {
        let owner = RootRouter()
        owner.engine.ios17NavigationStackPushWorkaround = IOS17NavigationStackPushWorkaround()
        _ = WithRouter(routes: RootRouteMap {
            Replace(RouteDestination(CompatSelection.self) { _, _ in EmptyView() }) {
                Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() })
            }
        }, router: owner) { EmptyView() }
        await owner.current.present(CompatSelection(number: 1))
        await owner.current.present(HomeDetailRoute())
        let child = try #require(owner.engine.defaultSpace.rootPath.last)
        let childRouter = owner.current
        let hostID = UUID()
        owner.engine.hostDidAttach(child, view: nil, id: hostID)

        let replacement = Task { await childRouter.present(CompatSelection(number: 2)) }
        for _ in 0..<1000 where owner.engine.defaultSpace.rootPath.count != 1 { await Task.yield() }
        #expect(owner.engine.defaultSpace.rootPath.count == 1)
        owner.engine.hostDidDetach(child, id: hostID)
        await replacement.value

        #expect(owner.engine.defaultSpace.rootPath.count == 1)
        #expect((owner.engine.defaultSpace.rootPath.last?.route as? CompatSelection)?.number == 2)
        await childRouter.present(CompatSelection(number: 3))
        #expect((owner.engine.defaultSpace.rootPath.last?.route as? CompatSelection)?.number == 2)
    }

    @Test func transientViewReinstallationDoesNotCompleteDeferredPushDismissal() async throws {
        let router = makeRouterWithWorkaround()

        installPushDeclaration(in: router)
        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(pushedScope)

        let presentation = router.routePresentationBinding(from: router.root, matching: .push)
        presentation.wrappedValue = nil
        router.routeScopeDidLeaveView(pushedScope)
        router.routeScopeDidInstallInView(pushedScope)
        for _ in 0..<3 {
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === pushedScope)
        #expect(presentation.wrappedValue?.scope === pushedScope)
    }

    @Test func routePathMutationInvalidatesDismissalWriteBackBeforeLaterViewExit() async throws {
        let router = makeRouterWithWorkaround()

        installPushDeclaration(in: router)
        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(pushedScope)

        let presentation = router.routePresentationBinding(from: router.root, matching: .push)
        presentation.wrappedValue = nil
        let laterScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        router.mutateRouteGraph {
            router.defaultSpace.rootPath.append(laterScope)
        }
        router.routeScopeDidLeaveView(pushedScope)

        #expect(router.defaultSpace.rootPath.count == 2)
        #expect(router.defaultSpace.rootPath.first === pushedScope)
        #expect(router.defaultSpace.rootPath.last === laterScope)
        #expect(presentation.wrappedValue?.scope === pushedScope)
    }

    @Test func unrelatedGraphMutationPreservesPendingPushDismissal() async throws {
        let router = makeRouterWithWorkaround()

        installPushDeclaration(in: router)
        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(pushedScope)

        let presentation = router.routePresentationBinding(from: router.root, matching: .push)
        presentation.wrappedValue = nil

        let unrelatedBranch = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let unrelatedScope = RouteScope(id: TransactionRoute().id, route: TransactionRoute())
        router.mutateRouteGraph {
            router.root.attachTestBranch(unrelatedBranch, for: AppTab.wallet)
            unrelatedBranch.path.append(unrelatedScope)
        }

        router.routeScopeDidLeaveView(pushedScope)
        for _ in 0..<10 where router.defaultSpace.rootPath.isEmpty == false {
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(unrelatedBranch.path.last === unrelatedScope)
    }

    @Test func branchMutationInvalidatesDismissalWriteBackAfterSwitchingBack() async throws {
        let router = makeRouterWithWorkaround()
        let (selection, _) = tabSelection(.home)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, kind: .push)
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, kind: .push)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, kind: .push)._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)
        router.root.attachTestBranch(
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
        let router = RouterEngine()
        router.ios17NavigationStackPushWorkaround = workaround
        let scope = RouteScope(id: HomeDetailRoute().id, route: HomeDetailRoute())
        router.routeScopeDidInstallInView(scope)

        await router.waitForRouteScopesToLeaveView([scope])

        #expect(scope.isInstalledInView == false)
    }

    @Test func staleViewExitWatchdogCannotDetachAReplacementHost() async throws {
        let workaround = IOS17NavigationStackPushWorkaround()
        workaround.viewExitTimeout = .milliseconds(10)
        let router = RouterEngine()
        router.ios17NavigationStackPushWorkaround = workaround
        installPushDeclaration(in: router)
        await router.present(HomeDetailRoute())
        let scope = try #require(router.defaultSpace.rootPath.last)
        let first = UUID(), replacement = UUID()
        router.hostDidAttach(scope, view: nil, id: first)
        workaround.startViewExitWatchdogs(for: [scope], in: router)
        await Task.yield()
        workaround.viewExitTimeout = .milliseconds(100)
        router.hostDidAttach(scope, view: nil, id: replacement)
        try await Task.sleep(for: .milliseconds(50))
        #expect(scope.isInstalledInView)
        #expect(scope.hostID == replacement)
        router.hostDidDetach(scope, id: replacement)
        #expect(!scope.isInstalledInView)
    }

    @Test func replacementHostKeepsTheMissingExitCallbackFallback() async throws {
        let workaround = IOS17NavigationStackPushWorkaround()
        workaround.viewExitTimeout = .milliseconds(10)
        let router = RouterEngine()
        router.ios17NavigationStackPushWorkaround = workaround
        installPushDeclaration(in: router)
        await router.present(HomeDetailRoute())
        let scope = try #require(router.defaultSpace.rootPath.last)
        router.hostDidAttach(scope, view: nil, id: UUID())
        let wait = Task { await router.waitForRouteScopesToLeaveView([scope]) }
        await Task.yield()
        router.hostDidAttach(scope, view: nil, id: UUID())
        await wait.value
        #expect(!scope.isInstalledInView)
    }

    private func makeRouterWithWorkaround() -> RouterEngine {
        let router = RouterEngine()
        router.ios17NavigationStackPushWorkaround = IOS17NavigationStackPushWorkaround()
        return router
    }

    private func installPushDeclaration(
        in router: RouterEngine,
        hostedBy presentationHostID: RoutePresentationHostID? = nil
    ) {
        if let presentationHostID {
            router.root.bindRoutingHost(presentationHostID, automatic: false, environment: router.root.sourceEnvironment)
        }
        let declarations = AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, kind: .push)._routeDeclarations
        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: declarations),
            ]
        )
    }
}

private struct CompatSelection: Route, Equatable {
    let number: Int
}
