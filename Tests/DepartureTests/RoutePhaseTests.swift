import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite struct RoutePhaseTests {
    let detail = RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }
    let settings = RouteDestination(SettingsRoute.self) { _, _ in EmptyView() }
    let login = RouteDestination(LoginRoute.self) { _, _ in EmptyView() }

    @Test func inactiveLiveAncestorsAndBranchesRetainCommandAuthority() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Branches {
                Branch(AppTab.home) { Push(detail) }
                Branch(AppTab.wallet) { Push(settings) }
            }
        }, router: owner) { EmptyView() }
        let engine = owner.engine
        let home = try #require(engine.root.branchScopes[AppTab.home])
        let wallet = try #require(engine.root.branchScopes[AppTab.wallet])
        await owner.default.branch(AppTab.home).present(HomeDetailRoute())
        #expect(engine.routePhase(for: home) == .inactive)
        #expect(engine.routePhase(for: wallet) == .inactive)
        #expect(engine.routePhase(for: engine.root) == .inactive)
        #expect(engine.isNavigationEligible(engine.root))
        #expect(engine.isNavigationEligible(home))
        #expect(engine.isNavigationEligible(wallet))
        #expect(!wallet.isInstalledInView)

        await Router(engine: engine, scope: engine.root).branch(AppTab.wallet).present(SettingsRoute())
        #expect(engine.root.activeBranch == AnyHashable(AppTab.wallet))
        // Awaiting presentation includes branch staging and destination insertion.
        #expect(engine.pendingRoute == nil)
        let current = try #require(wallet.path.last)
        #expect(current.route is SettingsRoute)
        #expect(engine.currentRouteScope === current)
        #expect(engine.defaultSpace.currentRoutePath === wallet.path)
        #expect(engine.root.activeBranch == AnyHashable(AppTab.wallet))
        #expect(engine.routePhase(for: current) == .active)
        #expect(engine.routePhase(for: home.path.last!) == .inactive)
    }

    @Test func concurrentEndpointsBecomeInactiveAndIneligibleWhenCovered() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Branches(concurrent: true) {
                Branch(AppTab.home) { Push(detail) }
                Branch(AppTab.wallet) { Push(settings) }
            }
        } highPriority: { Sheet(login) }, router: owner) { EmptyView() }
        let engine = owner.engine
        await owner.default.branch(AppTab.home).present(HomeDetailRoute())
        await owner.default.branch(AppTab.wallet).present(SettingsRoute())
        let home = try #require(engine.root.branchScopes[AppTab.home]?.path.last)
        let wallet = try #require(engine.root.branchScopes[AppTab.wallet]?.path.last)
        #expect(engine.routePhase(for: home) == .active)
        #expect(engine.routePhase(for: wallet) == .active)

        await owner.current.present(LoginRoute())
        let elevated = try #require(engine.spaces.highSpace?.root)
        for scope in [engine.root, home, wallet] {
            #expect(engine.spaces.routePath(containing: scope) != nil)
            #expect(engine.routePhase(for: scope) == .inactive)
            #expect(!engine.isNavigationEligible(scope))
        }
        #expect(engine.routePhase(for: elevated) == .active)
        #expect(await owner.dismissSpace(.high))
        #expect(engine.routePhase(for: elevated) == .inactive)
        #expect(!engine.isNavigationEligible(elevated))
        #expect(engine.routePhase(for: home) == .active)
        #expect(engine.routePhase(for: wallet) == .active)
    }

    @Test func aModalRestrictsPhaseToItsSubtreeButKeepsTopSpaceCommandsEligible() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Branches(concurrent: true) {
                Branch(AppTab.home) {
                    Push(detail) {
                        Sheet(login) {
                            Branches(concurrent: true) {
                                Branch("leading") {}
                                Branch("trailing") {}
                            }
                        }
                    }
                }
                Branch(AppTab.wallet) { Push(settings) }
            }
        }, router: owner) { EmptyView() }
        let engine = owner.engine
        await owner.default.branch(AppTab.home).present(HomeDetailRoute())
        await owner.default.branch(AppTab.wallet).present(SettingsRoute())
        let home = try #require(engine.root.branchScopes[AppTab.home]?.path.last)
        let wallet = try #require(engine.root.branchScopes[AppTab.wallet]?.path.last)
        await Router(engine: engine, scope: home).present(LoginRoute())
        let modal = try #require(home.owningPath?.last)
        #expect(modal.route is LoginRoute)
        for scope in [home, wallet] {
            #expect(engine.routePhase(for: scope) == .inactive)
            #expect(engine.isNavigationEligible(scope))
        }
        for scope in modal.branchScopes.values {
            #expect(engine.routePhase(for: scope) == .active)
            #expect(engine.isNavigationEligible(scope))
        }
    }
}
