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
        let router = RouterEngine()
        let sameRouter = router
        let otherRouter = RouterEngine()

        #expect(router == sameRouter)
        #expect(router != otherRouter)
        #expect(router.id != otherRouter.id)
    }

    @Test func routeEqualityUsesEquatableConformanceWhenAvailable() {
        #expect(EquatableOnlyRoute(value: 1)._isEqual(to: EquatableOnlyRoute(value: 1)))
        #expect(EquatableOnlyRoute(value: 1)._isEqual(to: EquatableOnlyRoute(value: 2)) == false)
    }

    @Test func routeEqualityRequiresEquatableConformance() {
        #expect(NonEquatableRoute(value: 1)._isEqual(to: NonEquatableRoute(value: 1)) == false)
    }

    @Test func publicRoutingActionsDispatchThroughRouter() async {
        let owner = RootRouter()
        let router = owner.engine
        let actionRecorder = AsyncActionRecorder()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )

        await owner.current.present(HomeDetailRoute())

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last?.route is HomeDetailRoute)

        await owner.current.unwind(.current)

        #expect(router.tree.rootPath.isEmpty)

        router.tree.rootPath.replaceTestPath([RouteScope(id: RootRoute().id, route: RootRoute())])
        await owner.current.perform(RecordingProbeAction(recorder: actionRecorder))

        #expect(await actionRecorder.values() == [true])
    }

    @Test func routePhaseTracksCurrentRouteScope() {
        let router = RouterEngine()
        let routeScope = RouteScope(id: RootRoute().id, route: RootRoute())

        #expect(router.routePhase(for: router.root) == .active)
        #expect(router.routePhase(for: routeScope) == .inactive)

        router.mutateRouteGraph {
            router.tree.rootPath.replaceTestPath([routeScope])
        }

        #expect(router.routePhase(for: router.root) == .inactive)
        #expect(router.routePhase(for: routeScope) == .active)
    }

    @Test func deferredBranchHostTeardownPreservesMapAndLogicalRoutePhase() async {
        let engine = RouterEngine(routes: RootRouteMap { Branches { Branch(AppTab.home) {
            testPush(testDestination(HomeDetailRoute.self))
        } } })
        let home = engine.root.branchScopes[AppTab.home]!
        let teardownDelivery = ViewLifecycleTeardownDelivery()
        let lifecycleID = UUID()
        teardownDelivery.install(lifecycleID)
        let teardownTask = teardownDelivery.schedule(for: lifecycleID) { engine.routeScopeDidLeaveView(home) }
        await teardownTask?.value
        #expect(engine.root.branchScopes[AppTab.home] === home)
        #expect(home.definitions.routeBinding(for: HomeDetailRoute.self) != nil)
        #expect(engine.routePhase(for: home) == .active)
    }

    @Test func activeEmptyBranchIsTheCurrentRoutePath() async {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        #expect(router.tree.currentRouteScope === homeScope)
        #expect(router.tree.currentRoutePath === homeScope.path)

        await router.requestRoute(HomeDetailRoute())

        #expect(router.tree.currentRouteScope === homeScope.path.last)
        #expect(router.tree.currentRoutePath === homeScope.path)
    }

    @Test func routePhaseTreatsActiveBranchRootAsCurrentScope() {
        let router = RouterEngine()
        let containerScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)

        router.mutateRouteGraph {
            router.tree.rootPath.replaceTestPath([containerScope])
            containerScope.setActiveBranch(AnyHashable(AppTab.home))
            containerScope.attachTestBranch(homeScope, for: AppTab.home)
            containerScope.attachTestBranch(walletScope, for: AppTab.wallet)
        }

        #expect(router.routePhase(for: containerScope) == .inactive)
        #expect(router.routePhase(for: homeScope) == .active)
        #expect(router.routePhase(for: walletScope) == .inactive)

        let detailScope = RouteScope(id: HomeDetailRoute().id, route: HomeDetailRoute())
        router.mutateRouteGraph {
            homeScope.path.replaceTestPath([detailScope])
        }

        #expect(router.routePhase(for: containerScope) == .inactive)
        #expect(router.routePhase(for: homeScope) == .inactive)
        #expect(router.routePhase(for: detailScope) == .active)
    }

    @Test func routePhaseTracksActiveBranchChanges() {
        let router = RouterEngine()
        let containerScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)

        router.mutateRouteGraph {
            router.tree.rootPath.replaceTestPath([containerScope])
            containerScope.setActiveBranch(AnyHashable(AppTab.home))
            containerScope.attachTestBranch(homeScope, for: AppTab.home)
            containerScope.attachTestBranch(walletScope, for: AppTab.wallet)
        }

        router.mutateRouteGraph {
            containerScope.setActiveBranch(AnyHashable(AppTab.wallet))
        }

        #expect(router.routePhase(for: homeScope) == .inactive)
        #expect(router.routePhase(for: walletScope) == .active)
    }

    @Test func presentedBranchModalIsTheOnlyActiveRouteScope() async throws {
        let router = RouterEngine()
        let containerScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)

        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        router.mutateRouteGraph {
            router.tree.rootPath.replaceTestPath([containerScope])
            containerScope.setActiveBranch(AnyHashable(AppTab.home))
            containerScope.attachTestBranch(homeScope, for: AppTab.home)
        }

        await router.requestRoute(HomeDetailRoute())
        let modalScope = try #require(homeScope.path.last)

        #expect(router.currentRouteScope === modalScope)
        #expect(router.routePhase(for: modalScope) == .active)
        #expect(router.routePhase(for: homeScope) == .inactive)
        #expect(router.routePhase(for: containerScope) == .inactive)
        #expect(router.routePhase(for: router.root) == .inactive)
    }

    @Test func publicUnwindReportsMissingTargetBeforeContinuation() async {
        let router = RouterEngine()
        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )

        let didUnwind = await Router(engine: router).unwind(from: LoginRoute.self)
        if didUnwind {
            await router.present(SettingsRoute())
        }

        #expect(didUnwind == false)
        #expect(router.tree.rootPath.isEmpty)
    }

    @Test func publicUnwindReportsNoRouteAtRoot() async {
        let router = RouterEngine()

        #expect(await router.resetToRoot() == false)
        #expect(await router.unwind(.current) == false)
        #expect(router.tree.rootPath.isEmpty)
    }

    @Test func publicUnwindReportsMissingNearestModal() async {
        let router = RouterEngine()

        #expect(await router.unwind(.nearestModal) == false)
        #expect(router.tree.rootPath.isEmpty)
    }

    @Test func routeRequestSelectsInactiveBranchAndWaitsForInstalledBranchScope() async {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.wallet)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        await router.requestRoute(HomeDetailRoute())

        // Completion includes the staged insertion. A later native host refresh
        // cannot insert the destination again.
        await Task.yield()
        await Task.yield()

        #expect(selectedTab() == .home)
        #expect(router.tree.rootPath.isEmpty)
        #expect(router.pendingRoute == nil)

        let homeScope = router.root.branchScopes[AppTab.home]!
        router.resumePendingRoute(for: AppTab.home, in: router.root)

        #expect(router.tree.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(router.pendingRoute == nil)
    }

    @Test func predefinedBranchNavigationPreservesContainerWithoutDeclarationInstallation() async {
        let engine = RouterEngine(routes: RootRouteMap {
            testPush(testDestination(RootRoute.self)) {
                Branches { Branch(AppTab.home) { testPush(testDestination(HomeDetailRoute.self)) } }
            }
        })
        await engine.present(RootRoute())
        let container = engine.tree.rootPath.last!
        let home = container.branchScopes[AppTab.home]!
        #expect(!home.isInstalledInView)
        await Router(engine: engine, scope: container).present(HomeDetailRoute())
        #expect(engine.tree.rootPath.last === container)
        #expect(home.path.last?.route is HomeDetailRoute)
        #expect(engine.pendingRoute == nil)
    }

    @Test func nativeTeardownPreservesNamedScopeIdentity() {
        let scope = RouteScope(id: "explicit", route: nil)
        scope.define(RootRouteMap { testPush(testDestination(HomeDetailRoute.self)) }.declarations)
        scope.attachHost(nil, id: UUID())
        scope.detachHost(id: scope.hostID!)
        #expect(scope.id == AnyHashable("explicit"))
        #expect(scope.definitions.routeBinding(for: HomeDetailRoute.self) != nil)
    }

    @Test func changingBranchSelectionKeepsDefinitionsAndScopeIdentityStable() async {
        let engine = RouterEngine(routes: RootRouteMap { Branches {
            Branch(AppTab.home) { testPush(testDestination(HomeDetailRoute.self)) }
            Branch(AppTab.wallet) { testSheet(testDestination(SettingsRoute.self)) }
        } })
        let identity = engine.root.branchScopes.values.flatMap(\.routeAttachments).map(\.identity)
        let (selection, selected) = tabSelection(.home)
        engine.root.bindTestBranchSelection(AnyRouteBranchSelection(selection))
        engine.root.setActiveBranch(AppTab.wallet)
        #expect(selected() == .wallet)
        #expect(engine.root.branchScopes.values.flatMap(\.routeAttachments).map(\.identity) == identity)
        #expect(engine.tree.firstDeclaration(including: SettingsRoute.self)?.declaration?.branchID == AnyHashable(AppTab.wallet))
    }

    @Test func repeatedDuplicateRouteDeclarationsAreDisabled() {
        let map = RootRouteMap {
            testSheet(testDestination(SettingsRoute.self))
            testPush(testDestination(SettingsRoute.self))
        }
        let engine = RouterEngine(routes: map)
        #expect(engine.root.routeAttachments.isEmpty)
        guard case .conflict? = engine.tree.firstDeclaration(including: SettingsRoute.self) else {
            Issue.record("Expected a conflicting declaration")
            return
        }
    }

    @Test func branchScopeChecksLocalDeclarationsBeforeAdoptedDeclarations() async {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable("home-root"), route: nil)
        homeScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        #expect(homeScope.definitions.routeBinding(for: HomeDetailRoute.self)?.declaration?.presentationKind == .push)
        #expect(homeScope.definitions.routeBinding(for: SettingsRoute.self)?.declaration?.presentationKind == .sheet)
        #expect(homeScope.id == AnyHashable("home-root"))

        await router.requestRoute(HomeDetailRoute())

        #expect(router.tree.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)

        await router.unwind(.current)
        await router.requestRoute(SettingsRoute())

        #expect(router.tree.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue != nil)
    }

    @Test func routeRequestFromInstalledInactiveBranchWaitsForTargetBranchScope() async {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.wallet)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())

        #expect(selectedTab() == .home)
        #expect(router.tree.rootPath.isEmpty)
        #expect(router.pendingRoute == nil)

        let homeScope = router.root.branchScopes[AppTab.home]!
        router.resumePendingRoute(for: AppTab.home, in: router.root)

        #expect(router.tree.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(router.pendingRoute == nil)
    }

    @Test func inactiveBranchRequestResumesAfterMountedHostObservesSelection() async {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.wallet)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(HomeDetailRoute())
        for _ in 0..<10 where router.pendingRoute != nil {
            await Task.yield()
        }

        #expect(selectedTab() == .home)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(router.pendingRoute == nil)
    }

    @Test func inactiveBranchCoverRequestActivatesBranchAndPresentsFromAdoptedScope() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.wallet)

        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        router.tree.rootPath.replaceTestPath([landingScope])

        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.fade)))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.fade)))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        let settingsScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        settingsScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(settingsScope, for: AppTab.wallet)

        await router.requestRoute(MessageRoute())

        #expect(selectedTab() == .home)
        #expect(router.tree.rootPath.count == 1)
        #expect(router.pendingRoute == nil)

        router.resumePendingRoute(for: AppTab.home, in: landingScope)

        #expect(router.tree.rootPath.count == 1)
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
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.slide)))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(TransactionRoute())
        #expect(router.tree.rootPath.isEmpty)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)

        await router.requestRoute(MessageRoute())

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last?.route is MessageRoute)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)

        let presentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .cover(.slide)
        ).wrappedValue)
        #expect(presentation.scope === router.tree.rootPath.last)
        #expect(router.routePresentationBinding(from: walletScope, matching: .cover(.slide)).wrappedValue == nil)

        router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue = nil

        #expect(router.tree.rootPath.isEmpty)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)
    }

    @Test func branchContainerSheetDoesNotReappearAfterBranchSwitchDismissal() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(MessageRoute())

        #expect(selectedTab() == .wallet)
        #expect(router.tree.rootPath.count == 2)
        #expect(router.tree.rootPath.last?.route is MessageRoute)
        #expect(landingScope.path.isEmpty)
        #expect(walletScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue?.scope === router.tree.rootPath.last)

        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue = nil

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === landingScope)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)

        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))

        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)
        #expect(walletScope.path.isEmpty)
    }

    @Test func branchPushRequestDismissesTopLevelModalBeforeAppending() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(MessageRoute())
        let modalScope = try #require(router.tree.rootPath.last)
        router.routeScopeDidInstallInView(modalScope)

        let requestTask = Task {
            await router.requestRoute(HomeDetailRoute())
        }

        for _ in 0..<10 {
            if router.tree.rootPath.count == 1,
               router.tree.rootPath.last === landingScope,
               homeScope.path.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(selectedTab() == .home)
        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === landingScope)
        #expect(homeScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(modalScope)
        _ = await requestTask.value

        #expect(selectedTab() == .home)
        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === landingScope)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .push).wrappedValue?.scope === homeScope.path.last)
    }

    @Test func branchLocalPushDiscoveredBehindModalAppendsAfterActiveLocalScope() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let appearanceScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let modalScope = RouteScope(id: MessageRoute().id, route: MessageRoute())

        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )
        appearanceScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        let branchPushDeclaration = try #require(
            landingScope.branchScopes[AppTab.wallet]?.routeAttachments.first
        )
        let modalDeclaration = try #require(
            landingScope.definitions.routeAttachments.first
        )
        appearanceScope.attachPresentation(
            to: walletScope,
            declaration: branchPushDeclaration
        )
        modalScope.attachPresentation(to: landingScope, declaration: modalDeclaration)
        walletScope.path.replaceTestPath([appearanceScope])
        router.tree.rootPath.replaceTestPath([landingScope, modalScope])

        await router.requestRoute(SettingsRoute())

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === landingScope)
        #expect(walletScope.path.count == 2)
        #expect(walletScope.path.first === appearanceScope)
        let authenticationScope = try #require(walletScope.path.last)
        #expect(authenticationScope.route is SettingsRoute)
        #expect(authenticationScope.presentationOrigin === appearanceScope)
        #expect(
            router.routePresentationBinding(from: appearanceScope, matching: .push)
                .wrappedValue?.scope === authenticationScope
        )
    }

    @Test func defaultRootBranchLocalPushBehindModalPreservesActiveLocalScope() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let walletRouteScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let modalScope = RouteScope(id: MessageRoute().id, route: MessageRoute())

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))
                ),
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )
        walletRouteScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        let walletRouteDeclaration = try #require(testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .push))._routeDeclarations.first)
        let modalDeclaration = try #require(
            router.root.definitions.routeAttachments.first {
                $0.routeTypeID == ObjectIdentifier(MessageRoute.self)
            }
        )
        walletRouteScope.attachPresentation(
            to: walletScope,
            declaration: walletRouteDeclaration
        )
        modalScope.attachPresentation(to: router.root, declaration: modalDeclaration)
        walletScope.path.replaceTestPath([walletRouteScope])
        router.tree.rootPath.replaceTestPath([modalScope])

        let match = try #require(router.tree.firstDeclaration(including: SettingsRoute.self)?.declaration)
        let unwindPlan = router.tree.presentationUnwindPlan(after: match)

        #expect(match.lookupStrategy == .defaultRootActiveBranchScope)
        #expect(match.declaration.presentationKind == .push)
        #expect(match.presentationPath === walletScope.path)
        #expect(match.presentingScope === walletRouteScope)
        #expect(match.declaringPath === router.tree.rootPath)
        #expect(match.declaringScope === router.root)
        #expect(unwindPlan.removedScopes.count == 1)
        #expect(unwindPlan.removedScopes.first === modalScope)

        router.routeScopeDidInstallInView(modalScope)
        let requestTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 where router.tree.rootPath.isEmpty == false {
            await Task.yield()
        }

        #expect(router.tree.rootPath.isEmpty)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last === walletRouteScope)
        #expect(router.pendingRoute?.route is SettingsRoute)

        router.routeScopeDidLeaveView(modalScope)
        _ = await requestTask.value

        #expect(walletScope.path.count == 2)
        #expect(walletScope.path.first === walletRouteScope)
        let transactionScope = try #require(walletScope.path.last)
        #expect(transactionScope.route is SettingsRoute)
        #expect(transactionScope.presentationOrigin === walletRouteScope)
        #expect(router.pendingRoute == nil)
        #expect(
            router.root.definitions.routeBinding(for: SettingsRoute.self)?.declaration?
                .presentationKind == .sheet
        )
        #expect(
            router.routePresentationBinding(from: walletRouteScope, matching: .push)
                .wrappedValue?.scope === transactionScope
        )
    }

    @Test func pendingActiveLocalPushResumePreservesResolvedLocalScope() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let walletRouteScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let modalScope = RouteScope(id: MessageRoute().id, route: MessageRoute())

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )
        walletRouteScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)
        walletRouteScope.attachPresentation(
            to: walletScope,
            declaration: try #require(testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .push))._routeDeclarations.first)
        )
        walletScope.path.replaceTestPath([walletRouteScope])
        modalScope.attachPresentation(
            to: router.root,
            declaration: try #require(testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations.first)
        )
        router.tree.rootPath.replaceTestPath([modalScope])

        let match = try #require(router.tree.firstDeclaration(including: TransactionRoute.self)?.declaration)
        router.appendOrPendRoute(
            RouterEngine.NavigationOperation(awaitingHost: .init(route: TransactionRoute(), match: match)),
            waitsForBranchActivation: true
        )
        router.resumePendingRoute(for: AppTab.wallet, in: router.root)

        #expect(router.tree.rootPath.isEmpty)
        #expect(walletScope.path.count == 2)
        #expect(walletScope.path.first === walletRouteScope)
        let transactionScope = try #require(walletScope.path.last)
        #expect(transactionScope.route is TransactionRoute)
        #expect(transactionScope.presentationOrigin === walletRouteScope)
        #expect(router.pendingRoute == nil)
    }

    @Test func branchDeclaredPushBehindModalStillReplacesActiveBranchPath() throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let walletRouteScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let modalScope = RouteScope(id: MessageRoute().id, route: MessageRoute())

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))
                ),
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)
        let modalDeclaration = try #require(
            router.root.definitions.routeAttachments.first {
                $0.routeTypeID == ObjectIdentifier(MessageRoute.self)
            }
        )
        modalScope.attachPresentation(to: router.root, declaration: modalDeclaration)
        walletScope.path.replaceTestPath([walletRouteScope])
        router.tree.rootPath.replaceTestPath([modalScope])

        let match = try #require(router.tree.firstDeclaration(including: SettingsRoute.self)?.declaration)
        let unwindPlan = router.tree.presentationUnwindPlan(after: match)

        #expect(match.lookupStrategy == .defaultRootDeclarations)
        #expect(match.declaration.presentationKind == .push)
        #expect(match.presentationPath === walletScope.path)
        #expect(match.presentingScope === walletScope)
        #expect(match.declaringPath === router.tree.rootPath)
        #expect(match.declaringScope === router.root)
        #expect(unwindPlan.removedScopes.count == 2)
        #expect(unwindPlan.removedScopes.contains { $0 === walletRouteScope })
        #expect(unwindPlan.removedScopes.contains { $0 === modalScope })
    }

    @Test func branchOwnerModalUsesResolvedOwnerWhilePreservingBranchPath() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let walletRouteScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))
                    }
                )
            )
        )
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)
        walletRouteScope.attachPresentation(
            to: walletScope,
            declaration: try #require(testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .push))._routeDeclarations.first)
        )
        walletScope.path.replaceTestPath([walletRouteScope])

        await router.requestRoute(SettingsRoute())

        #expect(walletScope.path.count == 2)
        #expect(walletScope.path.first === walletRouteScope)
        let sheetScope = try #require(walletScope.path.last)
        #expect(sheetScope.route is SettingsRoute)
        #expect(sheetScope.presentationOrigin === walletScope)
        #expect(
            router.routePresentationBinding(from: walletScope, matching: .sheet)
                .wrappedValue?.scope === sheetScope
        )
    }

    @Test func equivalentBranchPushDismissesTopLevelModalWithoutReplacingExistingScope() async throws {
        let router = RouterEngine()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let detailScope = RouteScope(id: HomeDetailRoute().id, route: HomeDetailRoute())
        let modalScope = RouteScope(id: MessageRoute().id, route: MessageRoute())
        let pushDeclaration = try #require(testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations.first)
        let modalDeclaration = try #require(testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations.first)

        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        landingScope.attachTestBranch(homeScope, for: AppTab.home)
        detailScope.attachPresentation(
            to: homeScope,
            declaration: pushDeclaration
        )
        modalScope.attachPresentation(to: landingScope, declaration: modalDeclaration)
        homeScope.path.replaceTestPath([detailScope])
        router.tree.rootPath.replaceTestPath([landingScope, modalScope])
        router.routeScopeDidInstallInView(modalScope)

        let match = RouterEngine.ResolvedRouteTarget(
            tree: router.tree,
            presentingScope: homeScope,
            declaringScope: landingScope,
            declaration: pushDeclaration,
            lookupStrategy: .currentPath
        )
        let requestTask = Task {
            await router.reuseEquivalentRoute(HomeDetailRoute(), at: detailScope,
                plan: router.tree.presentationUnwindPlan(after: match, retaining: detailScope))
        }

        for _ in 0..<10 {
            if router.tree.rootPath.last === landingScope {
                break
            }
            await Task.yield()
        }

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === landingScope)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last === detailScope)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(modalScope)
        #expect(await requestTask.value === detailScope)

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === landingScope)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last === detailScope)
        #expect(router.routePresentationBinding(from: homeScope, matching: .push).wrappedValue?.scope === detailScope)
    }

    @Test func nearestModalDeclarationWinsOverEquivalentRouteInBranch() async throws {
        let router = RouterEngine()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let existingDetailScope = RouteScope(id: HomeDetailRoute().id, route: HomeDetailRoute())
        let modalScope = RouteScope(id: MessageRoute().id, route: MessageRoute())
        let pushDeclaration = try #require(testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations.first)
        let modalDeclaration = try #require(testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations.first)

        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        landingScope.attachTestBranch(homeScope, for: AppTab.home)
        existingDetailScope.attachPresentation(
            to: homeScope,
            declaration: pushDeclaration
        )
        modalScope.attachPresentation(to: landingScope, declaration: modalDeclaration)
        modalScope.defineTestMap(
            id: MessageRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: [pushDeclaration]),
            ]
        )
        homeScope.path.replaceTestPath([existingDetailScope])
        router.tree.rootPath.replaceTestPath([landingScope, modalScope])

        await router.requestRoute(HomeDetailRoute())

        let presentedDetailScope = try #require(router.tree.rootPath.last)
        #expect(router.tree.rootPath.count == 3)
        #expect(presentedDetailScope !== existingDetailScope)
        #expect(presentedDetailScope.route is HomeDetailRoute)
        #expect(presentedDetailScope.presentationOrigin === modalScope)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last === existingDetailScope)
        #expect(router.routePresentationBinding(from: modalScope, matching: .push).wrappedValue?.scope === presentedDetailScope)
    }

    @Test func localSheetDeclarationWinsOverTopLevelDeclarationForSameRoute() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(SettingsRoute())

        let settingsScope = try #require(homeScope.path.last)
        settingsScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )

        await router.requestRoute(MessageRoute())

        #expect(router.tree.rootPath.isEmpty)
        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first?.route is SettingsRoute)
        #expect(homeScope.path.last?.route is MessageRoute)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .sheet).wrappedValue?.scope === homeScope.path.last)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)
    }

    @Test func localSheetOnPushedScopeWinsOverContainerLevelDeclaration() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(walletScope.path.last)

        // Toggle OFF: the pushed scope declares nothing, so the container-level sheet hosts.
        await router.requestRoute(MessageRoute())
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue?.scope === router.tree.rootPath.last)
        #expect(router.routePresentationBinding(from: walletScope, matching: .sheet).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .sheet).wrappedValue == nil)

        router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue = nil
        #expect(walletScope.path.last === settingsScope)

        // Toggle ON: the pushed scope now declares the same route locally and must win.
        settingsScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )

        await router.requestRoute(MessageRoute())
        #expect(router.routePresentationBinding(from: settingsScope, matching: .sheet).wrappedValue?.scope === walletScope.path.last)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: walletScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func presentingTopLevelSheetOverBranchLocalSheetReplacesItRatherThanStacking() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet)) // top-level (shared) sheet
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet)) // branch-local sheet
                    }
                )
            )
        )

        // The branch scope adopts both the top-level and the branch-local sheet (mirrors `.routeBranch`).
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

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
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.fade))) // top-level cover
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet)) // branch-local sheet
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.fade)))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

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

    @Test func nestedModalsOccupySuccessiveModalDepthsAndAncestorReplacementClearsBoth() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations
                    + testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.tree.rootPath.last)
        loginScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(router.tree.rootPath.last)

        #expect(loginScope.lane.depth == 1)
        #expect(settingsScope.lane.depth == 2)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue?.scope === loginScope)
        #expect(router.routePresentationBinding(from: loginScope, matching: .sheet).wrappedValue?.scope === settingsScope)

        await router.requestRoute(MessageRoute())

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last?.route is MessageRoute)
        #expect(router.tree.rootPath.scopes.contains { $0.route is LoginRoute } == false)
        #expect(router.tree.rootPath.scopes.contains { $0.route is SettingsRoute } == false)
    }

    @Test func replacingTopLevelCoverPreservesActiveBranchPushStack() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .cover(.slide)))
                ),
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.slide)))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations
                    + testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

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
        _ = await replacementTask.value

        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first?.route is SettingsRoute)
        #expect(homeScope.path.last?.route is MessageRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .cover(.slide)).wrappedValue?.scope.route is MessageRoute)
    }

    @Test func ancestorCoverRemovesDescendantLocalSheetAndPreservesPushStack() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .cover(.slide)))
                ),
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.slide)))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations
                    + testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(homeScope.path.last)
        settingsScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
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
        _ = await coverTask.value

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
        _ = await replacementTask.value

        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first === settingsScope)
        #expect(homeScope.path.last?.route is MessageRoute)
        #expect(homeScope.path.scopes.contains { $0.route is TransactionRoute } == false)

        router.routePresentationBinding(from: homeScope, matching: .cover(.slide)).wrappedValue = nil

        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last === settingsScope)
        #expect(homeScope.path.scopes.contains { $0.route is TransactionRoute } == false)
    }

    @Test func crawlBackBranchSwitchUsesFixedDeclarationAfterPresentationTeardown() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.home)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        let homeDetailScope = try #require(homeScope.path.last)
        router.routeScopeDidInstallInView(homeDetailScope)

        let requestTask = Task {
            await router.requestRoute(TransactionRoute())
        }

        await Task.yield()

        #expect(router.tree.rootPath.isEmpty)
        #expect(homeScope.path.last === homeDetailScope)

        router.routeScopeDidLeaveView(homeDetailScope)
        _ = await requestTask.value

        #expect(selectedTab() == .wallet)
        #expect(router.tree.rootPath.isEmpty)
        #expect(router.pendingRoute == nil)

        router.resumePendingRoute(for: AppTab.wallet, in: router.root)

        #expect(router.tree.rootPath.isEmpty)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)
        #expect(router.pendingRoute == nil)
        #expect(router.routePresentationBinding(from: walletScope, matching: .push).wrappedValue != nil)
    }

    @Test func unresolvedRoutesAndUndeclaredRoutesAreDropped() async {
        let router = RouterEngine()

        await router.requestRoute(DroppedRoute())
        #expect(router.tree.rootPath.isEmpty)

        await router.requestRoute(SettingsRoute())
        #expect(router.tree.rootPath.isEmpty)
    }

    @Test func routeResolutionReroutePresentsResolvedRoute() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )

        await router.requestRoute(ReroutingRoute())

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last?.route is LoginRoute)
    }

    @Test func routeResolutionRerouteChainStopsWhenAResolvedRouteDrops() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(DroppedRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )

        await router.requestRoute(ReroutingToDroppedRoute())

        #expect(router.tree.rootPath.isEmpty)
    }

    @Test func defaultPresentationResolvesAndDismissesFromDeclaringScope() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())

        let presentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .sheet
        ).wrappedValue)

        #expect(presentation.scope === router.tree.rootPath.last)
        #expect(presentation.scope.presentationDeclaration?.routeTypeID == ObjectIdentifier(SettingsRoute.self))

        router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue = nil

        #expect(router.tree.rootPath.isEmpty)
    }

    @Test func repeatedPresentationOfEquivalentRouteKeepsPresentationIdentity() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
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

        #expect(router.tree.rootPath.count == 1)
        #expect(firstPresentation.id == secondPresentation.id)
        #expect(firstPresentation == secondPresentation)
        #expect(firstPresentation.scope === secondPresentation.scope)
    }

    @Test func repeatedPresentationOfUnequalRouteValueGetsNewPresentationIdentity() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(NumberedRoute.self), presentation: .init(style: .push))._routeDeclarations),
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

        #expect(router.tree.rootPath.count == 1)
        #expect(firstPresentation.id != secondPresentation.id)
        #expect(firstPresentation.scope !== secondPresentation.scope)
        #expect(secondPresentation.scope.route as? NumberedRoute == NumberedRoute(number: 2))
    }

    @Test func presentingEquivalentAncestorUnwindsToExistingScopeInsteadOfRePresenting() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(NumberedRoute.self), presentation: .init(style: .push))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )

        await router.requestRoute(NumberedRoute(number: 1))
        let numberedPresentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .push
        ).wrappedValue)
        let numberedScope = numberedPresentation.scope
        numberedScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(router.tree.rootPath.last)
        #expect(router.tree.rootPath.count == 2)
        #expect(settingsScope.route is SettingsRoute)
        router.routeScopeDidInstallInView(settingsScope)

        let requestTask = Task {
            await router.requestRoute(NumberedRoute(number: 1))
        }

        for _ in 0..<10 {
            if router.tree.rootPath.last === numberedScope {
                break
            }
            await Task.yield()
        }

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === numberedScope)
        #expect(router.routePresentationBinding(from: router.root, matching: .push).wrappedValue?.scope === numberedScope)
        #expect(router.routePresentationBinding(from: numberedScope, matching: .push).wrappedValue == nil)

        router.routeScopeDidLeaveView(settingsScope)
        _ = await requestTask.value

        let finalPresentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .push
        ).wrappedValue)
        #expect(finalPresentation.id == numberedPresentation.id)
        #expect(finalPresentation.scope === numberedScope)
        #expect(router.tree.rootPath.count == 1)
    }

    @Test func presentingEquivalentRouteInInactiveBranchSelectsBranchAndUnwindsThere() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.wallet)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(NumberedRoute.self), presentation: .init(style: .push))
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(NumberedRoute.self), presentation: .init(style: .push))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(NumberedRoute(number: 7))
        let numberedScope = try #require(walletScope.path.last)
        numberedScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
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
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )

        await router.requestRoute(HomeDetailRoute())
        let firstScope = try #require(router.tree.rootPath.last)
        router.routeScopeDidInstallInView(firstScope)

        let requestTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        await Task.yield()

        #expect(router.tree.rootPath.isEmpty)

        router.routeScopeDidLeaveView(firstScope)
        _ = await requestTask.value

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last?.route is SettingsRoute)
    }

    @Test func removingPresentedRouteScopeSynchronizesRouterPath() async throws {
        let root = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            testPush(testDestination(HomeDetailRoute.self))
        }, router: root) { EmptyView() }

        await root.current.present(HomeDetailRoute())
        let pushedScope = try #require(root.engine.tree.rootPath.last)
        #expect(await root.current.unwind(.current))

        #expect(root.engine.tree.routePath(containing: pushedScope) == nil)
        #expect(root.engine.tree.rootPath.isEmpty)
        #expect(root.engine.routePresentationBinding(from: root.engine.root, matching: .push).wrappedValue == nil)
    }

    @Test func routeScopeLeavingViewUninstallsWithoutRemovingRouterPath() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )

        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.tree.rootPath.last)

        router.routeScopeDidInstallInView(pushedScope)
        router.routeScopeDidLeaveView(pushedScope)

        #expect(pushedScope.isInstalledInView == false)
        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === pushedScope)
        #expect(router.routePresentationBinding(from: router.root, matching: .push).wrappedValue != nil)
    }

    @Test func installedModalDismissalRetainsImmediateGraphSemantics() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let sheetScope = try #require(router.tree.rootPath.last)
        router.routeScopeDidInstallInView(sheetScope)

        let presentation = router.routePresentationBinding(from: router.root, matching: .sheet)
        presentation.wrappedValue = nil

        #expect(router.tree.rootPath.isEmpty)
        #expect(presentation.wrappedValue == nil)

        router.routeScopeDidLeaveView(sheetScope)
    }

    @Test func presentationDismissalClearsBranchPathsOwnedByRemovedScope() throws {
        let router = RouterEngine()
        let modalScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let branchScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let detailScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let modalDeclaration = try #require(testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations.first)

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: [modalDeclaration]),
            ]
        )
        modalScope.attachPresentation(to: router.root, declaration: modalDeclaration)
        modalScope.attachTestBranch(branchScope, for: AppTab.wallet)
        branchScope.path.replaceTestPath([detailScope])
        router.tree.rootPath.replaceTestPath([modalScope])

        router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue = nil

        #expect(router.tree.rootPath.isEmpty)
        #expect(router.tree.routePath(containing: branchScope) == nil)
    }

    @Test func snapshotPresentationWriteBackDoesNotTrimLiveRootPath() async throws {
        let router = RouterEngine()
        let retainedScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let coverScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let pushedScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let coverDeclaration = try #require(testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations.first)
        let pushDeclaration = try #require(testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations.first)

        coverScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: [pushDeclaration]),
            ]
        )
        coverScope.attachPresentation(to: retainedScope, declaration: coverDeclaration)
        pushedScope.attachPresentation(to: coverScope, declaration: pushDeclaration)
        router.tree.rootPath.replaceTestPath([retainedScope, coverScope, pushedScope])
        router.routeScopeDidInstallInView(coverScope)
        router.routeScopeDidInstallInView(pushedScope)

        let unwindTask = Task {
            await router.unwind(.nearestModal)
        }
        for _ in 0..<10 where router.hasOutgoingPresentations == false {
            await Task.yield()
        }

        let binding = router.routePresentationBinding(from: coverScope, matching: .push)
        #expect(binding.wrappedValue?.scope === pushedScope)
        binding.wrappedValue = nil

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === retainedScope)

        router.routeScopeDidLeaveView(coverScope)
        router.routeScopeDidLeaveView(pushedScope)
        #expect(await unwindTask.value)
    }

    @Test func routeScopeViewLifecycleResumesEveryWaiterForEachTransition() async {
        let router = RouterEngine()
        let scope = RouteScope(id: RootRoute().id, route: RootRoute())

        let firstInstallWaiter = Task {
            await scope.waitUntilInstalled()
        }
        let secondInstallWaiter = Task {
            await scope.waitUntilInstalled()
        }
        await Task.yield()

        router.routeScopeDidInstallInView(scope)
        await firstInstallWaiter.value
        await secondInstallWaiter.value
        #expect(scope.isInstalledInView)

        let firstUninstallWaiter = Task {
            await scope.waitUntilUninstalled()
        }
        let secondUninstallWaiter = Task {
            await scope.waitUntilUninstalled()
        }
        await Task.yield()

        router.routeScopeDidLeaveView(scope)
        await firstUninstallWaiter.value
        await secondUninstallWaiter.value
        #expect(scope.isInstalledInView == false)
    }

    @Test func combinedUnwindPlanKeepsShallowestBoundaryForTheSamePath() {
        let router = RouterEngine()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let thirdScope = RouteScope(id: AlertRoute().id, route: AlertRoute())
        router.tree.rootPath.replaceTestPath([firstScope, secondScope, thirdScope])

        let plan = RouteTree.UnwindPlan(retaining: [secondScope, firstScope])

        #expect(plan.retainedScopes.count == 1)
        #expect(plan.retainedScopes.first === firstScope)
        #expect(plan.removedScopes.count == 2)
        #expect(plan.removedScopes[0] === secondScope)
        #expect(plan.removedScopes[1] === thirdScope)
    }

    @Test func unwindToRootClearsAppRootAndActiveBranchFromDeepWithinBranch() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())
        #expect(walletScope.path.count == 1)
        #expect(router.tree.rootPath.count == 1)

        // `.root` reaches past the current branch path to the app root.
        await router.resetToRoot()
        #expect(router.tree.rootPath.isEmpty)
        #expect(router.tree.routePath(containing: walletScope) == nil)
    }

    @Test func unwindToRootClearsActiveBranchPushAndAdoptedModal() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(SettingsRoute())
        await router.requestRoute(MessageRoute())

        #expect(router.tree.rootPath.count == 1)
        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first?.route is SettingsRoute)
        #expect(homeScope.path.last?.route is MessageRoute)

        await router.resetToRoot()

        #expect(router.tree.rootPath.isEmpty)
        #expect(router.tree.routePath(containing: homeScope) == nil)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func unwindToRootClearsInactiveBranchStacksOwnedByRemovedScope() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                        testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations
                    + testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        await router.requestRoute(MessageRoute())
        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))
        await router.requestRoute(TransactionRoute())

        #expect(selectedTab() == .wallet)
        #expect(router.tree.rootPath.count == 1)
        #expect(homeScope.path.count == 2)
        #expect(walletScope.path.count == 1)

        await router.resetToRoot()

        #expect(router.tree.rootPath.isEmpty)
        #expect(router.tree.routePath(containing: homeScope) == nil)
        #expect(router.tree.routePath(containing: walletScope) == nil)
        #expect(router.routePresentationBinding(from: homeScope, matching: .push).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func unwindToRootPreservesInactiveBranchPushStackButClearsModal() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.home)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                        testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations
                    + testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        await router.requestRoute(MessageRoute())
        router.root.setActiveBranch(AnyHashable(AppTab.wallet))
        await router.requestRoute(TransactionRoute())
        await router.requestRoute(SettingsRoute())

        #expect(selectedTab() == .wallet)
        // Branches preserve independent push paths, but share the modal lane. Presenting the
        // wallet sheet retires the home sheet before the root unwind begins.
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(walletScope.path.count == 2)

        await router.resetToRoot()

        #expect(router.tree.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .push).wrappedValue?.scope === homeScope.path.last)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
        #expect(walletScope.path.isEmpty)
    }

    @Test func unwindFromBranchDestinationKeepsTheAppRoot() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())
        #expect(walletScope.path.count == 1)

        await Router(engine: router).unwind(from: SettingsRoute.self)
        #expect(walletScope.path.isEmpty)
        #expect(router.tree.rootPath.count == 1)
    }

    @Test func modalReplacementWaitsForInstalledRouteScopeToLeaveView() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.tree.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let replacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.tree.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.tree.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        _ = await replacementTask.value

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last?.route is SettingsRoute)
    }

    @Test func sheetToCoverReplacementWaitsForOldScopeToLeaveView() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.tree.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let replacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.tree.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.tree.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        _ = await replacementTask.value

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue?.scope === router.tree.rootPath.last)
    }

    @Test func coverToSheetReplacementWaitsForOldScopeToLeaveView() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.tree.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let replacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.tree.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.tree.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        _ = await replacementTask.value

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue?.scope === router.tree.rootPath.last)
    }

    @Test func pendingModalReplacementUsesLatestRequest() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations
                    + testDeclaration(testDestination(AlertRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.tree.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let firstReplacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.tree.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.tree.rootPath.isEmpty)

        let latestReplacementTask = Task {
            await router.requestRoute(AlertRoute())
        }

        await Task.yield()
        #expect(router.tree.rootPath.isEmpty)

        router.routeScopeDidLeaveView(loginScope)
        _ = await firstReplacementTask.value
        _ = await latestReplacementTask.value

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last?.route is AlertRoute)
    }

    @Test func namedRootRetainsIdentityAcrossNativeTeardown() async {
        let engine = RouterEngine(routes: RootRouteMap(id: "custom") {
            testPush(testDestination(HomeDetailRoute.self))
        })
        engine.routeScopeDidInstallInView(engine.root)
        engine.routeScopeDidLeaveView(engine.root)
        #expect(engine.root.id == AnyHashable("custom"))
        await engine.present(HomeDetailRoute())
        #expect(await engine.resetToRoot())
        #expect(engine.tree.rootPath.isEmpty)
    }

    @Test func cancellingPresentationWaitingForNavigationRemovesPendingRequest() async {
        let router = RouterEngine()
        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        let transaction = router.beginNavigationOperation()

        let presentationTask = Task {
            await router.present(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.pendingRoute != nil {
                break
            }
            await Task.yield()
        }

        #expect(router.pendingRoute != nil)
        presentationTask.cancel()
        await presentationTask.value

        #expect(router.pendingRoute == nil)
        #expect(router.tree.rootPath.isEmpty)
        router.finishNavigationOperation(transaction)
    }

    @Test func unwindFromBranchPresentationKeepsPresentedTopLevelScope() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: Branch(AppTab.home) {
                testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.fade)))
            }.routeScopeDeclarations
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.fade)))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(MessageRoute())
        #expect(homeScope.path.count == 1)

        await router.unwind(.current)

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === landingScope)
        #expect(homeScope.path.isEmpty)
    }

    @Test func unwindFromBranchPushCanTargetAncestorRouteForContinuation() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.fade)))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .cover(.fade)))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())

        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is SettingsRoute)

        let didUnwind = await Router(engine: router).unwind(from: SettingsRoute.self)
        if didUnwind {
            await router.requestRoute(MessageRoute())
            router.resumePendingRoute(for: AppTab.home, in: landingScope)
        }

        #expect(didUnwind)
        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === landingScope)
        #expect(walletScope.path.isEmpty)
        #expect(selectedTab() == .home)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is MessageRoute)
    }

    @Test func sequentialUnwindThenPresentCutsPathBeforeWaitingForAllRemovedScopes() async {
        let router = RouterEngine()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let thirdScope = RouteScope(id: AlertRoute().id, route: AlertRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )

        router.tree.rootPath.replaceTestPath([firstScope, secondScope, thirdScope])
        router.routeScopeDidInstallInView(firstScope)
        router.routeScopeDidInstallInView(secondScope)
        router.routeScopeDidInstallInView(thirdScope)

        let unwindTask = Task {
            guard await router.resetToRoot() else {
                return
            }

            await router.present(SettingsRoute())
        }

        await Task.yield()

        #expect(router.tree.rootPath.isEmpty)

        router.routeScopeDidLeaveView(firstScope)
        router.routeScopeDidLeaveView(secondScope)
        await Task.yield()

        #expect(router.tree.rootPath.isEmpty)

        router.routeScopeDidLeaveView(thirdScope)
        _ = await unwindTask.value

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last?.route is SettingsRoute)
    }

    @Test func unwindPreservesDescendantPresentationBindingsUntilAncestorLeavesView() async throws {
        let router = RouterEngine()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let profileScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(RootRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations),
            ]
        )
        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        profileScope.attachPresentation(
            to: homeScope,
            declaration: try #require(homeScope.routeAttachments.first { $0.presentationKind == .sheet })
        )
        router.tree.rootPath.replaceTestPath([landingScope, profileScope])
        router.routeScopeDidInstallInView(landingScope)
        router.routeScopeDidInstallInView(profileScope)

        let unwindTask = Task {
            await router.resetToRoot()
        }

        await Task.yield()

        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue != nil)

        router.routeScopeDidLeaveView(profileScope)
        router.routeScopeDidLeaveView(landingScope)
        _ = await unwindTask.value

        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func scopedCurrentUnwindKeepsModalPushSnapshotUntilSheetLeavesView() async throws {
        let router = RouterEngine()
        let sheetScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let pushedScope = RouteScope(id: HomeDetailRoute().id, route: HomeDetailRoute(), parent: sheetScope)

        router.root.defineTestMap(
            id: "root",
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        sheetScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        sheetScope.attachPresentation(
            to: router.root,
            declaration: try #require(router.root.routeAttachments.first { $0.presentationKind == .sheet })
        )
        pushedScope.attachPresentation(
            to: sheetScope,
            declaration: try #require(sheetScope.routeAttachments.first { $0.presentationKind == .push })
        )
        router.tree.rootPath.replaceTestPath([sheetScope, pushedScope])
        router.routeScopeDidInstallInView(sheetScope)
        router.routeScopeDidInstallInView(pushedScope)

        let unwind = Task { await Router(engine: router, scope: sheetScope).unwind(.current) }
        await Task.yield()

        #expect(router.hasOutgoingPresentations)
        #expect(router.routePresentationBinding(from: sheetScope, matching: .push).wrappedValue?.scope === pushedScope)
        #expect(sheetScope.routeAttachments.contains { $0.presentationKind == .push })

        router.routeScopeDidLeaveView(pushedScope)
        router.routeScopeDidLeaveView(sheetScope)
        #expect(await unwind.value)
        #expect(router.hasOutgoingPresentations == false)
    }

    @Test func capturedAncestorUnwindRemovesBothNestedSheetsInOnePlan() async throws {
        let router = RouterEngine()
        let sheetA = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let sheetB = RouteScope(id: SettingsRoute().id, route: SettingsRoute())

        router.root.defineTestMap(
            id: "root",
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        sheetA.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        sheetA.attachPresentation(
            to: router.root,
            declaration: try #require(router.root.routeAttachments.first { $0.presentationKind == .sheet })
        )
        sheetB.attachPresentation(
            to: sheetA,
            declaration: try #require(sheetA.routeAttachments.first { $0.presentationKind == .sheet })
        )
        router.tree.rootPath.replaceTestPath([sheetA, sheetB])
        router.routeScopeDidInstallInView(sheetA)
        router.routeScopeDidInstallInView(sheetB)

        let unwind = Task { await UnwindRouteAction(router: router, routeScope: sheetA)() }
        for _ in 0..<10 where !router.tree.rootPath.isEmpty {
            await Task.yield()
        }

        #expect(router.tree.rootPath.isEmpty)
        #expect(router.hasOutgoingPresentations)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: sheetA, matching: .sheet).wrappedValue?.scope === sheetB)

        router.routeScopeDidLeaveView(sheetB)
        router.routeScopeDidLeaveView(sheetA)
        #expect(await unwind.value)
        #expect(router.hasOutgoingPresentations == false)
    }

    @Test func sheetBindingDismissalPreservesNestedPushUntilSheetLeavesView() async throws {
        let router = RouterEngine()
        let sheetScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let pushedScope = RouteScope(id: HomeDetailRoute().id, route: HomeDetailRoute(), parent: sheetScope)

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        sheetScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        sheetScope.attachPresentation(
            to: router.root,
            declaration: try #require(router.root.routeAttachments.first { $0.presentationKind == .sheet })
        )
        pushedScope.attachPresentation(
            to: sheetScope,
            declaration: try #require(sheetScope.routeAttachments.first { $0.presentationKind == .push })
        )
        router.tree.rootPath.replaceTestPath([sheetScope, pushedScope])
        router.routeScopeDidInstallInView(sheetScope)
        router.routeScopeDidInstallInView(pushedScope)

        router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue = nil

        #expect(router.tree.rootPath.isEmpty)
        #expect(router.hasOutgoingPresentations)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: sheetScope, matching: .push).wrappedValue?.scope === pushedScope)
        #expect(sheetScope.routeAttachments.contains { $0.presentationKind == .push })

        router.routeScopeDidLeaveView(pushedScope)
        router.routeScopeDidLeaveView(sheetScope)
        for _ in 0..<10 where router.hasOutgoingPresentations {
            await Task.yield()
        }
        #expect(router.hasOutgoingPresentations == false)
    }

    @Test func targetedUnwindClearsCoverHostedByRetainedNonRootScopeWhilePreservingNestedPush() async throws {
        let router = RouterEngine()
        let paymentMethodsID = AnyHashable("paymentMethods")
        let paymentMethodsScope = RouteScope(id: paymentMethodsID, route: CardsListRoute())
        let coverScope = RouteScope(id: AddMethodRoute().id, route: AddMethodRoute())
        let pushedScope = RouteScope(id: AddCardRoute().id, route: AddCardRoute())

        paymentMethodsScope.defineTestMap(
            id: paymentMethodsID,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(AddMethodRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations),
            ]
        )
        coverScope.defineTestMap(
            id: AddMethodRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(AddCardRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        coverScope.attachPresentation(
            to: paymentMethodsScope,
            declaration: try #require(
                paymentMethodsScope.routeAttachments.first { $0.presentationKind == .cover(.slide) }
            )
        )
        pushedScope.attachPresentation(
            to: coverScope,
            declaration: try #require(
                coverScope.routeAttachments.first { $0.presentationKind == .push }
            )
        )
        router.tree.rootPath.replaceTestPath([paymentMethodsScope, coverScope, pushedScope])
        router.routeScopeDidInstallInView(coverScope)
        router.routeScopeDidInstallInView(pushedScope)

        let unwindTask = Task {
            await Router(engine: router).unwind(from: AddMethodRoute.self)
        }

        for _ in 0..<10 where router.hasOutgoingPresentations == false {
            await Task.yield()
        }

        #expect(router.tree.rootPath.scopes.elementsEqual([paymentMethodsScope], by: { $0 === $1 }))
        #expect(
            router.routePresentationBinding(from: paymentMethodsScope, matching: .cover(.slide))
                .wrappedValue == nil
        )
        #expect(
            router.routePresentationBinding(from: coverScope, matching: .push)
                .wrappedValue?.scope === pushedScope
        )

        router.routeScopeDidLeaveView(coverScope)
        router.routeScopeDidLeaveView(pushedScope)

        #expect(await unwindTask.value)
        #expect(router.hasOutgoingPresentations == false)
    }

    @Test func rootUnwindPreservesBranchDescendantPresentationBindingUntilAncestorLeavesView() async throws {
        let router = RouterEngine()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let profileScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(RootRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations),
            ]
        )
        landingScope.attachPresentation(
            to: router.root,
            declaration: try #require(router.root.routeAttachments.first { $0.presentationKind == .cover(.slide) })
        )

        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        profileScope.attachPresentation(
            to: homeScope,
            declaration: try #require(homeScope.routeAttachments.first { $0.presentationKind == .sheet })
        )
        homeScope.path.replaceTestPath([profileScope])
        router.tree.rootPath.replaceTestPath([landingScope])

        router.routeScopeDidInstallInView(landingScope)
        router.routeScopeDidInstallInView(profileScope)

        let unwindTask = Task {
            await router.resetToRoot()
        }

        for _ in 0..<10 {
            if router.hasOutgoingPresentations {
                break
            }
            await Task.yield()
        }

        #expect(router.tree.rootPath.isEmpty)
        #expect(router.tree.routePath(containing: homeScope) == nil)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue?.scope === profileScope)

        router.routeScopeDidLeaveView(landingScope)
        router.routeScopeDidLeaveView(profileScope)
        _ = await unwindTask.value

        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func rootUnwindPreservesDeepBranchPushStackWhileLandingCoverDismisses() async throws {
        let router = RouterEngine()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let settingsScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let authenticationScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let detailScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(RootRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations),
            ]
        )
        landingScope.attachPresentation(
            to: router.root,
            declaration: try #require(router.root.routeAttachments.first { $0.presentationKind == .cover(.slide) })
        )
        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))
        settingsScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(settingsScope, for: AppTab.wallet)

        authenticationScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        authenticationScope.attachPresentation(
            to: settingsScope,
            declaration: try #require(settingsScope.routeAttachments.first { $0.presentationKind == .push })
        )
        detailScope.attachPresentation(
            to: authenticationScope,
            declaration: try #require(authenticationScope.routeAttachments.first { $0.presentationKind == .push })
        )
        settingsScope.path.replaceTestPath([authenticationScope, detailScope])
        router.tree.rootPath.replaceTestPath([landingScope])

        router.routeScopeDidInstallInView(landingScope)
        router.routeScopeDidInstallInView(authenticationScope)
        router.routeScopeDidInstallInView(detailScope)

        let unwindTask = Task {
            await router.resetToRoot()
        }

        for _ in 0..<10 {
            if router.hasOutgoingPresentations {
                break
            }
            await Task.yield()
        }

        #expect(router.tree.routePath(containing: settingsScope) == nil)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .push).wrappedValue?.scope === authenticationScope)
        #expect(router.routePresentationBinding(from: authenticationScope, matching: .push).wrappedValue?.scope === detailScope)

        router.routeScopeDidLeaveView(landingScope)
        router.routeScopeDidLeaveView(authenticationScope)
        router.routeScopeDidLeaveView(detailScope)
        _ = await unwindTask.value

        #expect(router.routePresentationBinding(from: settingsScope, matching: .push).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: authenticationScope, matching: .push).wrappedValue == nil)
    }

    @Test func routeAppendPreservesDeepBranchPushStackWhileReplacingAncestorModal() async throws {
        let router = RouterEngine()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let settingsScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let appearanceScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let authenticationScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(RootRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations
                    + testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        landingScope.attachPresentation(
            to: router.root,
            declaration: try #require(router.root.routeAttachments.first { $0.presentationKind == .cover(.slide) })
        )
        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))
        settingsScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(settingsScope, for: AppTab.wallet)

        appearanceScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        appearanceScope.attachPresentation(
            to: settingsScope,
            declaration: try #require(settingsScope.routeAttachments.first { $0.presentationKind == .push })
        )
        authenticationScope.attachPresentation(
            to: appearanceScope,
            declaration: try #require(appearanceScope.routeAttachments.first { $0.presentationKind == .push })
        )
        settingsScope.path.replaceTestPath([appearanceScope, authenticationScope])
        router.tree.rootPath.replaceTestPath([landingScope])
        router.routeScopeDidInstallInView(landingScope)

        let requestTask = Task {
            await router.requestRoute(MessageRoute())
        }

        for _ in 0..<10 {
            if router.hasOutgoingPresentations {
                break
            }
            await Task.yield()
        }

        #expect(router.tree.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .push).wrappedValue?.scope === appearanceScope)
        #expect(router.routePresentationBinding(from: appearanceScope, matching: .push).wrappedValue?.scope === authenticationScope)

        router.routeScopeDidLeaveView(landingScope)
        _ = await requestTask.value

        #expect(router.hasOutgoingPresentations == false)
        #expect(router.tree.rootPath.last?.route is MessageRoute)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue?.scope === router.tree.rootPath.last)
    }

    @Test func routeAppendDoesNotPreservePushHostedByRetainedScopeWhileNestedModalLeaves() async throws {
        let router = RouterEngine()
        #if os(iOS)
        if #unavailable(iOS 18) {
            if let workaround = router.ios17NavigationStackPushWorkaround as? IOS17NavigationStackPushWorkaround {
                // This fixture owns fake host exits explicitly. Parallel test work must
                // not let the production missing-callback deadline synthesize them.
                workaround.viewExitTimeout = .seconds(30)
            }
        }
        #endif
        let appearanceScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let authenticationScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let sheetScope = RouteScope(id: MessageRoute().id, route: MessageRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        appearanceScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations
                    + testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))._routeDeclarations
                    + testDeclaration(testDestination(AlertRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        authenticationScope.defineTestMap(
            id: SettingsRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )

        appearanceScope.attachPresentation(
            to: router.root,
            declaration: try #require(router.root.routeAttachments.first { $0.routeType == LoginRoute.self })
        )
        authenticationScope.attachPresentation(
            to: appearanceScope,
            declaration: try #require(appearanceScope.routeAttachments.first { $0.routeType == SettingsRoute.self })
        )
        sheetScope.attachPresentation(
            to: authenticationScope,
            declaration: try #require(authenticationScope.routeAttachments.first { $0.routeType == MessageRoute.self })
        )
        router.tree.rootPath.replaceTestPath([appearanceScope, authenticationScope, sheetScope])
        router.routeScopeDidInstallInView(authenticationScope)
        router.routeScopeDidInstallInView(sheetScope)

        let requestTask = Task {
            await router.requestRoute(TransactionRoute())
        }

        let preparationDeadline = ContinuousClock.now + .seconds(5)
        while !router.tree.rootPath.scopes.elementsEqual([appearanceScope], by: { $0 === $1 }),
              ContinuousClock.now < preparationDeadline {
            await Task.yield()
        }

        #expect(router.tree.rootPath.scopes.elementsEqual([appearanceScope], by: { $0 === $1 }))
        #expect(router.routePresentationBinding(from: appearanceScope, matching: .push).wrappedValue == nil)

        router.routeScopeDidLeaveView(sheetScope)
        let supersedingTask = Task {
            await router.requestRoute(AlertRoute())
        }

        let supersessionDeadline = ContinuousClock.now + .seconds(5)
        while !((router.bufferedPresentationRequest?.route ?? router.pendingRoute?.route) is AlertRoute),
              ContinuousClock.now < supersessionDeadline {
            await Task.yield()
        }

        #expect(router.hasOutgoingPresentations == false)
        #expect(router.routePresentationBinding(from: appearanceScope, matching: .push).wrappedValue == nil)
        #expect((router.bufferedPresentationRequest?.route ?? router.pendingRoute?.route) is AlertRoute)

        router.routeScopeDidLeaveView(authenticationScope)
        _ = await requestTask.value
        _ = await supersedingTask.value

        #expect(router.pendingRoute == nil)
        #expect(router.tree.rootPath.count == 2)
        #expect(router.tree.rootPath.last?.route is AlertRoute)
    }

    @Test func unwindSnapshotDoesNotPreservePushPresentationBindingWithoutDepartingModal() async throws {
        let router = RouterEngine()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let settingsScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let authenticationScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))
        settingsScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(settingsScope, for: AppTab.wallet)

        authenticationScope.attachPresentation(
            to: settingsScope,
            declaration: try #require(settingsScope.routeAttachments.first { $0.presentationKind == .push })
        )
        settingsScope.path.replaceTestPath([authenticationScope])
        router.tree.rootPath.replaceTestPath([landingScope])

        router.routeScopeDidInstallInView(authenticationScope)

        let unwindTask = Task {
            await router.unwindAndWait(.current)
        }

        for _ in 0..<10 {
            if router.hasOutgoingPresentations {
                break
            }
            await Task.yield()
        }

        #expect(settingsScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .push).wrappedValue == nil)

        router.routeScopeDidLeaveView(authenticationScope)
        _ = await unwindTask.value
    }

    @Test func routeAppendAnimatesOnlyOutermostPushDuringMultiScreenPop() async throws {
        let router = RouterEngine()
        let appearanceScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let authenticationScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .push))._routeDeclarations
                    + testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        appearanceScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        appearanceScope.attachPresentation(
            to: router.root,
            declaration: try #require(router.root.routeAttachments.first { $0.routeType == LoginRoute.self })
        )
        authenticationScope.attachPresentation(
            to: appearanceScope,
            declaration: try #require(appearanceScope.routeAttachments.first { $0.routeType == SettingsRoute.self })
        )
        router.tree.rootPath.replaceTestPath([appearanceScope, authenticationScope])
        router.routeScopeDidInstallInView(appearanceScope)
        router.routeScopeDidInstallInView(authenticationScope)

        let requestTask = Task {
            await router.requestRoute(TransactionRoute())
        }

        for _ in 0..<10 where router.tree.rootPath.isEmpty == false {
            await Task.yield()
        }

        #expect(router.tree.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .push).wrappedValue == nil)
        #expect(
            router.routePresentationBinding(from: appearanceScope, matching: .push)
                .wrappedValue == nil
        )
        #expect(
            router.pushPresentationDismissalDisablesAnimations(
                from: router.root,
                hostedBy: router.root.presentationHostID
            ) == false
        )
        #expect(
            router.pushPresentationDismissalDisablesAnimations(
                from: appearanceScope,
                hostedBy: appearanceScope.presentationHostID
            )
        )

        router.routeScopeDidLeaveView(authenticationScope)
        router.routeScopeDidLeaveView(appearanceScope)
        _ = await requestTask.value

        #expect(router.hasOutgoingPresentations == false)
        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last?.route is TransactionRoute)
    }

    @Test func inactiveBranchPathIsPreservedWhenActiveBranchChanges() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.home)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        let homeDetailScope = try #require(homeScope.path.last)

        router.root.setActiveBranch(AnyHashable(AppTab.wallet))

        #expect(selectedTab() == .wallet)
        #expect(router.tree.rootPath.isEmpty)
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

    @Test func inactiveBranchPushPresentationBindingStaysStableWhenActiveBranchChanges() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

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
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: Branch(AppTab.home) {
                testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .sheet))
            }.routeScopeDeclarations
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(HomeDetailRoute())

        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue != nil)

        router.root.setActiveBranch(AnyHashable(AppTab.wallet))

        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func presentingModalInSiblingBranchClearsSharedModalLane() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .sheet))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .sheet))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(HomeDetailRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(TransactionRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        #expect(homeScope.path.last?.route is HomeDetailRoute)

        router.root.setActiveBranch(AnyHashable(AppTab.wallet))
        await router.requestRoute(TransactionRoute())

        #expect(homeScope.path.isEmpty)
        #expect(walletScope.path.last?.route is TransactionRoute)

        router.root.setActiveBranch(AnyHashable(AppTab.home))
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    #if DEBUG
    @Test func routeLookupTraceDescribesSearchOrder() {
        let event = DepartureLogEvent.routeLookupStarted(
            routeType: SettingsRoute.self,
            activePath: "RootRoute › LoginRoute › SettingsRoute"
        )
        let isTrace = if case .trace = event.logLevel { true } else { false }
        let expectedMessage = "looking up SettingsRoute"
            + " | strategy=surviving navigation ancestry, nearest scope first"
            + "\n  active path: RootRoute › LoginRoute › SettingsRoute"

        #expect(isTrace)
        #expect(event.message == expectedMessage)
    }

    @Test func missingRouteDeclarationWarningPreservesRouteContext() {
        let warning = DepartureLogTrace.$id.withValue("r:12345678") {
            DepartureWarningEvent.routeDroppedNoDeclaration(
                routeType: SettingsRoute.self
            ).renderedMessage
        }

        #expect(
            warning
                == "[route][r:12345678] ⊘ dropped \(String(reflecting: SettingsRoute.self))"
                    + " — no declaration found"
        )
    }

    @Test func ancestorPushLookupExplainsSingleMultiScopeTrim() throws {
        let router = RouterEngine()
        let ancestorScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let firstDescendant = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let secondDescendant = RouteScope(id: SettingsRoute().id, route: SettingsRoute())

        ancestorScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(MessageRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.tree.rootPath.replaceTestPath([ancestorScope, firstDescendant, secondDescendant])

        let match = try #require(router.tree.firstDeclaration(including: MessageRoute.self)?.declaration)
        let plan = router.tree.presentationUnwindPlan(after: match)
        let expectedDescription = "MessageRoute[push] • local scope"
            + " • lookup=current route path, nearest scope first"

        #expect(match.lookupStrategy == .currentPath)
        #expect(match.departureDebugDescription == expectedDescription)
        #expect(plan.retainedScopes.count == 1)
        #expect(plan.retainedScopes.first === ancestorScope)
        #expect(plan.removedScopes.count == 2)
        #expect(plan.removedScopes[0] === firstDescendant)
        #expect(plan.removedScopes[1] === secondDescendant)
    }

    @Test func unwindRequestLogMessagesDescribeTheirActualTargets() {
        #expect(
            DepartureLogEvent.unwindRequested(target: .routeType(SettingsRoute.self)).message
                == "requested from SettingsRoute"
        )
        #expect(
            DepartureLogEvent.unwindRequested(target: .policy(.current)).message
                == "requested current"
        )
        #expect(
            DepartureLogEvent.unwindPreviousRequested.message
                == "requested to previous route (scope-anchored)"
        )
    }

    @Test func presentationAndUnwindTraceCodesUseUniqueUUIDPrefixes() {
        let firstPresentation = DepartureLogTrace.nextID(prefix: "r")
        let secondPresentation = DepartureLogTrace.nextID(prefix: "r")
        let unwind = DepartureLogTrace.nextID(prefix: "u")

        #expect(firstPresentation.hasPrefix("r:"))
        #expect(secondPresentation.hasPrefix("r:"))
        #expect(unwind.hasPrefix("u:"))
        #expect(firstPresentation.count == 10)
        #expect(secondPresentation.count == 10)
        #expect(unwind.count == 10)
        #expect(Set([firstPresentation, secondPresentation, unwind]).count == 3)
    }

    @Test func branchScopeRegistrationIsIdempotentAndKeepsDebugIdentityAfterUnregister() {
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let branchScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)

        #expect(parentScope.attachTestBranch(branchScope, for: AppTab.home))
        #expect(parentScope.attachTestBranch(branchScope, for: AppTab.home) == false)
        #expect(branchScope.departureDebugDescription == "branchScope#home")

        parentScope.detachTestBranch(branchScope, for: AppTab.home)
        parentScope.detachTestBranch(branchScope, for: AppTab.home)

        #expect(branchScope.parent == nil)
        #expect(branchScope.departureDebugDescription == "branchScope#home")
    }
    #endif

}
