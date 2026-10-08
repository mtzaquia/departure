import SwiftUI
import Observation
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RouteSpaceTests {
    @Test(arguments: [false, true])
    func rootUnwindRetainsOnlyBranchesWhoseContainerSurvives(rootIsBranched: Bool) async throws {
        let (engine, _, container) = try await nestedBranchFixture(rootIsBranched: rootIsBranched)
        let active = try #require(container.branchScopes["active"])
        let inactive = try #require(container.branchScopes["inactive"])
        let activePush = try #require(active.path.last)
        let inactivePush = try #require(inactive.path.last)
        let captured = Router(engine: engine, scope: inactivePush)
        let plan = engine.spaces.unwindPlan(for: .root(engine.defaultSpace))
        #expect(plan.removedScopes.contains { $0 === activePush })
        #expect(plan.removedScopes.contains { $0 === inactivePush })
        #expect(plan.preservedPaths.contains { $0.routePath === inactive.path })
        #expect(!plan.pathTrims.contains { $0.path === active.path || $0.path === inactive.path })
        #expect(await Router(engine: engine, scope: container).unwind(to: .root))
        #expect(!container.belongs(to: engine.defaultSpace))
        #expect(!activePush.belongs(to: engine.defaultSpace))
        #expect(!inactivePush.belongs(to: engine.defaultSpace))
        #expect(active.path.last === activePush)
        #expect(inactive.path.last === inactivePush)
        #expect(engine.spaces.routePath(containing: active) == nil)
        #expect(engine.spaces.routePath(containing: inactive) == nil)

        if rootIsBranched {
            let other = try #require(engine.root.branchScopes["other"])
            #expect(other.path.last?.route is TransactionRoute)
            #expect(other.belongs(to: engine.defaultSpace))
            #expect(engine.root.branchScopes["main"]?.path.isEmpty == true)
        } else {
            #expect(engine.defaultSpace.rootPath.isEmpty)
        }

        let inactivePathBefore = inactive.path.scopes.map(ObjectIdentifier.init)
        await captured.present(MessageRoute())
        #expect(inactive.path.scopes.map(ObjectIdentifier.init) == inactivePathBefore)
    }

    @Test func detachingAContainerRemovesItsBranchesFromLiveTopologyWithoutClearingThem() async throws {
        let (engine, outerPath, container) = try await nestedBranchFixture(rootIsBranched: false)
        let active = try #require(container.branchScopes["active"])
        let inactive = try #require(container.branchScopes["inactive"])

        // Detach the owning edge; retained outgoing objects need not be emptied.
        outerPath.keepThrough(.owner)

        #expect(active.path.last?.route is HomeDetailRoute)
        #expect(inactive.path.last?.route is MessageRoute)
        #expect(!active.belongs(to: engine.defaultSpace))
        #expect(!inactive.belongs(to: engine.defaultSpace))
        #expect(engine.spaces.routePath(containing: active) == nil)
        #expect(engine.spaces.routePath(containing: inactive) == nil)
        await Router(engine: engine, scope: engine.root).present(LoginRoute())
        let replacement = try #require(outerPath.last)
        #expect(replacement !== container)
        #expect(replacement.branchScopes["active"]?.path.isEmpty == true)
        #expect(replacement.branchScopes["inactive"]?.path.isEmpty == true)
    }

    @Test func detachedBranchesAreReleasedByARCWhenOutgoingOwnersAreReleased() async throws {
        let (engine, probe) = try await detachBranchSubtree()
        #expect(probe.isReleased)
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }

    @Test func activePositionObservesCanonicalBranchStateWithoutEngineReconciliation() throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches(concurrent: true) {
                Branch(AppTab.home) {}
                Branch(AppTab.wallet) {}
            }
        })
        let home = try #require(engine.root.branchScopes[AppTab.home])
        let wallet = try #require(engine.root.branchScopes[AppTab.wallet])
        let (selection, _) = tabSelection(.home)
        let binding = AnyRouteBranchSelection(selection)
        engine.root.bindBranchSelection(binding)
        let changes = ObservationCount()
        withObservationTracking {
            #expect(engine.activeRouteScopeID == ObjectIdentifier(home))
        } onChange: {
            MainActor.assumeIsolated { changes.value += 1 }
        }
        // A native refresh with the same selection must not invalidate its own projection.
        engine.root.bindBranchSelection(binding)
        #expect(changes.value == 0)
        #expect(engine.root.setActiveBranch(AppTab.wallet))
        #expect(changes.value == 1)
        #expect(engine.activeRouteScopeID == ObjectIdentifier(wallet))
        #expect(engine.routePhase(for: wallet) == .active)
        #expect(engine.routePhase(for: home) == .active)
    }

    @Test func forwardPathsAndNestedModalLanesHaveOneStructuralLocation() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }) {
                Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
                    Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }) {
                        Cover(RouteDestination(AlertRoute.self) { _, _ in EmptyView() })
                    }
                    Branches {
                        Branch("inner") { Push(RouteDestination(MessageRoute.self) { _, _ in EmptyView() }) }
                    }
                }
            }
        })
        await engine.present(NumberedRoute(number: 1))
        await engine.present(LoginRoute())
        await engine.present(HomeDetailRoute())
        await engine.present(AlertRoute())
        let path = engine.defaultSpace.rootPath
        let scopes = path.scopes
        #expect(scopes.count == 4)
        #expect(scopes.map(\.pathDepth) == [1, 2, 3, 4])
        #expect(scopes.map { $0.lane.depth } == [0, 1, 1, 2])
        let push = try #require(scopes.first)
        let sheet = try #require(scopes.first { $0.route is LoginRoute })
        let detail = try #require(scopes.first { $0.route is HomeDetailRoute })
        let cover = try #require(scopes.first { $0.route is AlertRoute })
        let inner = try #require(sheet.branchScopes["inner"])
        #expect(engine.root.continuation === push)
        #expect(engine.root.lane.modal === sheet)
        #expect(sheet.continuation === detail)
        #expect(sheet.lane.modal === cover)
        #expect(inner.lane === sheet.lane)
        #expect(inner.pathDepth == sheet.pathDepth)
        #expect(scopes.allSatisfy { $0.owningPath === path && $0.belongs(to: engine.defaultSpace) })
        let stale = Router(engine: engine, scope: detail)
        #expect(await Router(engine: engine, scope: sheet).unwind(to: .topmostAncestor))
        #expect(path.scopes.count == 1)
        #expect(path.last === push)
        #expect(engine.root.lane.modal == nil)
        #expect(sheet.lane.modal == nil)
        #expect(sheet.continuation === detail)
        #expect(!inner.belongs(to: engine.defaultSpace))
        #expect(!detail.belongs(to: engine.defaultSpace))
        await stale.present(AlertRoute())
        #expect(path.last === push)
    }

    @Test func branchesShareModalCapacityWhileKeepingIndependentForwardPaths() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches(concurrent: true) {
                Branch("home") {
                    Push(RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }) {
                        Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
                            Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }) {
                                Sheet(RouteDestination(AlertRoute.self) { _, _ in EmptyView() })
                            }
                        }
                    }
                }
                Branch("wallet") {
                    Push(RouteDestination(TransactionRoute.self) { _, _ in EmptyView() }) {
                        Sheet(RouteDestination(MessageRoute.self) { _, _ in EmptyView() })
                    }
                }
            }
        })
        let home = try #require(engine.root.branchScopes["home"])
        let wallet = try #require(engine.root.branchScopes["wallet"])
        engine.hostDidAttach(home, view: nil, id: UUID())
        engine.hostDidAttach(wallet, view: nil, id: UUID())
        let router = Router(engine: engine, scope: engine.root)
        await router.branch("home").present(NumberedRoute(number: 1))
        await router.branch("wallet").present(TransactionRoute())
        let homePush = try #require(home.path.last)
        let walletPush = try #require(wallet.path.last)
        await Router(engine: engine, scope: homePush).present(LoginRoute())
        let sheet = try #require(home.path.last)
        await Router(engine: engine, scope: sheet).present(HomeDetailRoute())
        let detail = try #require(home.path.last)
        await Router(engine: engine, scope: detail).present(AlertRoute())
        let nested = try #require(home.path.last)
        #expect(home.lane === wallet.lane)
        #expect(home.lane === engine.root.lane)
        #expect(home.lane.modal === sheet)
        #expect(sheet.lane.modal === nested)
        await Router(engine: engine, scope: walletPush).present(MessageRoute())
        let replacement = try #require(wallet.path.last)
        #expect(replacement.route is MessageRoute)
        #expect(engine.root.lane.modal === replacement)
        #expect(home.path.scopes.count == 1)
        #expect(home.path.last === homePush)
        #expect(wallet.path.scopes.count == 2)
        #expect(wallet.path.first === walletPush)
        #expect(sheet.lane.modal == nil)
        #expect(!sheet.belongs(to: engine.defaultSpace))
        #expect(!nested.belongs(to: engine.defaultSpace))
        #expect(await Router(engine: engine, scope: replacement).unwind(to: .nearestBranch))
        #expect(wallet.path.isEmpty)
        #expect(home.path.last === homePush)
        #expect(engine.root.lane.modal == nil)
    }

    @Test func prioritiesOwnIndependentSpacesAndLocalRoutesKeepTheirPriority() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() }) {
                Push(RouteDestination(NumberedRoute.self) { _, _ in EmptyView() })
            }
        } highPriority: {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
                Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() })
            }
        } criticalPriority: {
            Cover(RouteDestination(AlertRoute.self) { _, _ in EmptyView() }) {
                Sheet(RouteDestination(MessageRoute.self) { _, _ in EmptyView() })
            }
        })
        await engine.present(SettingsRoute())
        await engine.present(NumberedRoute(number: 1))
        await engine.present(LoginRoute())
        await engine.present(HomeDetailRoute())
        await engine.present(AlertRoute())
        await engine.present(MessageRoute())
        let defaultSpace = engine.defaultSpace
        let high = try #require(engine.spaces.highSpace)
        let critical = try #require(engine.spaces.criticalSpace)
        let alert = critical.root
        let criticalModal = try #require(critical.rootPath.last)
        #expect(defaultSpace.root.lane !== high.root.lane)
        #expect(high.root.lane !== critical.root.lane)
        #expect(defaultSpace.root.lane !== critical.root.lane)
        #expect(defaultSpace.rootPath.scopes.map(\.pathDepth) == [1, 2])
        #expect(high.rootPath.scopes.map(\.pathDepth) == [1])
        #expect(critical.rootPath.scopes.map(\.pathDepth) == [1])
        #expect(high.rootPath.scopes.allSatisfy { $0.space === high && $0.routePresentation?.priority == .high })
        #expect(criticalModal.routePresentation?.priority == .critical)
        #expect(critical.root.lane.depth == 0)
        #expect(alert.lane.modal === criticalModal)
        #expect(await Router(engine: engine, scope: alert).unwind(to: .topmostAncestor))
        #expect(engine.spaces.criticalSpace == nil)
        #expect(engine.spaces.highSpace === high)
        #expect(high.rootPath.count == 1)
        #expect(defaultSpace.rootPath.count == 2)
        let login = high.root
        #expect(await Router(engine: engine, scope: login).unwind(to: .topmostAncestor))
        #expect(engine.spaces.highSpace == nil)
        #expect(defaultSpace.root.lane.modal === defaultSpace.rootPath.first)
        #expect(defaultSpace.rootPath.count == 2)
    }
}

