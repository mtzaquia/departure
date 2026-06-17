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
struct RouterTests {
    @Test func routersCompareByIdentity() {
        let router = Router()
        let sameRouter = router
        let otherRouter = Router()

        #expect(router == sameRouter)
        #expect(router != otherRouter)
        #expect(router.id != otherRouter.id)
    }

    @Test func publicRoutingActionsDispatchThroughRouter() async {
        let router = Router()
        let actionRecorder = AsyncActionRecorder()

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )

        await router.present(HomeDetailRoute())

        #expect(router.path.count == 1)
        #expect(router.path.last?.route is HomeDetailRoute)

        await router.unwind()

        #expect(router.path.isEmpty)

        router.path = [RouteScope(id: RootRoute().id, route: RootRoute())]
        await router.perform(RecordingProbeAction(recorder: actionRecorder))

        #expect(await actionRecorder.values() == [true])
    }

    @Test func publicUnwindReportsMissingTargetBeforeContinuation() async {
        let router = Router()
        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )

        let didUnwind = await router.unwind(to: .id("missing"))
        if didUnwind {
            await router.present(SettingsRoute())
        }

        #expect(didUnwind == false)
        #expect(router.path.isEmpty)
    }

    @Test func routeRequestSelectsInactiveBranchAndWaitsForMountedBranchScope() async {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.wallet)

        router.root.hydrateRoutes(
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

        await router.requestRoute(HomeDetailRoute())

        #expect(selectedTab() == .home)
        #expect(router.path.isEmpty)
        #expect(router.pendingRoute?.match.branchID == AnyHashable(AppTab.home))

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.hydrateRoutes(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)
        router.resumePendingRoute(for: AppTab.home, in: router.root)

        #expect(router.path.count == 1)
        #expect(router.path.last?.route is HomeDetailRoute)
        #expect(router.pendingRoute == nil)
    }

    @Test func unresolvedRoutesAndUndeclaredRoutesAreDropped() async {
        let router = Router()

        await router.requestRoute(DroppedRoute())
        #expect(router.path.isEmpty)

        await router.requestRoute(SettingsRoute())
        #expect(router.path.isEmpty)
    }

    @Test func routeResolutionReroutePresentsResolvedRoute() async {
        let router = Router()

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(LoginRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(ReroutingRoute())

        #expect(router.path.count == 1)
        #expect(router.path.last?.route is LoginRoute)
    }

    @Test func normalPresentationResolvesAndDismissesFromDeclaringScope() async throws {
        let router = Router()

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())

        let presentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .sheet
        ).wrappedValue)

        #expect(presentation.scope === router.path.last)
        #expect(presentation.declaration.routeTypeID == ObjectIdentifier(SettingsRoute.self))

        router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue = nil

        #expect(router.path.isEmpty)
    }

    @Test func repeatedPushOfSameRouteTypeGetsNewPresentationIdentity() async throws {
        let router = Router()

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(HomeDetailRoute())
        let firstPresentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .push
        ).wrappedValue)

        await router.requestRoute(HomeDetailRoute())
        let secondPresentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .push
        ).wrappedValue)

        #expect(firstPresentation.id != secondPresentation.id)
        #expect(firstPresentation.scope !== secondPresentation.scope)
    }

    @Test func replacingMountedPushWaitsForOldScopeToLeaveViewBeforeAppendingNextRoute() async throws {
        let router = Router()

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Push(HomeDetailRoute.self)._routeDeclarations
                    + Push(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(HomeDetailRoute())
        let firstScope = try #require(router.path.last)
        router.routeScopeDidInstallInView(firstScope)

        let requestTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        await Task.yield()

        #expect(router.path.isEmpty)

        router.routeScopeDidLeaveView(firstScope)
        await requestTask.value

        #expect(router.path.count == 1)
        #expect(router.path.last?.route is SettingsRoute)
    }

    @Test func removingPresentedRouteScopeSynchronizesRouterPath() async throws {
        let router = Router()

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.path.last)

        router.removeFromPath(pushedScope)

        #expect(router.path.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .push).wrappedValue == nil)
    }

    @Test func unwindDismissesCurrentRoute() async {
        let router = Router()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.path = [firstScope, secondScope]
        router.highPrioritySegmentStartIndex = 1

        await router.unwindAndWait(to: nil)

        #expect(router.path.count == 1)
        #expect(router.path.last === firstScope)
        #expect(router.highPrioritySegmentStartIndex == nil)
    }

    @Test func unwindToIDKeepsMatchingRouteScope() async {
        let router = Router()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.path = [firstScope, secondScope]
        router.highPrioritySegmentStartIndex = 1

        await router.unwindAndWait(to: .id(RootRoute().id))

        #expect(router.path.count == 1)
        #expect(router.path.last === firstScope)
        #expect(router.highPrioritySegmentStartIndex == nil)
    }

    @Test func unwindToRootClearsPath() async {
        let router = Router()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.path = [firstScope, secondScope]
        router.highPrioritySegmentStartIndex = 1

        await router.unwindAndWait(to: .root)

        #expect(router.path.isEmpty)
        #expect(router.highPrioritySegmentStartIndex == nil)
    }

    @Test func sequentialUnwindThenPresentWaitsForMountedRouteScopeToLeaveView() async {
        let router = Router()
        let loginScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
            ]
        )

        router.path = [loginScope]
        router.highPrioritySegmentStartIndex = 0
        router.routeScopeDidInstallInView(loginScope)

        let unwindTask = Task {
            guard await router.unwind(to: nil) else {
                return
            }

            await router.present(SettingsRoute())
        }

        await Task.yield()

        #expect(router.path.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        _ = await unwindTask.value

        #expect(router.path.count == 1)
        #expect(router.path.last?.route is SettingsRoute)
    }

    @Test func sequentialUnwindThenPresentCutsPathBeforeWaitingForAllRemovedScopes() async {
        let router = Router()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let thirdScope = RouteScope(id: AlertRoute().id, route: AlertRoute())

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
            ]
        )

        router.path = [firstScope, secondScope, thirdScope]
        router.routeScopeDidInstallInView(firstScope)
        router.routeScopeDidInstallInView(secondScope)
        router.routeScopeDidInstallInView(thirdScope)

        let unwindTask = Task {
            guard await router.unwind(to: .root) else {
                return
            }

            await router.present(SettingsRoute())
        }

        await Task.yield()

        #expect(router.path.isEmpty)

        router.routeScopeDidLeaveView(firstScope)
        router.routeScopeDidLeaveView(secondScope)
        await Task.yield()

        #expect(router.path.isEmpty)

        router.routeScopeDidLeaveView(thirdScope)
        _ = await unwindTask.value

        #expect(router.path.count == 1)
        #expect(router.path.last?.route is SettingsRoute)
    }

    @Test func unwindPreservesDescendantPresentationBindingsUntilAncestorUnmounts() async {
        let router = Router()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let profileScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(RootRoute.self, providesNavigation: false)._routeDeclarations),
            ]
        )
        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        homeScope.hydrateRoutes(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(LoginRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        router.path = [landingScope, profileScope]
        router.routeScopeDidInstallInView(landingScope)
        router.routeScopeDidInstallInView(profileScope)

        let unwindTask = Task {
            await router.unwindAndWait(to: .root)
        }

        await Task.yield()

        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue != nil)

        router.routeScopeDidLeaveView(profileScope)
        router.routeScopeDidLeaveView(landingScope)
        _ = await unwindTask.value

        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func branchLocalPresentationOnlyDrivesWhenParentBranchIsActive() async {
        let router = Router()
        let (selection, _) = tabSelection(.home)

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: Branch(AppTab.home) {
                Push(HomeDetailRoute.self)
            }.routeScopeDeclarations
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.hydrateRoutes(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)

        await router.requestRoute(HomeDetailRoute())

        #expect(router.routePresentationBinding(from: homeScope, matching: .push).wrappedValue != nil)

        router.root.setActiveBranch(AnyHashable(AppTab.wallet))

        #expect(router.routePresentationBinding(from: homeScope, matching: .push).wrappedValue == nil)
    }

    @Test func highPriorityPresentationUsesActiveLocalBranchScope() async {
        let router = Router()
        let (selection, _) = tabSelection(.home)

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: Branch(AppTab.home) {
                Cover(LoginRoute.self, priority: .high)
            }.routeScopeDeclarations
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.hydrateRoutes(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)

        await router.requestRoute(LoginRoute())

        let presentation = router.highPriorityRoutePresentationBinding(
            matching: .cover(.slide)
        ).wrappedValue

        #expect(presentation?.scope === router.path.last)
        #expect(presentation?.declaration.routeTypeID == ObjectIdentifier(LoginRoute.self))
    }

    @Test func highPriorityPresentationCanUseContainerDeclarationFromActiveLocalBranch() async {
        let router = Router()
        let (selection, _) = tabSelection(.home)

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Cover(LoginRoute.self, priority: .high)
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Sheet(SettingsRoute.self)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.hydrateRoutes(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)

        await router.requestRoute(LoginRoute())

        let presentation = router.highPriorityRoutePresentationBinding(
            matching: .cover(.slide)
        ).wrappedValue

        #expect(presentation?.scope === router.path.last)
        #expect(presentation?.declaration.routeTypeID == ObjectIdentifier(LoginRoute.self))
    }

    @Test func ancestorHighPriorityDeclarationReplacesActiveHighPriorityRoute() async {
        let router = Router()

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations
                        + Cover(AlertRoute.self, priority: .high, transition: .fade, providesNavigation: false)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(LoginRoute())
        await router.requestRoute(AlertRoute())

        let presentation = router.highPriorityRoutePresentationBinding(
            matching: .cover(.fade)
        ).wrappedValue

        #expect(router.path.count == 1)
        #expect(router.path.last?.route is AlertRoute)
        #expect(presentation?.scope === router.path.last)
        #expect(presentation?.declaration.routeTypeID == ObjectIdentifier(AlertRoute.self))
    }
}
