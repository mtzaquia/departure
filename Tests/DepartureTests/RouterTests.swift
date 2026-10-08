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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )

        await owner.current.present(HomeDetailRoute())

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is HomeDetailRoute)

        await owner.current.unwind(to: .topmostAncestor)

        #expect(router.defaultSpace.rootPath.isEmpty)

        router.defaultSpace.rootPath.replaceTestPath([RouteScope(id: RootRoute().id, route: RootRoute())])
        await owner.current.perform(RecordingProbeAction(recorder: actionRecorder))

        #expect(await actionRecorder.values() == [true])
    }

    @Test func routePhaseTracksCurrentRouteScope() {
        let router = RouterEngine()
        let routeScope = RouteScope(id: RootRoute().id, route: RootRoute())

        #expect(router.routePhase(for: router.root) == .active)
        #expect(router.routePhase(for: routeScope) == .inactive)

        router.mutateRouteGraph {
            router.defaultSpace.rootPath.replaceTestPath([routeScope])
        }

        #expect(router.routePhase(for: router.root) == .inactive)
        #expect(router.routePhase(for: routeScope) == .active)
    }

    @Test func deferredBranchHostTeardownPreservesMapAndLogicalRoutePhase() async {
        let engine = RouterEngine(routes: RootRouteMap { Branches { Branch(AppTab.home) {
            Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() })
        } } })
        let home = engine.root.branchScopes[AppTab.home]!
        let teardownDelivery = ViewLifecycleTeardownDelivery()
        let lifecycleID = UUID()
        teardownDelivery.install(lifecycleID)
        let teardownTask = teardownDelivery.schedule(for: lifecycleID) { engine.routeScopeDidLeaveView(home) }
        await teardownTask.value
        #expect(engine.root.branchScopes[AppTab.home] === home)
        #expect(home.firstRouteAttachment(for: HomeDetailRoute.self) != nil)
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
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        #expect(router.defaultSpace.currentRouteScope === homeScope)
        #expect(router.defaultSpace.currentRoutePath === homeScope.path)

        await router.requestRoute(HomeDetailRoute())

        #expect(router.defaultSpace.currentRouteScope === homeScope.path.last)
        #expect(router.defaultSpace.currentRoutePath === homeScope.path)
    }

    @Test func routePhaseTreatsActiveBranchRootAsCurrentScope() {
        let router = RouterEngine()
        let containerScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)

        router.mutateRouteGraph {
            router.defaultSpace.rootPath.replaceTestPath([containerScope])
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
            router.defaultSpace.rootPath.replaceTestPath([containerScope])
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        router.mutateRouteGraph {
            router.defaultSpace.rootPath.replaceTestPath([containerScope])
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )

        let didUnwind = await router.unwind(to: .id("missing"))
        if didUnwind {
            await router.present(SettingsRoute())
        }

        #expect(didUnwind == false)
        #expect(router.defaultSpace.rootPath.isEmpty)
    }

    @Test func publicUnwindReportsNoRouteAtRoot() async {
        let router = RouterEngine()

        #expect(await router.unwind(to: .root) == false)
        #expect(await router.unwind(to: .topmostAncestor) == false)
        #expect(router.defaultSpace.rootPath.isEmpty)
    }

    @Test func publicUnwindReportsMissingNearestBranch() async {
        let router = RouterEngine()

        #expect(await router.unwind(to: .nearestBranch) == false)
        #expect(router.defaultSpace.rootPath.isEmpty)
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
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
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
        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.pendingRoute == nil)

        let homeScope = router.root.branchScopes[AppTab.home]!
        router.resumePendingRoute(for: AppTab.home, in: router.root)

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(router.pendingRoute == nil)
    }

    @Test func predefinedBranchNavigationPreservesContainerWithoutDeclarationInstallation() async {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(RouteDestination(RootRoute.self) { _, _ in EmptyView() }) {
                Branches { Branch(AppTab.home) { Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }) } }
            }
        })
        await engine.present(RootRoute())
        let container = engine.defaultSpace.rootPath.last!
        let home = container.branchScopes[AppTab.home]!
        #expect(!home.isInstalledInView)
        await Router(engine: engine, scope: container).present(HomeDetailRoute())
        #expect(engine.defaultSpace.rootPath.last === container)
        #expect(home.path.last?.route is HomeDetailRoute)
        #expect(engine.pendingRoute == nil)
    }

    @Test func nativeTeardownPreservesNamedScopeIdentity() {
        let scope = RouteScope(id: "explicit", route: nil)
        scope.define(RootRouteMap { Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }) }.declarations)
        scope.attachHost(nil, id: UUID())
        scope.detachHost(id: scope.hostID!)
        #expect(scope.id == AnyHashable("explicit"))
        #expect(scope.definitions.routeBinding(for: HomeDetailRoute.self) != nil)
    }

    @Test func changingBranchSelectionKeepsDefinitionsAndScopeIdentityStable() async {
        let engine = RouterEngine(routes: RootRouteMap { Branches {
            Branch(AppTab.home) { Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }) }
            Branch(AppTab.wallet) { Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() }) }
        } })
        let identity = engine.root.branchScopes.values.flatMap(\.routeAttachments).map(\.identity)
        let (selection, selected) = tabSelection(.home)
        engine.root.bindTestBranchSelection(AnyRouteBranchSelection(selection))
        engine.root.setActiveBranch(AppTab.wallet)
        #expect(selected() == .wallet)
        #expect(engine.root.branchScopes.values.flatMap(\.routeAttachments).map(\.identity) == identity)
        #expect(engine.root.firstRouteAttachment(for: SettingsRoute.self)?.declaration?.branchID == AnyHashable(AppTab.wallet))
    }

    @Test func repeatedDuplicateRouteDeclarationsAreDisabled() {
        let map = RootRouteMap {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
            Push(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
        }
        let engine = RouterEngine(routes: map)
        #expect(engine.root.routeAttachments.isEmpty)
        guard case .conflict? = engine.root.firstRouteAttachment(for: SettingsRoute.self) else {
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
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable("home-root"), route: nil)
        homeScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        #expect(homeScope.firstRouteAttachment(for: HomeDetailRoute.self)?.declaration?.declaration.presentationKind == .push)
        #expect(homeScope.firstRouteAttachment(for: SettingsRoute.self)?.declaration?.declaration.presentationKind == .sheet)
        #expect(homeScope.id == AnyHashable("home-root"))

        await router.requestRoute(HomeDetailRoute())

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)

        await router.unwind(to: .nearestBranch)
        await router.requestRoute(SettingsRoute())

        #expect(router.defaultSpace.rootPath.isEmpty)
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
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())

        #expect(selectedTab() == .home)
        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.pendingRoute == nil)

        let homeScope = router.root.branchScopes[AppTab.home]!
        router.resumePendingRoute(for: AppTab.home, in: router.root)

        #expect(router.defaultSpace.rootPath.isEmpty)
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
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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
        router.defaultSpace.rootPath.replaceTestPath([landingScope])

        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        let settingsScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        settingsScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(settingsScope, for: AppTab.wallet)

        await router.requestRoute(MessageRoute())

        #expect(selectedTab() == .home)
        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.pendingRoute == nil)

        router.resumePendingRoute(for: AppTab.home, in: landingScope)

        #expect(router.defaultSpace.rootPath.count == 1)
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
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(TransactionRoute())
        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)

        await router.requestRoute(MessageRoute())

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is MessageRoute)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)

        let presentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .cover(.slide)
        ).wrappedValue)
        #expect(presentation.scope === router.defaultSpace.rootPath.last)
        #expect(router.routePresentationBinding(from: walletScope, matching: .cover(.slide)).wrappedValue == nil)

        router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue = nil

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)
    }

    @Test func branchContainerSheetDoesNotReappearAfterBranchSwitchDismissal() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(MessageRoute())

        #expect(selectedTab() == .wallet)
        #expect(router.defaultSpace.rootPath.count == 2)
        #expect(router.defaultSpace.rootPath.last?.route is MessageRoute)
        #expect(landingScope.path.isEmpty)
        #expect(walletScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue?.scope === router.defaultSpace.rootPath.last)

        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue = nil

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === landingScope)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)

        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))

        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)
        #expect(walletScope.path.isEmpty)
    }

    @Test func branchPushRequestDismissesTopLevelModalBeforeAppending() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(MessageRoute())
        let modalScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(modalScope)

        let requestTask = Task {
            await router.requestRoute(HomeDetailRoute())
        }

        for _ in 0..<10 {
            if router.defaultSpace.rootPath.count == 1,
               router.defaultSpace.rootPath.last === landingScope,
               homeScope.path.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(selectedTab() == .home)
        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === landingScope)
        #expect(homeScope.path.isEmpty)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(modalScope)
        _ = await requestTask.value

        #expect(selectedTab() == .home)
        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === landingScope)
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
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )
        appearanceScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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
        router.defaultSpace.rootPath.replaceTestPath([landingScope, modalScope])

        await router.requestRoute(SettingsRoute())

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === landingScope)
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
                    AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                ),
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )
        walletRouteScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        let walletRouteDeclaration = try #require(AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations.first)
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
        router.defaultSpace.rootPath.replaceTestPath([modalScope])

        let match = try #require(router.spaces.firstDeclaration(including: SettingsRoute.self)?.declaration)
        let unwindPlan = router.spaces.presentationUnwindPlan(after: match)

        #expect(match.lookupStrategy == .defaultRootActiveBranchScope)
        #expect(match.declaration.presentationKind == .push)
        #expect(match.presentationPath === walletScope.path)
        #expect(match.presentingScope === walletRouteScope)
        #expect(match.declaringPath === router.defaultSpace.rootPath)
        #expect(match.declaringScope === router.root)
        #expect(unwindPlan.removedScopes.count == 1)
        #expect(unwindPlan.removedScopes.first === modalScope)

        router.routeScopeDidInstallInView(modalScope)
        let requestTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 where router.defaultSpace.rootPath.isEmpty == false {
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.isEmpty)
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
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )
        walletRouteScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)
        walletRouteScope.attachPresentation(
            to: walletScope,
            declaration: try #require(AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations.first)
        )
        walletScope.path.replaceTestPath([walletRouteScope])
        modalScope.attachPresentation(
            to: router.root,
            declaration: try #require(AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations.first)
        )
        router.defaultSpace.rootPath.replaceTestPath([modalScope])

        let match = try #require(router.spaces.firstDeclaration(including: TransactionRoute.self)?.declaration)
        router.appendOrPendRoute(
            RouterEngine.NavigationOperation(awaitingHost: .init(route: TransactionRoute(), match: match)),
            waitsForBranchActivation: true
        )
        router.resumePendingRoute(for: AppTab.wallet, in: router.root)

        #expect(router.defaultSpace.rootPath.isEmpty)
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
                    AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                ),
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
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
        router.defaultSpace.rootPath.replaceTestPath([modalScope])

        let match = try #require(router.spaces.firstDeclaration(including: SettingsRoute.self)?.declaration)
        let unwindPlan = router.spaces.presentationUnwindPlan(after: match)

        #expect(match.lookupStrategy == .defaultRootDeclarations)
        #expect(match.declaration.presentationKind == .push)
        #expect(match.presentationPath === walletScope.path)
        #expect(match.presentingScope === walletScope)
        #expect(match.declaringPath === router.defaultSpace.rootPath)
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
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                    }
                )
            )
        )
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)
        walletRouteScope.attachPresentation(
            to: walletScope,
            declaration: try #require(AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations.first)
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
        let pushDeclaration = try #require(AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations.first)
        let modalDeclaration = try #require(AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations.first)

        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        landingScope.attachTestBranch(homeScope, for: AppTab.home)
        detailScope.attachPresentation(
            to: homeScope,
            declaration: pushDeclaration
        )
        modalScope.attachPresentation(to: landingScope, declaration: modalDeclaration)
        homeScope.path.replaceTestPath([detailScope])
        router.defaultSpace.rootPath.replaceTestPath([landingScope, modalScope])
        router.routeScopeDidInstallInView(modalScope)

        let match = RouterEngine.ResolvedRouteTarget(
            space: router.defaultSpace,
            presentingScope: homeScope,
            declaringScope: landingScope,
            branchID: AnyHashable(AppTab.home),
            declaration: pushDeclaration,
            lookupStrategy: .currentPath(spacePriority: .default)
        )
        let requestTask = Task {
            await router.reuseEquivalentRoute(HomeDetailRoute(), at: detailScope,
                plan: router.spaces.presentationUnwindPlan(after: match, retaining: detailScope))
        }

        for _ in 0..<10 {
            if router.defaultSpace.rootPath.last === landingScope {
                break
            }
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === landingScope)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last === detailScope)
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(modalScope)
        #expect(await requestTask.value === detailScope)

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === landingScope)
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
        let pushDeclaration = try #require(AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations.first)
        let modalDeclaration = try #require(AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations.first)

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
        router.defaultSpace.rootPath.replaceTestPath([landingScope, modalScope])

        await router.requestRoute(HomeDetailRoute())

        let presentedDetailScope = try #require(router.defaultSpace.rootPath.last)
        #expect(router.defaultSpace.rootPath.count == 3)
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
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(SettingsRoute())

        let settingsScope = try #require(homeScope.path.last)
        settingsScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(MessageRoute())

        #expect(router.defaultSpace.rootPath.isEmpty)
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

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(walletScope.path.last)

        // Toggle OFF: the pushed scope declares nothing, so the container-level sheet hosts.
        await router.requestRoute(MessageRoute())
        #expect(router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue?.scope === router.defaultSpace.rootPath.last)
        #expect(router.routePresentationBinding(from: walletScope, matching: .sheet).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .sheet).wrappedValue == nil)

        router.routePresentationBinding(from: landingScope, matching: .sheet).wrappedValue = nil
        #expect(walletScope.path.last === settingsScope)

        // Toggle ON: the pushed scope now declares the same route locally and must win.
        settingsScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
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

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default)) // top-level (shared) sheet
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default)) // branch-local sheet
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
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

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .default)) // top-level cover
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default)) // branch-local sheet
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.defaultSpace.rootPath.last)
        loginScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(router.defaultSpace.rootPath.last)

        #expect(loginScope.lane.depth == 1)
        #expect(settingsScope.lane.depth == 2)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue?.scope === loginScope)
        #expect(router.routePresentationBinding(from: loginScope, matching: .sheet).wrappedValue?.scope === settingsScope)

        await router.requestRoute(MessageRoute())

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is MessageRoute)
        #expect(router.defaultSpace.rootPath.scopes.contains { $0.route is LoginRoute } == false)
        #expect(router.defaultSpace.rootPath.scopes.contains { $0.route is SettingsRoute } == false)
    }

    @Test func replacingTopLevelCoverPreservesActiveBranchPushStack() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))
                ),
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))
                ),
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(homeScope.path.last)
        settingsScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
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
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(homeScope.path.last === homeDetailScope)

        router.routeScopeDidLeaveView(homeDetailScope)
        _ = await requestTask.value

        #expect(selectedTab() == .wallet)
        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.pendingRoute == nil)

        router.resumePendingRoute(for: AppTab.wallet, in: router.root)

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is TransactionRoute)
        #expect(router.pendingRoute == nil)
        #expect(router.routePresentationBinding(from: walletScope, matching: .push).wrappedValue != nil)
    }

    @Test func unresolvedRoutesAndUndeclaredRoutesAreDropped() async {
        let router = RouterEngine()

        await router.requestRoute(DroppedRoute())
        #expect(router.defaultSpace.rootPath.isEmpty)

        await router.requestRoute(SettingsRoute())
        #expect(router.defaultSpace.rootPath.isEmpty)
    }

    @Test func routeResolutionReroutePresentsResolvedRoute() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(ReroutingRoute())

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is LoginRoute)
    }

    @Test func routeResolutionRerouteChainStopsWhenAResolvedRouteDrops() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(DroppedRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(ReroutingToDroppedRoute())

        #expect(router.defaultSpace.rootPath.isEmpty)
    }

    @Test func defaultPresentationResolvesAndDismissesFromDeclaringScope() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())

        let presentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .sheet
        ).wrappedValue)

        #expect(presentation.scope === router.defaultSpace.rootPath.last)
        #expect(presentation.scope.presentationDeclaration?.routeTypeID == ObjectIdentifier(SettingsRoute.self))

        router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue = nil

        #expect(router.defaultSpace.rootPath.isEmpty)
    }

    @Test func repeatedPresentationOfEquivalentRouteKeepsPresentationIdentity() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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

        #expect(router.defaultSpace.rootPath.count == 1)
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(NumberedRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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

        #expect(router.defaultSpace.rootPath.count == 1)
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(NumberedRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(router.defaultSpace.rootPath.last)
        #expect(router.defaultSpace.rootPath.count == 2)
        #expect(settingsScope.route is SettingsRoute)
        router.routeScopeDidInstallInView(settingsScope)

        let requestTask = Task {
            await router.requestRoute(NumberedRoute(number: 1))
        }

        for _ in 0..<10 {
            if router.defaultSpace.rootPath.last === numberedScope {
                break
            }
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === numberedScope)
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
        #expect(router.defaultSpace.rootPath.count == 1)
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
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(NumberedRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(NumberedRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(NumberedRoute(number: 7))
        let numberedScope = try #require(walletScope.path.last)
        numberedScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(HomeDetailRoute())
        let firstScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(firstScope)

        let requestTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        await Task.yield()

        #expect(router.defaultSpace.rootPath.isEmpty)

        router.routeScopeDidLeaveView(firstScope)
        _ = await requestTask.value

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is SettingsRoute)
    }

    @Test func removingPresentedRouteScopeSynchronizesRouterPath() async throws {
        let root = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() })
        }, router: root) { EmptyView() }

        await root.current.present(HomeDetailRoute())
        let pushedScope = try #require(root.engine.defaultSpace.rootPath.last)
        #expect(await root.current.unwind(to: .topmostAncestor))

        #expect(root.engine.spaces.routePath(containing: pushedScope) == nil)
        #expect(root.engine.defaultSpace.rootPath.isEmpty)
        #expect(root.engine.routePresentationBinding(from: root.engine.root, matching: .push).wrappedValue == nil)
    }

    @Test func routeScopeLeavingViewUninstallsWithoutRemovingRouterPath() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(HomeDetailRoute())
        let pushedScope = try #require(router.defaultSpace.rootPath.last)

        router.routeScopeDidInstallInView(pushedScope)
        router.routeScopeDidLeaveView(pushedScope)

        #expect(pushedScope.isInstalledInView == false)
        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === pushedScope)
        #expect(router.routePresentationBinding(from: router.root, matching: .push).wrappedValue != nil)
    }

    @Test func installedModalDismissalRetainsImmediateGraphSemantics() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let sheetScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(sheetScope)

        let presentation = router.routePresentationBinding(from: router.root, matching: .sheet)
        presentation.wrappedValue = nil

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(presentation.wrappedValue == nil)

        router.routeScopeDidLeaveView(sheetScope)
    }

    @Test func presentationDismissalClearsBranchPathsOwnedByRemovedScope() throws {
        let router = RouterEngine()
        let modalScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let branchScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let detailScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let modalDeclaration = try #require(AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations.first)

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
        router.defaultSpace.rootPath.replaceTestPath([modalScope])

        router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue = nil

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.spaces.routePath(containing: branchScope) == nil)
    }

    @Test func snapshotPresentationWriteBackDoesNotTrimLiveRootPath() async throws {
        let router = RouterEngine()
        let retainedScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let coverScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let pushedScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let coverDeclaration = try #require(AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations.first)
        let pushDeclaration = try #require(AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations.first)

        coverScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: [pushDeclaration]),
            ]
        )
        coverScope.attachPresentation(to: retainedScope, declaration: coverDeclaration)
        pushedScope.attachPresentation(to: coverScope, declaration: pushDeclaration)
        router.defaultSpace.rootPath.replaceTestPath([retainedScope, coverScope, pushedScope])
        router.routeScopeDidInstallInView(coverScope)
        router.routeScopeDidInstallInView(pushedScope)

        let unwindTask = Task {
            await router.unwind(to: .id(RootRoute().id))
        }
        for _ in 0..<10 where router.hasOutgoingPresentations == false {
            await Task.yield()
        }

        let binding = router.routePresentationBinding(from: coverScope, matching: .push)
        #expect(binding.wrappedValue?.scope === pushedScope)
        binding.wrappedValue = nil

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === retainedScope)

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

    @Test func unwindDismissesCurrentRoute() async {
        let router = RouterEngine()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.defaultSpace.rootPath.replaceTestPath([firstScope])
        router.installElevatedSpace(priority: .high, scopes: [secondScope])

        await router.unwindAndWait(to: nil)

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === firstScope)
        #expect(router.spaces.highSpace == nil)
    }

    @Test func unwindToIDKeepsMatchingRouteScope() async {
        let router = RouterEngine()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.defaultSpace.rootPath.replaceTestPath([firstScope])
        router.installElevatedSpace(priority: .high, scopes: [secondScope])

        #expect(!((await router.unwindAndWait(to: .id(RootRoute().id)))))
        #expect(router.defaultSpace.rootPath.last === firstScope)
        #expect(router.spaces.highSpace?.root === secondScope)
    }

    @Test func combinedUnwindPlanKeepsShallowestBoundaryForTheSamePath() {
        let router = RouterEngine()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let thirdScope = RouteScope(id: AlertRoute().id, route: AlertRoute())
        router.defaultSpace.rootPath.replaceTestPath([firstScope, secondScope, thirdScope])

        let plan = RouteSpaces.UnwindPlan(retaining: [secondScope, firstScope])

        #expect(plan.retainedScopes.count == 1)
        #expect(plan.retainedScopes.first === firstScope)
        #expect(plan.removedScopes.count == 2)
        #expect(plan.removedScopes[0] === secondScope)
        #expect(plan.removedScopes[1] === thirdScope)
    }

    @Test func unwindToRootClearsPath() async {
        let router = RouterEngine()
        let firstScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let secondScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.defaultSpace.rootPath.replaceTestPath([firstScope])
        router.installElevatedSpace(priority: .high, scopes: [secondScope])

        await router.unwindAndWait(to: .root)

        #expect(router.defaultSpace.rootPath.last === firstScope)
        #expect(router.spaces.highSpace?.root === secondScope)
        #expect(router.spaces.highSpace?.rootPath.isEmpty == true)
    }

    @Test func unwindToRootClearsAppRootAndActiveBranchFromDeepWithinBranch() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())
        #expect(walletScope.path.count == 1)
        #expect(router.defaultSpace.rootPath.count == 1)

        // `.root` reaches past the current branch path to the app root.
        await router.unwind(to: .root)
        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.spaces.routePath(containing: walletScope) == nil)
    }

    @Test func unwindToRootClearsActiveBranchPushAndAdoptedModal() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(SettingsRoute())
        await router.requestRoute(MessageRoute())

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(homeScope.path.count == 2)
        #expect(homeScope.path.first?.route is SettingsRoute)
        #expect(homeScope.path.last?.route is MessageRoute)

        await router.unwind(to: .root)

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.spaces.routePath(containing: homeScope) == nil)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
    }

    @Test func unwindToRootClearsInactiveBranchStacksOwnedByRemovedScope() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                        AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        await router.requestRoute(MessageRoute())
        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))
        await router.requestRoute(TransactionRoute())

        #expect(selectedTab() == .wallet)
        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(homeScope.path.count == 2)
        #expect(walletScope.path.count == 1)

        await router.unwind(to: .root)

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.spaces.routePath(containing: homeScope) == nil)
        #expect(router.spaces.routePath(containing: walletScope) == nil)
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
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                        AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
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

        await router.unwind(to: .root)

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is HomeDetailRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .push).wrappedValue?.scope === homeScope.path.last)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue == nil)
        #expect(walletScope.path.isEmpty)
    }

    @Test func unwindToNearestBranchClearsThatBranchPathButKeepsTheAppRoot() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())
        #expect(walletScope.path.count == 1)

        // `.nearestBranch` is branch-scoped: from a pushed scope it clears the branch's own path back
        // to its root but keeps the app root (the landing scope) — it does not escape the branch.
        await router.unwind(to: .nearestBranch)
        #expect(walletScope.path.isEmpty)
        #expect(router.defaultSpace.rootPath.count == 1)
    }

    @Test func unwindToNearestBranchAtBranchRootIsNoOp() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        // Already at the branch root (nothing pushed). `.nearestBranch` must not escape to the root
        // path — it is a no-op that leaves the landing (app root) intact.
        #expect(walletScope.path.isEmpty)
        await router.unwind(to: .nearestBranch)
        #expect(walletScope.path.isEmpty)
        #expect(router.defaultSpace.rootPath.count == 1)
    }

    @Test func sequentialUnwindThenPresentWaitsForInstalledRouteScopeToLeaveView() async {
        let router = RouterEngine()
        let loginScope = RouteScope(id: LoginRoute().id, route: LoginRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )

        router.installElevatedSpace(priority: .high, scopes: [loginScope])
        router.routeScopeDidInstallInView(loginScope)

        let unwindTask = Task {
            guard await router.unwind(to: .topmostAncestor) else {
                return
            }

            await router.present(SettingsRoute())
        }

        await Task.yield()

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        _ = await unwindTask.value

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is SettingsRoute)
    }

    @Test func modalReplacementWaitsForInstalledRouteScopeToLeaveView() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let replacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.defaultSpace.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        _ = await replacementTask.value

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is SettingsRoute)
    }

    @Test func sheetToCoverReplacementWaitsForOldScopeToLeaveView() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let replacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.defaultSpace.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        _ = await replacementTask.value

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue?.scope === router.defaultSpace.rootPath.last)
    }

    @Test func coverToSheetReplacementWaitsForOldScopeToLeaveView() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let replacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.defaultSpace.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)

        router.routeScopeDidLeaveView(loginScope)
        _ = await replacementTask.value

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue?.scope === router.defaultSpace.rootPath.last)
    }

    @Test func pendingModalReplacementUsesLatestRequest() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(AlertRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.defaultSpace.rootPath.last)
        router.routeScopeDidInstallInView(loginScope)

        let firstReplacementTask = Task {
            await router.requestRoute(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.defaultSpace.rootPath.isEmpty {
                break
            }
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.isEmpty)

        let latestReplacementTask = Task {
            await router.requestRoute(AlertRoute())
        }

        await Task.yield()
        #expect(router.defaultSpace.rootPath.isEmpty)

        router.routeScopeDidLeaveView(loginScope)
        _ = await firstReplacementTask.value
        _ = await latestReplacementTask.value

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is AlertRoute)
    }

    @Test func namedRootUnwindTargetSurvivesNativeTeardown() async {
        let engine = RouterEngine(routes: RootRouteMap(id: "custom") {
            Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() })
        })
        engine.routeScopeDidInstallInView(engine.root)
        engine.routeScopeDidLeaveView(engine.root)
        #expect(engine.root.id == AnyHashable("custom"))
        await engine.present(HomeDetailRoute())
        #expect(await engine.unwind(to: .id("custom")))
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }

    @Test func cancellingPresentationWaitingForNavigationRemovesPendingRequest() async {
        let router = RouterEngine()
        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
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
        #expect(router.defaultSpace.rootPath.isEmpty)
        router.finishNavigationOperation(transaction)
    }

    @Test func pendingPresentationWaitsForEveryOverlappingNavigationTransaction() async throws {
        let router = RouterEngine(routes: RootRouteMap {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
        } highPriority: {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() })
        } criticalPriority: {
            Sheet(RouteDestination(AlertRoute.self) { _, _ in EmptyView() })
        })
        await router.present(LoginRoute())
        await router.present(AlertRoute())
        let firstSpace = try #require(router.spaces.highSpace)
        let secondSpace = try #require(router.spaces.criticalSpace)
        let firstDismissedScope = firstSpace.root
        let secondDismissedScope = secondSpace.root
        router.routeScopeDidInstallInView(firstDismissedScope)
        router.routeScopeDidInstallInView(secondDismissedScope)
        router.performPresentationDismissalUnwind(for: firstDismissedScope, in: nil,
            plan: RouteSpaces.UnwindPlan(removing: [firstSpace]))
        router.performPresentationDismissalUnwind(for: secondDismissedScope, in: nil,
            plan: RouteSpaces.UnwindPlan(removing: [secondSpace]))

        let presentationTask = Task {
            await router.present(SettingsRoute())
        }

        for _ in 0..<10 {
            if router.pendingRoute != nil {
                break
            }
            await Task.yield()
        }

        #expect(router.isNavigating)
        #expect(router.pendingRoute != nil)

        router.routeScopeDidLeaveView(firstDismissedScope)
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(router.isNavigating)
        #expect(router.pendingRoute != nil)
        #expect(router.defaultSpace.rootPath.isEmpty)

        router.routeScopeDidLeaveView(secondDismissedScope)
        await presentationTask.value

        #expect(router.isNavigating == false)
        #expect(router.pendingRoute == nil)
        #expect(router.defaultSpace.rootPath.last?.route is SettingsRoute)
    }

    @Test func snapshotPresentationUsesOriginalPositionForHighTreeLocalHosting() async {
        let router = RouterEngine()
        let rootScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let loginScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let noticeScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let noticeDeclaration = AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .high))._routeDeclarations[0]

        router.defaultSpace.rootPath.replaceTestPath([rootScope])
        noticeScope.attachPresentation(to: loginScope, declaration: noticeDeclaration)
        router.installElevatedSpace(priority: .high, scopes: [loginScope, noticeScope])
        router.routeScopeDidInstallInView(loginScope)
        router.routeScopeDidInstallInView(noticeScope)

        let unwindTask = Task {
            await RootRouter(engine: router).dismissSpace(.high)
        }

        for _ in 0..<10 {
            if router.hasOutgoingPresentations {
                break
            }
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.hasOutgoingPresentations)
        let presentation = router.routePresentation(from: loginScope, matching: .sheet)
        #expect(presentation?.scope === noticeScope)
        #expect(presentation?.scope.presentationDeclaration?.priority == .high)

        router.routeScopeDidLeaveView(loginScope)
        router.routeScopeDidLeaveView(noticeScope)

        #expect(await unwindTask.value)
    }

    @Test func unwindFromBranchPresentationKeepsPresentedTopLevelScope() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: Branch(AppTab.home) {
                AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .default))
            }.routeScopeDeclarations
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(MessageRoute())
        #expect(homeScope.path.count == 1)

        await router.unwind(to: .topmostAncestor)

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === landingScope)
        #expect(homeScope.path.isEmpty)
    }

    @Test func highPriorityUnwindFromBranchKeepsPresentedTopLevelScopeForContinuation() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(LoginRoute())

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === landingScope)
        #expect(router.spaces.highSpace?.rootPath.count == 0)
        #expect(router.spaces.highSpace?.currentRouteScope.route is LoginRoute)
        #expect(router.spaces.highSpace?.currentRoutePath === router.spaces.highSpace?.rootPath)

        await router.unwind(to: .topmostAncestor)

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === landingScope)
        #expect(landingScope.path.isEmpty)
        #expect(walletScope.path.isEmpty)

        await router.requestRoute(MessageRoute())
        router.resumePendingRoute(for: AppTab.home, in: landingScope)

        #expect(selectedTab() == .home)
        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is MessageRoute)
    }

    @Test func unwindFromBranchPushCanTargetAncestorRouteForContinuation() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())

        #expect(walletScope.path.count == 1)
        #expect(walletScope.path.last?.route is SettingsRoute)

        let didUnwind = await router.unwind(to: .id(RootRoute().id))
        if didUnwind {
            await router.requestRoute(MessageRoute())
            router.resumePendingRoute(for: AppTab.home, in: landingScope)
        }

        #expect(didUnwind)
        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === landingScope)
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )

        router.defaultSpace.rootPath.replaceTestPath([firstScope, secondScope, thirdScope])
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

        #expect(router.defaultSpace.rootPath.isEmpty)

        router.routeScopeDidLeaveView(firstScope)
        router.routeScopeDidLeaveView(secondScope)
        await Task.yield()

        #expect(router.defaultSpace.rootPath.isEmpty)

        router.routeScopeDidLeaveView(thirdScope)
        _ = await unwindTask.value

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is SettingsRoute)
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(RootRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations),
            ]
        )
        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        profileScope.attachPresentation(
            to: homeScope,
            declaration: try #require(homeScope.routeAttachments.first { $0.presentationKind == .sheet })
        )
        router.defaultSpace.rootPath.replaceTestPath([landingScope, profileScope])
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

    @Test func scopedTopmostAncestorKeepsModalPushSnapshotUntilSheetLeavesView() async throws {
        let router = RouterEngine()
        let sheetScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let pushedScope = RouteScope(id: HomeDetailRoute().id, route: HomeDetailRoute(), parent: sheetScope)

        router.root.defineTestMap(
            id: "root",
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        sheetScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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
        router.defaultSpace.rootPath.replaceTestPath([sheetScope, pushedScope])
        router.routeScopeDidInstallInView(sheetScope)
        router.routeScopeDidInstallInView(pushedScope)

        let unwind = Task { await Router(engine: router, scope: sheetScope).unwind(to: .topmostAncestor) }
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        sheetA.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
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
        router.defaultSpace.rootPath.replaceTestPath([sheetA, sheetB])
        router.routeScopeDidInstallInView(sheetA)
        router.routeScopeDidInstallInView(sheetB)

        let unwind = Task { await UnwindRouteAction(router: router, routeScope: sheetA)() }
        for _ in 0..<10 where !router.defaultSpace.rootPath.isEmpty {
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.isEmpty)
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        sheetScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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
        router.defaultSpace.rootPath.replaceTestPath([sheetScope, pushedScope])
        router.routeScopeDidInstallInView(sheetScope)
        router.routeScopeDidInstallInView(pushedScope)

        router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue = nil

        #expect(router.defaultSpace.rootPath.isEmpty)
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(AddMethodRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations),
            ]
        )
        coverScope.defineTestMap(
            id: AddMethodRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(AddCardRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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
        router.defaultSpace.rootPath.replaceTestPath([paymentMethodsScope, coverScope, pushedScope])
        router.routeScopeDidInstallInView(coverScope)
        router.routeScopeDidInstallInView(pushedScope)

        let unwindTask = Task {
            await router.unwind(to: .id(paymentMethodsID))
        }

        for _ in 0..<10 where router.hasOutgoingPresentations == false {
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.scopes.elementsEqual([paymentMethodsScope], by: { $0 === $1 }))
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(RootRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations),
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(homeScope, for: AppTab.home)

        profileScope.attachPresentation(
            to: homeScope,
            declaration: try #require(homeScope.routeAttachments.first { $0.presentationKind == .sheet })
        )
        homeScope.path.replaceTestPath([profileScope])
        router.defaultSpace.rootPath.replaceTestPath([landingScope])

        router.routeScopeDidInstallInView(landingScope)
        router.routeScopeDidInstallInView(profileScope)

        let unwindTask = Task {
            await router.unwindAndWait(to: .root)
        }

        for _ in 0..<10 {
            if router.hasOutgoingPresentations {
                break
            }
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.spaces.routePath(containing: homeScope) == nil)
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(RootRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations),
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(settingsScope, for: AppTab.wallet)

        authenticationScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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
        router.defaultSpace.rootPath.replaceTestPath([landingScope])

        router.routeScopeDidInstallInView(landingScope)
        router.routeScopeDidInstallInView(authenticationScope)
        router.routeScopeDidInstallInView(detailScope)

        let unwindTask = Task {
            await router.unwindAndWait(to: .root)
        }

        for _ in 0..<10 {
            if router.hasOutgoingPresentations {
                break
            }
            await Task.yield()
        }

        #expect(router.spaces.routePath(containing: settingsScope) == nil)
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(RootRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(settingsScope, for: AppTab.wallet)

        appearanceScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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
        router.defaultSpace.rootPath.replaceTestPath([landingScope])
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

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue == nil)
        #expect(router.routePresentationBinding(from: settingsScope, matching: .push).wrappedValue?.scope === appearanceScope)
        #expect(router.routePresentationBinding(from: appearanceScope, matching: .push).wrappedValue?.scope === authenticationScope)

        router.routeScopeDidLeaveView(landingScope)
        _ = await requestTask.value

        #expect(router.hasOutgoingPresentations == false)
        #expect(router.defaultSpace.rootPath.last?.route is MessageRoute)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue?.scope === router.defaultSpace.rootPath.last)
    }

    @Test func routeAppendDoesNotPreservePushHostedByRetainedScopeWhileNestedModalLeaves() async throws {
        let router = RouterEngine()
        let appearanceScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let authenticationScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let sheetScope = RouteScope(id: MessageRoute().id, route: MessageRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        appearanceScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(AlertRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        authenticationScope.defineTestMap(
            id: SettingsRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
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
        router.defaultSpace.rootPath.replaceTestPath([appearanceScope, authenticationScope, sheetScope])
        router.routeScopeDidInstallInView(authenticationScope)
        router.routeScopeDidInstallInView(sheetScope)

        let requestTask = Task {
            await router.requestRoute(TransactionRoute())
        }

        for _ in 0..<10 {
            if router.hasOutgoingPresentations {
                break
            }
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.scopes.elementsEqual([appearanceScope], by: { $0 === $1 }))
        #expect(router.routePresentationBinding(from: appearanceScope, matching: .push).wrappedValue == nil)

        router.routeScopeDidLeaveView(sheetScope)
        let supersedingTask = Task {
            await router.requestRoute(AlertRoute())
        }

        for _ in 0..<10 {
            if router.hasOutgoingPresentations == false,
               router.pendingRoute?.route is AlertRoute {
                break
            }
            await Task.yield()
        }

        #expect(router.hasOutgoingPresentations == false)
        #expect(router.routePresentationBinding(from: appearanceScope, matching: .push).wrappedValue == nil)
        #expect(router.pendingRoute?.route is AlertRoute)

        router.routeScopeDidLeaveView(authenticationScope)
        _ = await requestTask.value
        _ = await supersedingTask.value

        #expect(router.pendingRoute == nil)
        #expect(router.defaultSpace.rootPath.count == 2)
        #expect(router.defaultSpace.rootPath.last?.route is AlertRoute)
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(settingsScope, for: AppTab.wallet)

        authenticationScope.attachPresentation(
            to: settingsScope,
            declaration: try #require(settingsScope.routeAttachments.first { $0.presentationKind == .push })
        )
        settingsScope.path.replaceTestPath([authenticationScope])
        router.defaultSpace.rootPath.replaceTestPath([landingScope])

        router.routeScopeDidInstallInView(authenticationScope)

        let unwindTask = Task {
            await router.unwindAndWait(to: .nearestBranch)
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        appearanceScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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
        router.defaultSpace.rootPath.replaceTestPath([appearanceScope, authenticationScope])
        router.routeScopeDidInstallInView(appearanceScope)
        router.routeScopeDidInstallInView(authenticationScope)

        let requestTask = Task {
            await router.requestRoute(TransactionRoute())
        }

        for _ in 0..<10 where router.defaultSpace.rootPath.isEmpty == false {
            await Task.yield()
        }

        #expect(router.defaultSpace.rootPath.isEmpty)
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
        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last?.route is TransactionRoute)
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
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(HomeDetailRoute())
        let homeDetailScope = try #require(homeScope.path.last)

        router.root.setActiveBranch(AnyHashable(AppTab.wallet))

        #expect(selectedTab() == .wallet)
        #expect(router.defaultSpace.rootPath.isEmpty)
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

    @Test func highPrioritySpaceClearsWhenHighRouteLeavesViewOnInactiveBranch() async throws {
        let router = RouterEngine()
        let (selection, selectedTab) = tabSelection(.wallet)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(LoginRoute())
        let highRouteScope = try #require(router.spaces.highSpace?.currentRouteScope)
        router.routeScopeDidInstallInView(highRouteScope)

        router.root.setActiveBranch(AnyHashable(AppTab.home))
        router.routeScopeDidLeaveView(highRouteScope)

        #expect(selectedTab() == .home)
        #expect(router.spaces.highSpace == nil)

        await router.requestRoute(SettingsRoute())

        #expect(homeScope.path.count == 1)
        #expect(homeScope.path.last?.route is SettingsRoute)
        #expect(router.routePresentationBinding(from: homeScope, matching: .sheet).wrappedValue?.scope === homeScope.path.last)
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
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
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
                AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
            }.routeScopeDeclarations
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
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
                        AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                    }
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(TransactionRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
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
            + " | strategy=highest eligible space first, current path before root path, nearest scope first"
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
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        router.defaultSpace.rootPath.replaceTestPath([ancestorScope, firstDescendant, secondDescendant])

        let match = try #require(router.spaces.firstDeclaration(including: MessageRoute.self)?.declaration)
        let plan = router.spaces.presentationUnwindPlan(after: match)
        let expectedDescription = "MessageRoute[push] • local scope"
            + " • lookup=current route path in default space, nearest scope first"

        #expect(match.lookupStrategy == .currentPath(spacePriority: .default))
        #expect(match.departureDebugDescription == expectedDescription)
        #expect(plan.retainedScopes.count == 1)
        #expect(plan.retainedScopes.first === ancestorScope)
        #expect(plan.removedScopes.count == 2)
        #expect(plan.removedScopes[0] === firstDescendant)
        #expect(plan.removedScopes[1] === secondDescendant)
    }

    @Test func unwindRequestLogMessagesDescribeTheirActualTargets() {
        #expect(
            DepartureLogEvent.unwindRequested(target: nil).message
                == "requested to previous route"
        )
        #expect(
            DepartureLogEvent.unwindRequested(target: .topmostAncestor).message
                == "requested to topmostAncestor"
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

    @Test func highPriorityPresentationUsesActiveLocalBranchScope() async {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: Branch(AppTab.home) {
                AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))
            }.routeScopeDeclarations
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(LoginRoute())

        let presentation = router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue

        #expect(presentation?.scope === router.spaces.highSpace?.currentRouteScope)
        #expect(presentation?.scope.presentationDeclaration?.routeTypeID == ObjectIdentifier(LoginRoute.self))
    }

    @Test func pendingElevatedPresentationBlocksLowerPriorityBeforeTreeStarts() async {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
        } highPriority: {
            Cover(RouteDestination(NumberedRoute.self) { _, _ in EmptyView() })
        })
        await engine.present(NumberedRoute(number: 1))
        let old = engine.spaces.highSpace!.root
        engine.routeScopeDidInstallInView(old)
        let replacing = Task { await engine.present(NumberedRoute(number: 2)) }
        for _ in 0..<1000 where engine.spaces.highSpace?.root === old { await Task.yield() }
        #expect(engine.spaces.highSpace?.root.route as? NumberedRoute == NumberedRoute(number: 2))
        #expect(engine.isNavigating)
        let lowerRequest = Task { await Router(engine: engine, scope: engine.root).present(SettingsRoute()) }
        for _ in 0..<1000 where engine.pendingRoute == nil { await Task.yield() }
        #expect(engine.pendingRoute != nil)
        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(engine.spaces.highSpace?.root.route as? NumberedRoute == NumberedRoute(number: 2))
        engine.routeScopeDidLeaveView(old)
        await replacing.value
        await lowerRequest.value
        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(engine.spaces.highSpace?.root.presentationOrigin === engine.root)
    }

    @Test func equalPriorityRequestReplacesPendingElevatedPresentationBeforeTreeStarts() async {
        let engine = RouterEngine(routes: RootRouteMap {} highPriority: {
            Cover(RouteDestination(NumberedRoute.self) { _, _ in EmptyView() })
            Cover(RouteDestination(AlertRoute.self) { _, _ in EmptyView() })
        })
        await engine.present(NumberedRoute(number: 1))
        let old = engine.spaces.highSpace!.root
        engine.routeScopeDidInstallInView(old)
        let first = Task { await engine.present(NumberedRoute(number: 2)) }
        for _ in 0..<1000 where engine.spaces.highSpace?.root === old { await Task.yield() }
        let latest = Task { await engine.present(AlertRoute()) }
        for _ in 0..<100 { await Task.yield() }
        engine.routeScopeDidLeaveView(old)
        await first.value
        await latest.value
        #expect(engine.pendingRoute == nil)
        #expect(engine.spaces.highSpace?.currentRouteScope.route is AlertRoute)
        #expect(engine.spaces.highSpace?.root.presentationOrigin === engine.root)
    }

    @Test func highPriorityPresentationCanUseContainerDeclarationFromActiveLocalBranch() async {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)

        router.root.defineTestMap(
            id: nil,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))
                ),
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))
                    }
                )
            )
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(
            id: AnyHashable(AppTab.home),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )
        router.root.attachTestBranch(homeScope, for: AppTab.home)

        await router.requestRoute(LoginRoute())

        let presentation = router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue

        #expect(presentation?.scope === router.spaces.highSpace?.currentRouteScope)
        #expect(presentation?.scope.presentationDeclaration?.routeTypeID == ObjectIdentifier(LoginRoute.self))
    }

    @Test func defaultRouteBeforeActiveHighTreeIsDropped() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        await router.requestRoute(SettingsRoute())

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.spaces.highSpace?.rootPath.count == 0)
        #expect(router.spaces.highSpace?.currentRouteScope.route is LoginRoute)
        #expect(router.routePresentationBinding(from: router.root, matching: .sheet).wrappedValue == nil)
    }

    @Test func highPriorityPresentationOverlaysDefaultPresentation() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let defaultScope = router.defaultSpace.rootPath.last

        await router.requestRoute(LoginRoute())

        let defaultPresentation = router.routePresentationBinding(
            from: router.root,
            matching: .cover(.slide)
        ).wrappedValue
        let highPresentation = router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.first === defaultScope)
        #expect(router.defaultSpace.rootPath.first?.route is SettingsRoute)
        #expect(router.spaces.highSpace?.rootPath.count == 0)
        #expect(router.spaces.highSpace?.currentRouteScope.route is LoginRoute)
        #expect(router.spaces.highSpace?.root.route is LoginRoute)
        #expect(defaultPresentation?.scope === defaultScope)
        #expect(defaultPresentation?.scope.presentationDeclaration?.priority == .default)
        #expect(highPresentation?.scope === router.spaces.highSpace?.currentRouteScope)
        #expect(highPresentation?.scope.presentationDeclaration?.priority == .high)

        router.elevatedRoutePresentationBinding(priority: .high, matching: .cover(.slide)).wrappedValue = nil

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.last === defaultScope)
        #expect(router.routePresentationBinding(from: router.root, matching: .cover(.slide)).wrappedValue?.scope === defaultScope)
        #expect(router.spaces.highSpace == nil)
    }

    @Test func highPriorityReplacementPreservesUnderlyingDefaultPresentation() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(AlertRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .high))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let defaultScope = router.defaultSpace.rootPath.last
        await router.requestRoute(LoginRoute())
        await router.requestRoute(AlertRoute())

        let defaultPresentation = router.routePresentationBinding(
            from: router.root,
            matching: .cover(.slide)
        ).wrappedValue
        let highPresentation = router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.fade)
        ).wrappedValue

        #expect(router.defaultSpace.rootPath.count == 1)
        #expect(router.defaultSpace.rootPath.first === defaultScope)
        #expect(router.defaultSpace.rootPath.first?.route is SettingsRoute)
        #expect(router.spaces.highSpace?.rootPath.count == 0)
        #expect(router.spaces.highSpace?.currentRouteScope.route is AlertRoute)
        #expect(router.spaces.highSpace?.rootPath.scopes.contains { $0.route is LoginRoute } == false)
        #expect(router.spaces.highSpace?.root.route is AlertRoute)
        #expect(defaultPresentation?.scope === defaultScope)
        #expect(defaultPresentation?.scope.presentationDeclaration?.priority == .default)
        #expect(highPresentation?.scope === router.spaces.highSpace?.currentRouteScope)
        #expect(highPresentation?.scope.presentationDeclaration?.priority == .high)
    }

    @Test func highPriorityReplacementClearsAndWaitsForOwnedBranchPaths() async throws {
        let router = RouterEngine()
        let branchScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let branchDetailScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations
                        + AnyRouteDeclaration(RouteDestination(AlertRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .high))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.spaces.highSpace?.currentRouteScope)
        loginScope.attachTestBranch(branchScope, for: AppTab.wallet)
        branchScope.path.replaceTestPath([branchDetailScope])
        router.routeScopeDidInstallInView(loginScope)
        router.routeScopeDidInstallInView(branchDetailScope)

        let replacementTask = Task {
            await router.requestRoute(AlertRoute())
        }
        for _ in 0..<10 where router.spaces.highSpace != nil {
            await Task.yield()
        }

        #expect(router.spaces.highSpace?.root.route is AlertRoute)
        #expect(router.spaces.routePath(containing: branchScope) == nil)
        #expect(router.isNavigating)

        router.routeScopeDidLeaveView(loginScope)
        await Task.yield()
        #expect(router.isNavigating)
        #expect(router.spaces.highSpace?.root.route is AlertRoute)

        router.routeScopeDidLeaveView(branchDetailScope)
        _ = await replacementTask.value

        #expect(router.pendingRoute == nil)
        #expect(router.spaces.highSpace?.currentRouteScope.route is AlertRoute)
    }

    @Test func defaultRouteMatchedInsideHighTreeAppendsNormally() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = router.spaces.highSpace?.currentRouteScope
        loginScope?.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())

        #expect(router.spaces.highSpace?.rootPath.count == 1)
        #expect(router.spaces.highSpace?.root.route is LoginRoute)
        #expect(router.spaces.highSpace?.currentRouteScope.route is SettingsRoute)
        #expect(router.spaces.highSpace?.root === loginScope)
    }

    @Test func highPriorityDeclarationInsideHighTreeAppendsNormally() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = router.spaces.highSpace?.currentRouteScope
        loginScope?.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(AlertRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(AlertRoute())

        #expect(router.spaces.highSpace?.rootPath.count == 1)
        #expect(router.spaces.highSpace?.root.route is LoginRoute)
        #expect(router.spaces.highSpace?.currentRouteScope.route is AlertRoute)
        #expect(router.spaces.highSpace?.root === loginScope)
        #expect(router.routePresentationBinding(from: loginScope, matching: .cover(.fade)).wrappedValue?.scope === router.spaces.highSpace?.currentRouteScope)
    }

    @Test func presentingEquivalentHighPriorityRouteUnwindsInsideHighTreeInsteadOfReplacing() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.spaces.highSpace?.currentRouteScope)
        loginScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(router.spaces.highSpace?.currentRouteScope)
        #expect(router.spaces.highSpace?.rootPath.count == 1)
        #expect(settingsScope.route is SettingsRoute)
        router.routeScopeDidInstallInView(settingsScope)

        let requestTask = Task {
            await router.requestRoute(LoginRoute())
        }

        for _ in 0..<10 {
            if router.spaces.highSpace?.currentRouteScope === loginScope {
                break
            }
            await Task.yield()
        }

        #expect(router.spaces.highSpace?.rootPath.count == 0)
        #expect(router.spaces.highSpace?.currentRouteScope === loginScope)
        #expect(router.spaces.highSpace?.root === loginScope)
        #expect(router.elevatedRoutePresentationBinding(priority: .high, matching: .cover(.slide)).wrappedValue?.scope === loginScope)

        router.routeScopeDidLeaveView(settingsScope)
        _ = await requestTask.value

        #expect(router.spaces.highSpace?.rootPath.count == 0)
        #expect(router.spaces.highSpace?.currentRouteScope === loginScope)
        #expect(router.spaces.highSpace?.root === loginScope)
    }

    @Test func equivalentHighPriorityRouteClearsBranchesOwnedByRemovedScopes() async throws {
        let router = RouterEngine()
        let branchScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let branchDetailScope = RouteScope(id: TransactionRoute().id, route: TransactionRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.spaces.highSpace?.currentRouteScope)
        loginScope.defineTestMap(
            id: LoginRoute().id,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default))._routeDeclarations),
            ]
        )
        await router.requestRoute(SettingsRoute())
        let settingsScope = try #require(router.spaces.highSpace?.currentRouteScope)
        settingsScope.attachTestBranch(branchScope, for: AppTab.wallet)
        branchScope.path.replaceTestPath([branchDetailScope])

        await router.requestRoute(LoginRoute())

        #expect(router.spaces.highSpace?.rootPath.count == 0)
        #expect(router.spaces.highSpace?.currentRouteScope === loginScope)
        #expect(router.spaces.routePath(containing: branchScope) == nil)
    }

    @Test func elevatedPresentationDismissalClearsOwnedBranchPaths() async throws {
        let router = RouterEngine()
        let branchScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let branchDetailScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = try #require(router.spaces.highSpace?.currentRouteScope)
        loginScope.attachTestBranch(branchScope, for: AppTab.wallet)
        branchScope.path.replaceTestPath([branchDetailScope])

        router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue = nil

        #expect(router.spaces.highSpace == nil)
        #expect(router.spaces.routePath(containing: branchScope) == nil)
    }

    @Test func ancestorHighPriorityDeclarationReplacesActiveHighPriorityRoute() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations
                        + AnyRouteDeclaration(RouteDestination(AlertRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .high))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        await router.requestRoute(AlertRoute())

        let presentation = router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.fade)
        ).wrappedValue

        #expect(router.spaces.highSpace?.rootPath.count == 0)
        #expect(router.spaces.highSpace?.currentRouteScope.route is AlertRoute)
        #expect(presentation?.scope === router.spaces.highSpace?.currentRouteScope)
        #expect(presentation?.scope.presentationDeclaration?.routeTypeID == ObjectIdentifier(AlertRoute.self))
    }

    @Test func criticalPriorityPresentationOverlaysHighPriorityPresentation() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(AlertRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .critical))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let highScope = router.spaces.highSpace?.currentRouteScope

        await router.requestRoute(AlertRoute())

        let highPresentation = router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue
        let criticalPresentation = router.elevatedRoutePresentationBinding(
            priority: .critical,
            matching: .cover(.fade)
        ).wrappedValue

        #expect(router.spaces.highSpace?.rootPath.count == 0)
        #expect(router.spaces.highSpace?.root === highScope)
        #expect(router.spaces.highSpace?.root.route is LoginRoute)
        #expect(router.spaces.criticalSpace?.rootPath.count == 0)
        #expect(router.spaces.criticalSpace?.currentRouteScope.route is AlertRoute)
        #expect(router.spaces.highSpace?.root === highScope)
        #expect(router.spaces.criticalSpace?.root === router.spaces.criticalSpace?.currentRouteScope)
        #expect(highPresentation?.scope === highScope)
        #expect(highPresentation?.scope.presentationDeclaration?.priority == .high)
        #expect(criticalPresentation?.scope === router.spaces.criticalSpace?.currentRouteScope)
        #expect(criticalPresentation?.scope.presentationDeclaration?.priority == .critical)
    }

    @Test func unwindingHighPriorityRoutePreservesCriticalTreeAnchoredToAncestor() async throws {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(AlertRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .critical))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        _ = try #require(router.spaces.highSpace?.currentRouteScope)
        await router.requestRoute(AlertRoute())

        let didUnwind = await RootRouter(engine: router).dismissSpace(.high)

        #expect(didUnwind)
        #expect(router.spaces.highSpace == nil)
        #expect(router.spaces.criticalSpace != nil)
        #expect(router.elevatedRoutePresentationBinding(priority: .critical, matching: .cover(.fade)).wrappedValue != nil)
    }

    @Test func criticalPriorityReplacementPreservesUnderlyingHighPriorityPresentation() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(AlertRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .critical))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .critical))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let highScope = router.spaces.highSpace?.currentRouteScope
        await router.requestRoute(AlertRoute())
        await router.requestRoute(SettingsRoute())

        let highPresentation = router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue
        let criticalPresentation = router.elevatedRoutePresentationBinding(
            priority: .critical,
            matching: .cover(.slide)
        ).wrappedValue

        #expect(router.spaces.highSpace?.rootPath.count == 0)
        #expect(router.spaces.highSpace?.root === highScope)
        #expect(router.spaces.highSpace?.root.route is LoginRoute)
        #expect(router.spaces.criticalSpace?.rootPath.count == 0)
        #expect(router.spaces.criticalSpace?.currentRouteScope.route is SettingsRoute)
        #expect(router.spaces.criticalSpace?.rootPath.scopes.contains { $0.route is AlertRoute } == false)
        #expect(router.spaces.highSpace?.root === highScope)
        #expect(router.spaces.criticalSpace?.root === router.spaces.criticalSpace?.currentRouteScope)
        #expect(highPresentation?.scope === highScope)
        #expect(criticalPresentation?.scope === router.spaces.criticalSpace?.currentRouteScope)
        #expect(criticalPresentation?.scope.presentationDeclaration?.priority == .critical)
    }

    @Test func lowerPriorityRouteBeforeActiveCriticalTreeIsDropped() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .critical))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        await router.requestRoute(SettingsRoute())
        await router.requestRoute(MessageRoute())

        #expect(router.defaultSpace.rootPath.isEmpty)
        #expect(router.spaces.criticalSpace?.rootPath.count == 0)
        #expect(router.spaces.criticalSpace?.currentRouteScope.route is LoginRoute)
        #expect(router.spaces.criticalSpace?.root === router.spaces.criticalSpace?.currentRouteScope)
        #expect(router.spaces.highSpace == nil)
    }

    @Test func criticalPriorityDeclarationInsideHighTreeStartsCriticalTree() async {
        let router = RouterEngine()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .high))._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let loginScope = router.spaces.highSpace?.currentRouteScope
        loginScope?.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(AlertRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.fade), priority: .critical))._routeDeclarations),
            ]
        )

        await router.requestRoute(AlertRoute())

        #expect(router.spaces.highSpace?.rootPath.count == 0)
        #expect(router.spaces.highSpace?.root.route is LoginRoute)
        #expect(router.spaces.criticalSpace?.rootPath.count == 0)
        #expect(router.spaces.criticalSpace?.currentRouteScope.route is AlertRoute)
        #expect(router.spaces.highSpace?.root === loginScope)
        #expect(router.spaces.criticalSpace?.root === router.spaces.criticalSpace?.currentRouteScope)
        #expect(router.elevatedRoutePresentationBinding(priority: .critical, matching: .cover(.fade)).wrappedValue?.scope === router.spaces.criticalSpace?.currentRouteScope)
        #expect(router.routePresentationBinding(from: loginScope, matching: .cover(.fade)).wrappedValue == nil)
    }

    @Test func criticalCoverHostUpdatesKeepItsDefinitionsStable() async throws {
        let engine = RouterEngine(routes: RootRouteMap {} criticalPriority: {
            Cover(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
                Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
            }
        })
        await engine.present(LoginRoute())
        let cover = try #require(engine.spaces.criticalSpace?.currentRouteScope)
        let identity = cover.routeAttachments.map(\.identity)
        for _ in 0..<5 { engine.routeScopeDidInstallInView(cover); engine.routeScopeDidLeaveView(cover) }
        #expect(cover.routeAttachments.map(\.identity) == identity)
        #expect(cover.definitions.routeBinding(for: SettingsRoute.self) != nil)
    }
}

private extension RouterEngine {
    @MainActor
    func installElevatedSpace(priority: RoutePriority, scopes: [RouteScope]) {
        let rootScope = scopes.first!
        let space = RouteSpace(priority: priority, root: rootScope)
        rootScope.path.replaceTestPath(Array(scopes.dropFirst()))

        switch priority {
        case .default:
            break

        case .high:
            spaces.highSpace = space

        case .critical:
            spaces.criticalSpace = space
        }

        mutateRouteGraph {}
    }
}