@MainActor
private func nestedBranchFixture(rootIsBranched: Bool) async throws -> (RouterEngine, RoutePath, RouteScope) {
    let feature = RouteMap {
        Push(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
            Branches {
                Branch("active") { Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }) }
                Branch("inactive") { Push(RouteDestination(MessageRoute.self) { _, _ in EmptyView() }) }
            }
        }
    }
    let engine = RouterEngine(routes: RootRouteMap {
        if rootIsBranched {
            Branches {
                Branch("main") { feature }
                Branch("other") { Push(RouteDestination(TransactionRoute.self) { _, _ in EmptyView() }) }
            }
        } else {
            feature
        }
    })
    let root = Router(engine: engine, scope: engine.root)
    func present(_ route: any Route, using router: Router) async {
        await router.present(route)
        // Mounted exclusive branch hosts observe selection before the append resumes.
        for _ in 0..<20 where engine.pendingRoute != nil { await Task.yield() }
        #expect(engine.pendingRoute == nil)
    }
    let source: Router
    let outerPath: RoutePath
    if rootIsBranched {
        for branch in engine.root.branchScopes.values { engine.hostDidAttach(branch, view: nil, id: UUID()) }
        await present(TransactionRoute(), using: root.branch("other"))
        source = root.branch("main")
        outerPath = try #require(engine.root.branchScopes["main"]?.path)
    } else {
        source = root
        outerPath = engine.defaultSpace.rootPath
    }
    await present(LoginRoute(), using: source)
    let container = try #require(outerPath.last)
    for branch in container.branchScopes.values { engine.hostDidAttach(branch, view: nil, id: UUID()) }
    let router = Router(engine: engine, scope: container)
    await present(MessageRoute(), using: router.branch("inactive"))
    await present(HomeDetailRoute(), using: router.branch("active"))
    _ = try #require(container.branchScopes["active"]?.path.last)
    _ = try #require(container.branchScopes["inactive"]?.path.last)
    return (engine, outerPath, container)
}

@MainActor private final class ObservationCount { var value = 0 }

@MainActor
private final class BranchLifetimeProbe {
    weak var container: RouteScope?
    weak var active: RouteScope?
    weak var inactive: RouteScope?
    weak var activePush: RouteScope?
    weak var inactivePush: RouteScope?

    init(container: RouteScope) {
        self.container = container
        active = container.branchScopes["active"]
        inactive = container.branchScopes["inactive"]
        activePush = active?.path.last
        inactivePush = inactive?.path.last
    }

    var isReleased: Bool {
        container == nil && active == nil && inactive == nil && activePush == nil && inactivePush == nil
    }
}

@MainActor
private func detachBranchSubtree() async throws -> (RouterEngine, BranchLifetimeProbe) {
    let (engine, path, container) = try await nestedBranchFixture(rootIsBranched: false)
    let probe = BranchLifetimeProbe(container: container)
    path.keepThrough(.owner)
    return (engine, probe)
}
