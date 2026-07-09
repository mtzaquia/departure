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

import Foundation
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

    @Test func routeEqualityUsesEquatableConformanceWhenAvailable() {
        #expect(EquatableOnlyRoute(value: 1)._isEqual(to: EquatableOnlyRoute(value: 1)))
        #expect(EquatableOnlyRoute(value: 1)._isEqual(to: EquatableOnlyRoute(value: 2)) == false)
    }

    @Test func routeEqualityFallsBackToProtocolEqualityForNonEquatableRoutes() {
        #expect(ProtocolEqualOnlyRoute(value: 1)._isEqual(to: ProtocolEqualOnlyRoute(value: 1)))
        #expect(ProtocolEqualOnlyRoute(value: 1)._isEqual(to: ProtocolEqualOnlyRoute(value: 2)) == false)
    }

    @Test func publicRoutingActionsDispatchThroughRouter() async {
        let router = Router()
        let actionRecorder = AsyncActionRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )

        await router.present(HomeDetailRoute())

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is HomeDetailRoute)

        await router.unwind(to: nil)

        #expect(router.normalTree.rootPath.isEmpty)

        router.normalTree.rootPath.scopes = [RouteScope(id: RootRoute().id, route: RootRoute())]
        await router.perform(RecordingProbeAction(recorder: actionRecorder))

        #expect(await actionRecorder.values() == [true])
    }

    @Test func routePhaseTracksCurrentRouteScope() {
        let router = Router()
        let routeScope = RouteScope(id: RootRoute().id, route: RootRoute())

        #expect(router.routePhase(for: router.root) == .active)
        #expect(router.routePhase(for: routeScope) == .inactive)

        router.mutateRouteGraph {
            router.normalTree.rootPath.scopes = [routeScope]
        }

        #expect(router.routePhase(for: router.root) == .active)
        #expect(router.routePhase(for: routeScope) == .active)
    }

    @Test func routePhaseTreatsActiveBranchRootAsCurrentScope() {
        let router = Router()
        let containerScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)

        router.mutateRouteGraph {
            router.normalTree.rootPath.scopes = [containerScope]
            containerScope.setActiveBranch(AnyHashable(AppTab.home))
            containerScope.registerBranchScope(homeScope, for: AppTab.home)
            containerScope.registerBranchScope(walletScope, for: AppTab.wallet)
        }

        #expect(router.routePhase(for: containerScope) == .active)
        #expect(router.routePhase(for: homeScope) == .active)
        #expect(router.routePhase(for: walletScope) == .inactive)

        let detailScope = RouteScope(id: HomeDetailRoute().id, route: HomeDetailRoute())
        router.mutateRouteGraph {
            homeScope.path.scopes = [detailScope]
        }

        #expect(router.routePhase(for: homeScope) == .active)
        #expect(router.routePhase(for: detailScope) == .active)
    }

    @Test func routePhaseTracksActiveBranchChanges() {
        let router = Router()
        let containerScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)

        router.mutateRouteGraph {
            router.normalTree.rootPath.scopes = [containerScope]
            containerScope.setActiveBranch(AnyHashable(AppTab.home))
            containerScope.registerBranchScope(homeScope, for: AppTab.home)
            containerScope.registerBranchScope(walletScope, for: AppTab.wallet)
        }

        router.mutateRouteGraph {
            containerScope.setActiveBranch(AnyHashable(AppTab.wallet))
        }

        #expect(router.routePhase(for: homeScope) == .inactive)
        #expect(router.routePhase(for: walletScope) == .active)
    }

    @Test func publicUnwindReportsMissingTargetBeforeContinuation() async {
        let router = Router()
        router.root.installRouteDeclarations(
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
        #expect(router.normalTree.rootPath.isEmpty)
    }

    @Test func routeRequestSelectsInactiveBranchAndWaitsForInstalledBranchScope() async {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.wallet)

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

        await router.requestRoute(HomeDetailRoute())

        #expect(selectedTab() == .home)
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.pendingRoute?.append?.match.branchID == AnyHashable(AppTab.home))

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)
        router.resumePendingRoute(for: AppTab.home, in: router.root)

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(router.pendingRoute == nil)
    }

    @Test func clearingRoutesRestoresInitialScopeIdentity() {
        let scope = RouteScope(id: AnyHashable("initial"), route: nil)
        let sourceID = AnyHashable("routes")

        scope.installRouteDeclarations(
            sourceID: sourceID,
            id: AnyHashable("explicit"),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )

        #expect(scope.id == AnyHashable("explicit"))

        scope.uninstallRouteDeclarations(sourceID: sourceID)

        #expect(scope.id == AnyHashable("initial"))
        #expect(scope.activeBranch == AnyHashable("initial"))
        #expect(scope.firstRouteAttachment(for: HomeDetailRoute.self) == nil)
    }

    @Test func branchScopeChecksLocalDeclarationsBeforeAdoptedDeclarations() async {
        let router = Router()
        let (selection, _) = tabSelection(.home)

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Push(HomeDetailRoute.self)
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable("home-root"), route: nil)
        homeScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)

        #expect(homeScope.firstRouteAttachment(for: HomeDetailRoute.self)?.declaration.presentationKind == .push)
        #expect(homeScope.firstRouteAttachment(for: SettingsRoute.self)?.declaration.presentationKind == .sheet)
        #expect(homeScope.id == AnyHashable("home-root"))

        await router.requestRoute(HomeDetailRoute())

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)

        await router.unwind(to: .nearestBranch)
        await router.requestRoute(SettingsRoute())

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue != nil)
    }

    @Test func routeRequestFromInstalledInactiveBranchWaitsForTargetBranchScope() async {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.wallet)

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

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(TransactionRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())

        #expect(selectedTab() == .home)
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.pendingRoute?.append?.match.branchID == AnyHashable(AppTab.home))

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)
        router.resumePendingRoute(for: AppTab.home, in: router.root)

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(router.pendingRoute == nil)
    }

    @Test func inactiveBranchCoverRequestActivatesBranchAndPresentsFromAdoptedScope() async throws {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.wallet)

        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        router.normalTree.rootPath.scopes = [landingScope]

        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Cover(MessageRoute.self, transition: .fade, providesNavigation: false)
                    }
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(MessageRoute.self, transition: .fade, providesNavigation: false)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        let settingsScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        settingsScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(settingsScope, for: AppTab.wallet)

        await router.requestRoute(MessageRoute())

        #expect(selectedTab() == .home)
        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.pendingRoute?.append?.match.branchID == AnyHashable(AppTab.home))

        router.resumePendingRoute(for: AppTab.home, in: landingScope)

        #expect(router.normalTree.rootPath.count == 1)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is MessageRoute)
        #expect(router.pendingRoute == nil)

        let presentation = try #require(router.routePresentationBinding(
            from: homeScope,
            matching: .cover(.fade)
        ).wrappedValue)
        #expect(presentation.scope === homeScope.path.last)
    }

    @Test func branchContainerCoverPresentsFromContainerWithoutClearingBranchPath() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.wallet)

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Cover(MessageRoute.self)
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Push(TransactionRoute.self)
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(TransactionRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(TransactionRoute())
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)

        await router.requestRoute(MessageRoute())

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is MessageRoute)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)

        let presentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .cover(.slide)
        ).wrappedValue)
        #expect(presentation.scope === router.normalTree.rootPath.last)
        #expect(router.routePresentationBinding(from: walletScope, matching: .cover(.slide)).wrappedValue == nil)

        router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue = nil

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)
    }

    @Test func branchContainerSheetDoesNotReappearAfterBranchSwitchDismissal() async throws {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Sheet(MessageRoute.self)
                ),
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
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(TransactionRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(MessageRoute())

        #expect(selectedTab() == .wallet)
        #expect(router.normalTree.rootPath.count == 2)
        #expect(router.normalTree.rootPath.last?.route is MessageRoute)
        #expect(landingScope.path.isEmpty)
        #expect(walletScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue?.scope === router.normalTree.rootPath.last)

        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue = nil

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === landingScope)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)

        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))

        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)
        #expect(walletScope.path.isEmpty)
    }

    @Test func branchPushRequestDismissesTopLevelModalBeforeAppending() async throws {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Sheet(MessageRoute.self)
                ),
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
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        await router.requestRoute(MessageRoute())
        let modalScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(modalScope)

        let requestTask = Task {
            await router.requestRoute(HomeDetailRoute())
        }

        for _ in 0..<10 {
            if router.normalTree.rootPath.count == 1,
               router.normalTree.rootPath.last === landingScope,
               homeScope.path.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(selectedTab() == .home)
        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === landingScope)
        #expect(homeScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(modalScope)
        await requestTask.value

        #expect(selectedTab() == .home)
        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === landingScope)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .push).wrappedValue?.scope === homeScope.path.last)
    }

    @Test func localSheetDeclarationWinsOverTopLevelDeclarationForSameRoute() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.home)

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Sheet(MessageRoute.self)
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)

        await router.requestRoute(SettingsRoute())

        let settingsScope = try #require(homeScope.path.last)
        settingsScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(MessageRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(MessageRoute())

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first?.route is SettingsRoute)
        #expect(homeScope.path.last?.route is MessageRoute)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .sheet).wrappedValue?.scope === homeScope.path.last)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)
    }

    @Test func localSheetOnPushedScopeWinsOverContainerLevelDeclaration() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Sheet(MessageRoute.self)
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations.drivingPresentation(true)),
            ]
        )
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(walletScope.path.last)

        // Toggle OFF: the pushed scope declares nothing, so the container-level sheet hosts.
        await router.requestRoute(MessageRoute())
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue?.scope === router.normalTree.rootPath.last)
        #expect(router.routePresentationBinding(from: walletScope, matching: .sheet).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .sheet).wrappedValue == nil)

        router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue = nil
        #expect(walletScope.path.last === settingsScope)

        // Toggle ON: the pushed scope now declares the same route locally and must win.
        settingsScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(MessageRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(MessageRoute())
        #expect(router.routePresentationBinding(from: settingsScope, matching: .sheet).wrappedValue?.scope === walletScope.path.last)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: walletScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func presentingTopLevelSheetOverBranchLocalSheetReplacesItRatherThanStacking() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Sheet(MessageRoute.self) // top-level (shared) sheet
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Sheet(SettingsRoute.self) // branch-local sheet
                    }
                )
            )
        )

        // The branch scope adopts both the top-level and the branch-local sheet (mirrors `.routeBranch`).
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Sheet(MessageRoute.self)._routeDeclarations.drivingPresentation(true)
                    + Sheet(SettingsRoute.self)._routeDeclarations.drivingPresentation(true)
                ),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        // Present the branch-local sheet.
        await router.requestRoute(SettingsRoute())
        #expect(homeScope.path.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue?.scope.route is SettingsRoute)

        // Present the top-level sheet from within the branch-local presentation: it must replace the
        // branch-local sheet, not stack above it.
        await router.requestRoute(MessageRoute())
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue?.scope.route is MessageRoute)
        #expect(homeScope.path.scopes.contains { $0.route is SettingsRoute } == false)

        // Dismissing the top-level sheet returns to no presentation — the branch-local sheet must
        // not reappear.
        router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue = nil
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
        #expect(homeScope.path.isEmpty)
    }

    @Test func presentingTopLevelCoverOverBranchLocalSheetReplacesItAcrossModalKinds() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Cover(MessageRoute.self, transition: .fade, providesNavigation: false) // top-level cover
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Sheet(SettingsRoute.self) // branch-local sheet
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(MessageRoute.self, transition: .fade, providesNavigation: false)._routeDeclarations.drivingPresentation(true)
                    + Sheet(SettingsRoute.self)._routeDeclarations.drivingPresentation(true)
                ),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        // Present the branch-local sheet.
        await router.requestRoute(SettingsRoute())
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue?.scope.route is SettingsRoute)

        // A scope hosts one modal regardless of kind: presenting a cover must replace the sheet,
        // not stack a second modal the host cannot show.
        await router.requestRoute(MessageRoute())
        #expect(router.routePresentationBinding(from: homeScope, matching: .cover(.fade)).wrappedValue?.scope.route is MessageRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
        #expect(homeScope.path.scopes.contains { $0.route is SettingsRoute } == false)

        // Dismissing the cover returns to no presentation — the sheet must not reappear.
        router.routePresentationBinding(from: homeScope, matching: .cover(.fade)).wrappedValue = nil
        #expect(homeScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func replacingTopLevelCoverPreservesActiveBranchPushStack() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Cover(LoginRoute.self)
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Cover(MessageRoute.self)
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(LoginRoute.self)._routeDeclarations.drivingPresentation(true)
                    + Cover(MessageRoute.self)._routeDeclarations.drivingPresentation(true)
                    + Push(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        await router.requestRoute(SettingsRoute())
        #expect(homeScope.path.last?.route is SettingsRoute)

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(homeScope.path.last)
        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first?.route is SettingsRoute)
        #expect(loginScope.route is LoginRoute)
        router.routeScopeDidInstallInView(loginScope)

        let replacementTask = Task {
            await router.requestRoute(MessageRoute())
        }

        for _ in 0..<10 {
            if homeScope.path.count == 1 {
                break
            }
            await Task.yield()
        }

        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .cover(.slide)).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        await replacementTask.value

        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first?.route is SettingsRoute)
        #expect(homeScope.path.last?.route is MessageRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .cover(.slide)).wrappedValue?.scope.route is MessageRoute)
    }

    @Test func ancestorCoverRemovesDescendantLocalSheetAndPreservesPushStack() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Cover(LoginRoute.self)
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Cover(MessageRoute.self)
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(LoginRoute.self)._routeDeclarations.drivingPresentation(true)
                    + Cover(MessageRoute.self)._routeDeclarations.drivingPresentation(true)
                    + Push(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(homeScope.path.last)
        settingsScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(TransactionRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(TransactionRoute())
        let sheetScope = try #require(homeScope.path.last)
        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first?.route is SettingsRoute)
        #expect(sheetScope.route is TransactionRoute)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .sheet).wrappedValue?.scope === sheetScope)
        router.routeScopeDidInstallInView(sheetScope)

        let coverTask = Task {
            await router.requestRoute(LoginRoute())
        }

        for _ in 0..<10 {
            if homeScope.path.count == 1 {
                break
            }
            await Task.yield()
        }

        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last === settingsScope)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(sheetScope)
        await coverTask.value

        let coverScope = try #require(homeScope.path.last)
        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first === settingsScope)
        #expect(coverScope.route is LoginRoute)
        #expect(homeScope.path.scopes.contains { $0.route is TransactionRoute } == false)
        #expect(router.routePresentationBinding(from: homeScope, matching: .cover(.slide)).wrappedValue?.scope === coverScope)
        router.routeScopeDidInstallInView(coverScope)

        let replacementTask = Task {
            await router.requestRoute(MessageRoute())
        }

        for _ in 0..<10 {
            if homeScope.path.count == 1 {
                break
            }
            await Task.yield()
        }

        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last === settingsScope)
        #expect(router.routePresentationBinding(from: homeScope, matching: .cover(.slide)).wrappedValue == nil)

        router.routeScopeDidLeaveView(coverScope)
        await replacementTask.value

        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first === settingsScope)
        #expect(homeScope.path.last?.route is MessageRoute)
        #expect(homeScope.path.scopes.contains { $0.route is TransactionRoute } == false)

        router.routePresentationBinding(from: homeScope, matching: .cover(.slide)).wrappedValue = nil

        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last === settingsScope)
        #expect(homeScope.path.scopes.contains { $0.route is TransactionRoute } == false)
    }

    @Test func crawlBackBranchSwitchWaitsForAdoptedLocalDeclarationBeforePresenting() async throws {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.home)

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

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        router.root.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        let homeDetailScope = try #require(homeScope.path.last)
        router.routeScopeDidInstallInView(homeDetailScope)

        let requestTask = Task {
            await router.requestRoute(TransactionRoute())
        }

        await Task.yield()

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(homeScope.path.last === homeDetailScope)

        router.routeScopeDidLeaveView(homeDetailScope)
        await requestTask.value

        #expect(selectedTab() == .wallet)
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.pendingRoute?.append?.match.branchID == AnyHashable(AppTab.wallet))

        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(TransactionRoute.self)._routeDeclarations),
            ]
        )
        router.resumePendingRoute(for: AppTab.wallet, in: router.root)

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)
        #expect(router.pendingRoute == nil)
        #expect(router.routePresentationBinding(from: walletScope, matching: .push).wrappedValue != nil)
    }

    @Test func unresolvedRoutesAndUndeclaredRoutesAreDropped() async {
        let router = Router()

        await router.requestRoute(DroppedRoute())
        #expect(router.normalTree.rootPath.isEmpty)

        await router.requestRoute(SettingsRoute())
        #expect(router.normalTree.rootPath.isEmpty)
    }

    @Test func routeResolutionReroutePresentsResolvedRoute() async {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(LoginRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(ReroutingRoute())

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is LoginRoute)
    }

    @Test func normalPresentationResolvesAndDismissesFromDeclaringScope() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
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

        #expect(presentation.scope === router.normalTree.rootPath.last)
        #expect(presentation.declaration.routeTypeID == ObjectIdentifier(SettingsRoute.self))

        router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue = nil

        #expect(router.normalTree.rootPath.isEmpty)
    }

    @Test func repeatedPresentationOfEquivalentRouteKeepsPresentationIdentity() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
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

        #expect(router.normalTree.rootPath.count == 1)
        #expect(firstPresentation.id == secondPresentation.id)
        #expect(firstPresentation == secondPresentation)
        #expect(firstPresentation.scope === secondPresentation.scope)
    }

    @Test func repeatedPresentationOfUnequalRouteValueGetsNewPresentationIdentity() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(NumberedRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(NumberedRoute(number: 1))
        let firstPresentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .push
        ).wrappedValue)

        await router.requestRoute(NumberedRoute(number: 2))
        let secondPresentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .push
        ).wrappedValue)

        #expect(router.normalTree.rootPath.count == 1)
        #expect(firstPresentation.id != secondPresentation.id)
        #expect(firstPresentation.scope !== secondPresentation.scope)
        #expect(secondPresentation.scope.route as? NumberedRoute == NumberedRoute(number: 2))
    }

    @Test func presentingEquivalentAncestorUnwindsToExistingScopeInsteadOfRePresenting() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Push(NumberedRoute.self)._routeDeclarations
                    + Push(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(NumberedRoute(number: 1))
        let numberedPresentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .push
        ).wrappedValue)
        let numberedScope = numberedPresentation.scope
        numberedScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(router.normalTree.rootPath.last)
        #expect(router.normalTree.rootPath.count == 2)
        #expect(settingsScope.route is SettingsRoute)
        router.routeScopeDidInstallInView(settingsScope)

        let requestTask = Task {
            await router.requestRoute(NumberedRoute(number: 1))
        }

        for _ in 0..<10 {
            if router.normalTree.rootPath.last === numberedScope {
                break
            }
            await Task.yield()
        }

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === numberedScope)
        #expect(router.routePresentationBinding(from: router.root, matching: .push).wrappedValue?.scope === numberedScope)
        #expect(router.routePresentationBinding(from: numberedScope, matching: .push).wrappedValue == nil)

        router.routeScopeDidLeaveView(settingsScope)
        await requestTask.value

        let finalPresentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .push
        ).wrappedValue)
        #expect(finalPresentation.id == numberedPresentation.id)
        #expect(finalPresentation.scope === numberedScope)
        #expect(router.normalTree.rootPath.count == 1)
    }

    @Test func presentingEquivalentRouteInInactiveBranchSelectsBranchAndUnwindsThere() async throws {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.wallet)

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
                        Push(NumberedRoute.self)
                        Push(SettingsRoute.self)
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

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Push(NumberedRoute.self)._routeDeclarations
                    + Push(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )
        router.root.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(NumberedRoute(number: 7))
        let numberedScope = try #require(walletScope.path.last)
        numberedScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        #expect(walletScope.path.count == 2)
        #expect(walletScope.path.last?.route is SettingsRoute)

        await router.requestRoute(HomeDetailRoute())
        router.resumePendingRoute(for: AppTab.home, in: router.root)
        #expect(selectedTab() == .home)
        #expect(homeScope.path.last?.route is HomeDetailRoute)

        await router.requestRoute(NumberedRoute(number: 7))

        #expect(selectedTab() == .wallet)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last === numberedScope)
        #expect(walletScope.path.last?.route as? NumberedRoute == NumberedRoute(number: 7))
    }

    @Test func replacingInstalledPushWaitsForOldScopeToLeaveViewBeforeAppendingNextRoute() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
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
        let firstScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(firstScope)

        let requestTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        await Task.yield()

        #expect(router.normalTree.rootPath.isEmpty)

        router.routeScopeDidLeaveView(firstScope)
        await requestTask.value

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is SettingsRoute)
    }

    @Test func removingPresentedRouteScopeSynchronizesRouterPath() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.normalTree.rootPath.last)

        router.removeFromPath(pushedScope)

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .push).wrappedValue == nil)
    }

    @Test func routeScopeLeavingViewUninstallsWithoutRemovingRouterPath() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.normalTree.rootPath.last)

        router.routeScopeDidInstallInView(pushedScope)
        router.routeScopeDidLeaveView(pushedScope)

        #expect(pushedScope.isInstalledInView == false)
        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === pushedScope)
        #expect(router.routePresentationBinding(from: router.root, matching: .push).wrappedValue != nil)
    }

    @Test func unwindDismissesCurrentRoute() async {
        let router = Router()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.normalTree.rootPath.scopes = [firstScope]
        router.installElevatedTree(priority: .high, scopes: [secondScope])

        await router.unwindAndWait(to: nil)

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === firstScope)
        #expect(router.routeForest.highTree == nil)
    }

    @Test func unwindToIDKeepsMatchingRouteScope() async {
        let router = Router()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.normalTree.rootPath.scopes = [firstScope]
        router.installElevatedTree(priority: .high, scopes: [secondScope])

        await router.unwindAndWait(to: .id(RootRoute().id))

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === firstScope)
        #expect(router.routeForest.highTree == nil)
    }

    @Test func unwindToRootClearsPath() async {
        let router = Router()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.normalTree.rootPath.scopes = [firstScope]
        router.installElevatedTree(priority: .high, scopes: [secondScope])

        await router.unwindAndWait(to: .root)

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.routeForest.highTree == nil)
    }

    @Test func unwindToRootClearsAppRootAndActiveBranchFromDeepWithinBranch() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())
        #expect(walletScope.path.count == 1)
        #expect(router.normalTree.rootPath.count == 1)

        // `.root` reaches past the current branch path to the app root.
        await router.unwind(to: .root)
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(walletScope.path.isEmpty)
    }

    @Test func unwindToRootClearsActiveBranchPushAndAdoptedModal() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Sheet(MessageRoute.self)
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Sheet(MessageRoute.self)._routeDeclarations.drivingPresentation(true)
                    + Push(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        await router.requestRoute(SettingsRoute())
        await router.requestRoute(MessageRoute())

        #expect(router.normalTree.rootPath.count == 1)
        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first?.route is SettingsRoute)
        #expect(homeScope.path.last?.route is MessageRoute)

        await router.unwind(to: .root)

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(homeScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func unwindToRootClearsInactiveBranchStacksOwnedByRemovedScope() async throws {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Push(HomeDetailRoute.self)
                        Sheet(MessageRoute.self)
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
                RouteScopeDeclaration(
                    routes: Push(HomeDetailRoute.self)._routeDeclarations
                    + Sheet(MessageRoute.self)._routeDeclarations
                ),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(TransactionRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        await router.requestRoute(MessageRoute())
        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))
        await router.requestRoute(TransactionRoute())

        #expect(selectedTab() == .wallet)
        #expect(router.normalTree.rootPath.count == 1)
        #expect(homeScope.path.count == 2)
        #expect(walletScope.path.count == 1)

        await router.unwind(to: .root)

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(homeScope.path.isEmpty)
        #expect(walletScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: homeScope, matching: .push).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func unwindToRootPreservesInactiveBranchPushStackButClearsModal() async throws {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.home)

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Push(HomeDetailRoute.self)
                        Sheet(MessageRoute.self)
                    }
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Push(TransactionRoute.self)
                        Sheet(SettingsRoute.self)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Push(HomeDetailRoute.self)._routeDeclarations
                    + Sheet(MessageRoute.self)._routeDeclarations
                ),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Push(TransactionRoute.self)._routeDeclarations
                    + Sheet(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )
        router.root.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        await router.requestRoute(MessageRoute())
        router.root.setActiveBranch(AnyHashable(AppTab.wallet))
        await router.requestRoute(TransactionRoute())
        await router.requestRoute(SettingsRoute())

        #expect(selectedTab() == .wallet)
        #expect(homeScope.path.count == 2)
        #expect(walletScope.path.count == 2)

        await router.unwind(to: .root)

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .push).wrappedValue?.scope === homeScope.path.last)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
        #expect(walletScope.path.isEmpty)
    }

    @Test func unwindToNearestBranchClearsThatBranchPathButKeepsTheAppRoot() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())
        #expect(walletScope.path.count == 1)

        // `.nearestBranch` is branch-scoped: from a pushed scope it clears the branch's own path back
        // to its root but keeps the app root (the landing scope) — it does not escape the branch.
        await router.unwind(to: .nearestBranch)
        #expect(walletScope.path.isEmpty)
        #expect(router.normalTree.rootPath.count == 1)
    }

    @Test func unwindToNearestBranchAtBranchRootIsNoOp() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        // Already at the branch root (nothing pushed). `.nearestBranch` must not escape to the root
        // path — it is a no-op that leaves the landing (app root) intact.
        #expect(walletScope.path.isEmpty)
        await router.unwind(to: .nearestBranch)
        #expect(walletScope.path.isEmpty)
        #expect(router.normalTree.rootPath.count == 1)
    }

    @Test func sequentialUnwindThenPresentWaitsForInstalledRouteScopeToLeaveView() async {
        let router = Router()
        let loginScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
            ]
        )

        router.installElevatedTree(priority: .high, scopes: [loginScope])
        router.routeScopeDidInstallInView(loginScope)

        let unwindTask = Task {
            guard await router.unwind(to: nil) else {
                return
            }

            await router.present(SettingsRoute())
        }

        await Task.yield()

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        _ = await unwindTask.value

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is SettingsRoute)
    }

    @Test func modalReplacementWaitsForInstalledRouteScopeToLeaveView() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Sheet(LoginRoute.self)._routeDeclarations
                    + Sheet(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let replacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.normalTree.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        await replacementTask.value

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is SettingsRoute)
    }

    @Test func sheetToCoverReplacementWaitsForOldScopeToLeaveView() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Sheet(LoginRoute.self)._routeDeclarations
                    + Cover(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let replacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.normalTree.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        await replacementTask.value

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue?.scope === router.normalTree.rootPath.last)
    }

    @Test func coverToSheetReplacementWaitsForOldScopeToLeaveView() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(LoginRoute.self)._routeDeclarations
                    + Sheet(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let replacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.normalTree.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        await replacementTask.value

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue?.scope === router.normalTree.rootPath.last)
    }

    @Test func pendingModalReplacementUsesLatestRequest() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(LoginRoute.self)._routeDeclarations
                    + Cover(SettingsRoute.self)._routeDeclarations
                    + Cover(AlertRoute.self)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let firstReplacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.normalTree.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.normalTree.rootPath.isEmpty)

        let latestReplacementTask = Task {
            await router.requestRoute(AlertRoute())
        }

        await Task.yield()
        #expect(router.normalTree.rootPath.isEmpty)

        router.routeScopeDidLeaveView(loginScope)
        await firstReplacementTask.value
        await latestReplacementTask.value

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is AlertRoute)
    }

    @Test func snapshotPresentationUsesOriginalPositionForHighTreeLocalHosting() async {
        let router = Router()
        let rootScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let loginScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let noticeScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let noticeDeclaration = Sheet(SettingsRoute.self, priority: .high)._routeDeclarations[0]

        router.normalTree.rootPath.scopes = [rootScope]
        router.installElevatedTree(priority: .high, scopes: [loginScope, noticeScope])
        loginScope.modalChild = noticeScope
        noticeScope.hostScope = loginScope
        noticeScope.hostDeclaration = noticeDeclaration
        router.routeScopeDidInstallInView(loginScope)
        router.routeScopeDidInstallInView(noticeScope)

        let unwindTask = Task {
            await router.unwind(to: .id(RootRoute().id))
        }

        for _ in 0..<10 {
            if router.unwindPresentationSnapshot != nil {
                break
            }
            await Task.yield()
        }

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.unwindPresentationSnapshot != nil)
        let presentation = router.routePresentation(from: loginScope, matching: .sheet)
        #expect(presentation?.scope === noticeScope)
        #expect(presentation?.declaration.priority == .high)

        router.routeScopeDidLeaveView(loginScope)
        router.routeScopeDidLeaveView(noticeScope)

        #expect(await unwindTask.value)
    }

    @Test func unwindFromBranchPresentationKeepsPresentedTopLevelScope() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: Branch(AppTab.home) {
                Cover(MessageRoute.self, transition: .fade, providesNavigation: false)
            }.routeScopeDeclarations
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(MessageRoute.self, transition: .fade, providesNavigation: false)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        await router.requestRoute(MessageRoute())
        #expect(homeScope.path.count == 1)

        await router.unwind(to: nil)

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === landingScope)
        #expect(homeScope.path.isEmpty)
    }

    @Test func highPriorityUnwindFromBranchKeepsPresentedTopLevelScopeForContinuation() async throws {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Cover(LoginRoute.self, priority: .high)
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Sheet(MessageRoute.self)
                    }
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(MessageRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(LoginRoute())

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === landingScope)
        #expect(router.routeForest.highTree?.rootPath.count == 1)
        #expect(router.routeForest.highTree?.rootPath.last?.route is LoginRoute)
        #expect(router.routeForest.highTree?.currentRoutePath === router.routeForest.highTree?.rootPath)

        await router.unwind(to: nil)

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === landingScope)
        #expect(landingScope.path.isEmpty)
        #expect(walletScope.path.isEmpty)

        await router.requestRoute(MessageRoute())
        router.resumePendingRoute(for: AppTab.home, in: landingScope)

        #expect(selectedTab() == .home)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is MessageRoute)
    }

    @Test func unwindFromBranchPushCanTargetAncestorRouteForContinuation() async throws {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.normalTree.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Cover(MessageRoute.self, transition: .fade, providesNavigation: false)
                    }
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(MessageRoute.self, transition: .fade, providesNavigation: false)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())

        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is SettingsRoute)

        let didUnwind = await router.unwind(to: .id(RootRoute().id))
        if didUnwind {
            await router.requestRoute(MessageRoute())
            router.resumePendingRoute(for: AppTab.home, in: landingScope)
        }

        #expect(didUnwind)
        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === landingScope)
        #expect(walletScope.path.isEmpty)
        #expect(selectedTab() == .home)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is MessageRoute)
    }

    @Test func sequentialUnwindThenPresentCutsPathBeforeWaitingForAllRemovedScopes() async {
        let router = Router()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let thirdScope = RouteScope(id: AlertRoute().id, route: AlertRoute())

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
            ]
        )

        router.normalTree.rootPath.scopes = [firstScope, secondScope, thirdScope]
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

        #expect(router.normalTree.rootPath.isEmpty)

        router.routeScopeDidLeaveView(firstScope)
        router.routeScopeDidLeaveView(secondScope)
        await Task.yield()

        #expect(router.normalTree.rootPath.isEmpty)

        router.routeScopeDidLeaveView(thirdScope)
        _ = await unwindTask.value

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last?.route is SettingsRoute)
    }

    @Test func unwindPreservesDescendantPresentationBindingsUntilAncestorLeavesView() async {
        let router = Router()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let profileScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(RootRoute.self, providesNavigation: false)._routeDeclarations),
            ]
        )
        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(LoginRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        router.normalTree.rootPath.scopes = [landingScope, profileScope]
        profileScope.hostScope = homeScope
        profileScope.hostDeclaration = homeScope.routeAttachments.first { $0.presentationKind == .sheet }
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

    @Test func rootUnwindPreservesBranchDescendantPresentationBindingUntilAncestorLeavesView() async {
        let router = Router()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let profileScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(RootRoute.self, providesNavigation: false)._routeDeclarations),
            ]
        )
        landingScope.hostScope = router.root
        landingScope.hostDeclaration = router.root.routeAttachments.first { $0.presentationKind == .cover(.slide) }
        router.root.modalChild = landingScope

        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(LoginRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home)

        profileScope.hostScope = homeScope
        profileScope.hostDeclaration = homeScope.routeAttachments.first { $0.presentationKind == .sheet }
        homeScope.modalChild = profileScope
        homeScope.path.scopes = [profileScope]
        router.normalTree.rootPath.scopes = [landingScope]

        router.routeScopeDidInstallInView(landingScope)
        router.routeScopeDidInstallInView(profileScope)

        let unwindTask = Task {
            await router.unwindAndWait(to: .root)
        }

        for _ in 0..<10 {
            if router.unwindPresentationSnapshot != nil {
                break
            }
            await Task.yield()
        }

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(homeScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue?.scope === profileScope)

        router.routeScopeDidLeaveView(landingScope)
        router.routeScopeDidLeaveView(profileScope)
        _ = await unwindTask.value

        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func unwindSnapshotDoesNotPreservePushPresentationBinding() async {
        let router = Router()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let settingsScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let authenticationScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))
        settingsScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(LoginRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(settingsScope, for: AppTab.wallet)

        authenticationScope.hostScope = settingsScope
        authenticationScope.hostDeclaration = settingsScope.routeAttachments.first { $0.presentationKind == .push }
        settingsScope.pushChild = authenticationScope
        settingsScope.path.scopes = [authenticationScope]
        router.normalTree.rootPath.scopes = [landingScope]

        router.routeScopeDidInstallInView(authenticationScope)

        let unwindTask = Task {
            await router.unwindAndWait(to: .nearestBranch)
        }

        for _ in 0..<10 {
            if router.unwindPresentationSnapshot != nil {
                break
            }
            await Task.yield()
        }

        #expect(settingsScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .push).wrappedValue == nil)

        router.routeScopeDidLeaveView(authenticationScope)
        _ = await unwindTask.value
    }

    @Test func inactiveBranchPathIsPreservedWhenActiveBranchChanges() async throws {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.home)

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

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(TransactionRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        let homeDetailScope = try #require(homeScope.path.last)

        router.root.setActiveBranch(AnyHashable(AppTab.wallet))

        #expect(selectedTab() == .wallet)
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last === homeDetailScope)

        await router.requestRoute(TransactionRoute())
        let transactionScope = try #require(walletScope.path.last)

        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last === homeDetailScope)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last === transactionScope)

        router.root.setActiveBranch(AnyHashable(AppTab.home))

        #expect(selectedTab() == .home)
        #expect(homeScope.path.last === homeDetailScope)
        #expect(walletScope.path.last === transactionScope)
    }

    @Test func highPriorityTreeClearsWhenHighRouteLeavesViewOnInactiveBranch() async throws {
        let router = Router()
        let (selection, selectedTab) = tabSelection(.wallet)

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Sheet(SettingsRoute.self)
                    }
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Cover(LoginRoute.self, priority: .high)
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(LoginRoute())
        let highRouteScope = try #require(router.routeForest.highTree?.rootPath.last)
        router.routeScopeDidInstallInView(highRouteScope)

        router.root.setActiveBranch(AnyHashable(AppTab.home))
        router.routeScopeDidLeaveView(highRouteScope)

        #expect(selectedTab() == .home)
        #expect(router.routeForest.highTree == nil)

        await router.requestRoute(SettingsRoute())

        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue?.scope === homeScope.path.last)
    }

    @Test func inactiveBranchPushPresentationBindingStaysStableWhenActiveBranchChanges() async throws {
        let router = Router()
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

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(TransactionRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        let homeDetailScope = try #require(homeScope.path.last)
        let homePresentation = router.routePresentationBinding(from: homeScope, matching: .push)

        #expect(homePresentation.wrappedValue?.scope === homeDetailScope)

        router.root.setActiveBranch(AnyHashable(AppTab.wallet))

        #expect(homePresentation.wrappedValue?.scope === homeDetailScope)

        await router.requestRoute(TransactionRoute())

        #expect(router.routePresentationBinding(from: walletScope, matching: .push).wrappedValue?.scope === walletScope.path.last)
        #expect(homePresentation.wrappedValue?.scope === homeDetailScope)

        router.root.setActiveBranch(AnyHashable(AppTab.home))

        #expect(homePresentation.wrappedValue?.scope === homeDetailScope)
    }

    @Test func branchLocalModalPresentationOnlyDrivesWhenParentBranchIsActive() async {
        let router = Router()
        let (selection, _) = tabSelection(.home)

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: Branch(AppTab.home) {
                Sheet(HomeDetailRoute.self)
            }.routeScopeDeclarations
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(HomeDetailRoute.self)._routeDeclarations),
            ]
        )
        router.root.registerBranchScope(homeScope, for: AppTab.home)

        await router.requestRoute(HomeDetailRoute())

        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue != nil)

        router.root.setActiveBranch(AnyHashable(AppTab.wallet))

        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    #if DEBUG
    @Test func branchScopeRegistrationIsIdempotentAndKeepsDebugIdentityAfterUnregister() {
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let branchScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)

        #expect(parentScope.registerBranchScope(branchScope, for: AppTab.home))
        #expect(parentScope.registerBranchScope(branchScope, for: AppTab.home) == false)
        #expect(branchScope.departureDebugDescription == "branchScope#home")

        parentScope.unregisterBranchScope(branchScope, for: AppTab.home)
        parentScope.unregisterBranchScope(branchScope, for: AppTab.home)

        #expect(branchScope.parent == nil)
        #expect(branchScope.departureDebugDescription == "branchScope#home")
    }
    #endif

    @Test func highPriorityPresentationUsesActiveLocalBranchScope() async {
        let router = Router()
        let (selection, _) = tabSelection(.home)

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: Branch(AppTab.home) {
                Cover(LoginRoute.self, priority: .high)
            }.routeScopeDeclarations
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
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

        #expect(presentation?.scope === router.routeForest.highTree?.rootPath.last)
        #expect(presentation?.declaration.routeTypeID == ObjectIdentifier(LoginRoute.self))
    }

    @Test func highPriorityPresentationCanUseContainerDeclarationFromActiveLocalBranch() async {
        let router = Router()
        let (selection, _) = tabSelection(.home)

        router.root.installRouteDeclarations(
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
        homeScope.installRouteDeclarations(
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

        #expect(presentation?.scope === router.routeForest.highTree?.rootPath.last)
        #expect(presentation?.declaration.routeTypeID == ObjectIdentifier(LoginRoute.self))
    }

    @Test func normalRouteBeforeActiveHighTreeIsDropped() async {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations
                    + Sheet(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(LoginRoute())
        await router.requestRoute(SettingsRoute())

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.routeForest.highTree?.rootPath.count == 1)
        #expect(router.routeForest.highTree?.rootPath.last?.route is LoginRoute)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)
    }

    @Test func highPriorityPresentationOverlaysNormalPresentation() async {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(SettingsRoute.self)._routeDeclarations
                    + Cover(LoginRoute.self, priority: .high)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let normalScope = router.normalTree.rootPath.last

        await router.requestRoute(LoginRoute())

        let normalPresentation = router.routePresentationBinding(
            from: router.root,
            matching: .cover(.slide)
        ).wrappedValue
        let highPresentation = router.highPriorityRoutePresentationBinding(
            matching: .cover(.slide)
        ).wrappedValue

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.first === normalScope)
        #expect(router.normalTree.rootPath.first?.route is SettingsRoute)
        #expect(router.routeForest.highTree?.rootPath.count == 1)
        #expect(router.routeForest.highTree?.rootPath.last?.route is LoginRoute)
        #expect(router.routeForest.highTree?.elevatedRouteScope?.route is LoginRoute)
        #expect(normalPresentation?.scope === normalScope)
        #expect(normalPresentation?.declaration.priority == .normal)
        #expect(highPresentation?.scope === router.routeForest.highTree?.rootPath.last)
        #expect(highPresentation?.declaration.priority == .high)

        router.highPriorityRoutePresentationBinding(matching: .cover(.slide)).wrappedValue = nil

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === normalScope)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue?.scope === normalScope)
        #expect(router.routeForest.highTree == nil)
    }

    @Test func highPriorityReplacementPreservesUnderlyingNormalPresentation() async {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(SettingsRoute.self)._routeDeclarations
                    + Cover(LoginRoute.self, priority: .high)._routeDeclarations
                    + Cover(AlertRoute.self, priority: .high, transition: .fade, providesNavigation: false)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let normalScope = router.normalTree.rootPath.last
        await router.requestRoute(LoginRoute())
        await router.requestRoute(AlertRoute())

        let normalPresentation = router.routePresentationBinding(
            from: router.root,
            matching: .cover(.slide)
        ).wrappedValue
        let highPresentation = router.highPriorityRoutePresentationBinding(
            matching: .cover(.fade)
        ).wrappedValue

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.first === normalScope)
        #expect(router.normalTree.rootPath.first?.route is SettingsRoute)
        #expect(router.routeForest.highTree?.rootPath.count == 1)
        #expect(router.routeForest.highTree?.rootPath.last?.route is AlertRoute)
        #expect(router.routeForest.highTree?.rootPath.scopes.contains { $0.route is LoginRoute } == false)
        #expect(router.routeForest.highTree?.elevatedRouteScope?.route is AlertRoute)
        #expect(normalPresentation?.scope === normalScope)
        #expect(normalPresentation?.declaration.priority == .normal)
        #expect(highPresentation?.scope === router.routeForest.highTree?.rootPath.last)
        #expect(highPresentation?.declaration.priority == .high)
    }

    @Test func normalRouteMatchedInsideHighTreeAppendsNormally() async {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = router.routeForest.highTree?.rootPath.last
        loginScope?.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())

        #expect(router.routeForest.highTree?.rootPath.count == 2)
        #expect(router.routeForest.highTree?.rootPath.first?.route is LoginRoute)
        #expect(router.routeForest.highTree?.rootPath.last?.route is SettingsRoute)
        #expect(router.routeForest.highTree?.elevatedRouteScope === loginScope)
    }

    @Test func highPriorityDeclarationInsideHighTreeAppendsNormally() async {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = router.routeForest.highTree?.rootPath.last
        loginScope?.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(AlertRoute.self, priority: .high, transition: .fade, providesNavigation: false)._routeDeclarations),
            ]
        )

        await router.requestRoute(AlertRoute())

        #expect(router.routeForest.highTree?.rootPath.count == 2)
        #expect(router.routeForest.highTree?.rootPath.first?.route is LoginRoute)
        #expect(router.routeForest.highTree?.rootPath.last?.route is AlertRoute)
        #expect(router.routeForest.highTree?.elevatedRouteScope === loginScope)
        #expect(router.routePresentationBinding(from: loginScope, matching: .cover(.fade)).wrappedValue?.scope === router.routeForest.highTree?.rootPath.last)
    }

    @Test func presentingEquivalentHighPriorityRouteUnwindsInsideHighTreeInsteadOfReplacing() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.routeForest.highTree?.rootPath.last)
        loginScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(router.routeForest.highTree?.rootPath.last)
        #expect(router.routeForest.highTree?.rootPath.count == 2)
        #expect(settingsScope.route is SettingsRoute)
        router.routeScopeDidInstallInView(settingsScope)

        let requestTask = Task {
            await router.requestRoute(LoginRoute())
        }

        for _ in 0..<10 {
            if router.routeForest.highTree?.rootPath.last === loginScope {
                break
            }
            await Task.yield()
        }

        #expect(router.routeForest.highTree?.rootPath.count == 1)
        #expect(router.routeForest.highTree?.rootPath.last === loginScope)
        #expect(router.routeForest.highTree?.elevatedRouteScope === loginScope)
        #expect(router.highPriorityRoutePresentationBinding(matching: .cover(.slide)).wrappedValue?.scope === loginScope)

        router.routeScopeDidLeaveView(settingsScope)
        await requestTask.value

        #expect(router.routeForest.highTree?.rootPath.count == 1)
        #expect(router.routeForest.highTree?.rootPath.last === loginScope)
        #expect(router.routeForest.highTree?.elevatedRouteScope === loginScope)
    }

    @Test func ancestorHighPriorityDeclarationReplacesActiveHighPriorityRoute() async {
        let router = Router()

        router.root.installRouteDeclarations(
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

        #expect(router.routeForest.highTree?.rootPath.count == 1)
        #expect(router.routeForest.highTree?.rootPath.last?.route is AlertRoute)
        #expect(presentation?.scope === router.routeForest.highTree?.rootPath.last)
        #expect(presentation?.declaration.routeTypeID == ObjectIdentifier(AlertRoute.self))
    }

    @Test func criticalPriorityPresentationOverlaysHighPriorityPresentation() async {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations
                    + Cover(AlertRoute.self, priority: .critical, transition: .fade, providesNavigation: false)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(LoginRoute())
        let highScope = router.routeForest.highTree?.rootPath.last

        await router.requestRoute(AlertRoute())

        let highPresentation = router.highPriorityRoutePresentationBinding(
            matching: .cover(.slide)
        ).wrappedValue
        let criticalPresentation = router.elevatedRoutePresentationBinding(
            priority: .critical,
            matching: .cover(.fade)
        ).wrappedValue

        #expect(router.routeForest.highTree?.rootPath.count == 1)
        #expect(router.routeForest.highTree?.rootPath.first === highScope)
        #expect(router.routeForest.highTree?.rootPath.first?.route is LoginRoute)
        #expect(router.routeForest.criticalTree?.rootPath.count == 1)
        #expect(router.routeForest.criticalTree?.rootPath.last?.route is AlertRoute)
        #expect(router.routeForest.highTree?.elevatedRouteScope === highScope)
        #expect(router.routeForest.criticalTree?.elevatedRouteScope === router.routeForest.criticalTree?.rootPath.last)
        #expect(highPresentation?.scope === highScope)
        #expect(highPresentation?.declaration.priority == .high)
        #expect(criticalPresentation?.scope === router.routeForest.criticalTree?.rootPath.last)
        #expect(criticalPresentation?.declaration.priority == .critical)
    }

    @Test func unwindingHighPriorityRoutePreservesCriticalTreeAnchoredToAncestor() async throws {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations
                    + Cover(AlertRoute.self, priority: .critical, transition: .fade, providesNavigation: false)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.routeForest.highTree?.rootPath.last)
        await router.requestRoute(AlertRoute())

        let didUnwind = await router.unwindRoute(from: loginScope)

        #expect(didUnwind)
        #expect(router.routeForest.highTree == nil)
        #expect(router.routeForest.criticalTree != nil)
        #expect(router.elevatedRoutePresentationBinding(priority: .critical, matching: .cover(.fade)).wrappedValue != nil)
    }

    @Test func criticalPriorityReplacementPreservesUnderlyingHighPriorityPresentation() async {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations
                    + Cover(AlertRoute.self, priority: .critical, transition: .fade, providesNavigation: false)._routeDeclarations
                    + Cover(SettingsRoute.self, priority: .critical)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(LoginRoute())
        let highScope = router.routeForest.highTree?.rootPath.last
        await router.requestRoute(AlertRoute())
        await router.requestRoute(SettingsRoute())

        let highPresentation = router.highPriorityRoutePresentationBinding(
            matching: .cover(.slide)
        ).wrappedValue
        let criticalPresentation = router.elevatedRoutePresentationBinding(
            priority: .critical,
            matching: .cover(.slide)
        ).wrappedValue

        #expect(router.routeForest.highTree?.rootPath.count == 1)
        #expect(router.routeForest.highTree?.rootPath.first === highScope)
        #expect(router.routeForest.highTree?.rootPath.first?.route is LoginRoute)
        #expect(router.routeForest.criticalTree?.rootPath.count == 1)
        #expect(router.routeForest.criticalTree?.rootPath.last?.route is SettingsRoute)
        #expect(router.routeForest.criticalTree?.rootPath.scopes.contains { $0.route is AlertRoute } == false)
        #expect(router.routeForest.highTree?.elevatedRouteScope === highScope)
        #expect(router.routeForest.criticalTree?.elevatedRouteScope === router.routeForest.criticalTree?.rootPath.last)
        #expect(highPresentation?.scope === highScope)
        #expect(criticalPresentation?.scope === router.routeForest.criticalTree?.rootPath.last)
        #expect(criticalPresentation?.declaration.priority == .critical)
    }

    @Test func lowerPriorityRouteBeforeActiveCriticalTreeIsDropped() async {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(LoginRoute.self, priority: .critical)._routeDeclarations
                    + Cover(SettingsRoute.self, priority: .high)._routeDeclarations
                    + Sheet(MessageRoute.self)._routeDeclarations
                ),
            ]
        )

        await router.requestRoute(LoginRoute())
        await router.requestRoute(SettingsRoute())
        await router.requestRoute(MessageRoute())

        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.routeForest.criticalTree?.rootPath.count == 1)
        #expect(router.routeForest.criticalTree?.rootPath.last?.route is LoginRoute)
        #expect(router.routeForest.criticalTree?.elevatedRouteScope === router.routeForest.criticalTree?.rootPath.last)
        #expect(router.routeForest.highTree == nil)
    }

    @Test func criticalPriorityDeclarationInsideHighTreeStartsCriticalTree() async {
        let router = Router()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = router.routeForest.highTree?.rootPath.last
        loginScope?.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(AlertRoute.self, priority: .critical, transition: .fade, providesNavigation: false)._routeDeclarations),
            ]
        )

        await router.requestRoute(AlertRoute())

        #expect(router.routeForest.highTree?.rootPath.count == 1)
        #expect(router.routeForest.highTree?.rootPath.first?.route is LoginRoute)
        #expect(router.routeForest.criticalTree?.rootPath.count == 1)
        #expect(router.routeForest.criticalTree?.rootPath.last?.route is AlertRoute)
        #expect(router.routeForest.highTree?.elevatedRouteScope === loginScope)
        #expect(router.routeForest.criticalTree?.elevatedRouteScope === router.routeForest.criticalTree?.rootPath.last)
        #expect(router.elevatedRoutePresentationBinding(priority: .critical, matching: .cover(.fade)).wrappedValue?.scope === router.routeForest.criticalTree?.rootPath.last)
        #expect(router.routePresentationBinding(from: loginScope, matching: .cover(.fade)).wrappedValue == nil)
    }
}

private extension Router {
    @MainActor
    func installElevatedTree(priority: RoutePriority, scopes: [RouteScope]) {
        let rootScope = RouteScope(id: UUID(), route: nil)
        let routePath = RoutePath(owner: rootScope)
        routePath.scopes = scopes
        let tree = RouteTree(priority: priority, root: rootScope, rootPath: routePath)

        switch priority {
        case .normal:
            break

        case .high:
            routeForest.highTree = tree

        case .critical:
            routeForest.criticalTree = tree
        }

        mutateRouteGraph {}
    }
}
