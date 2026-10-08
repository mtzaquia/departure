import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RouteRequestCompletionTests {
    @Test(arguments: [false, true])
    func branchPresentationReturnsItsExactDestinationAfterReveal(concurrent: Bool) async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches(concurrent: concurrent) {
                Branch("first") {}
                Branch("second") { Sheet(destination(SettingsRoute.self)) }
            }
        })
        let branch = try #require(engine.root.branchScopes["second"])
        let result = await engine.requestRouteWhenReady(SettingsRoute(), origin: RouteRequestOrigin(scope: engine.root))
        // A resumed native host and the scheduled mounted-host refresh must not insert twice.
        engine.routeScopeDidInstallInView(branch)
        engine.resumePendingRoute(for: "second", in: engine.root)
        #expect(result === branch.path.last)
        #expect(branch.path.count == 1)
        #expect(engine.pendingRoute == nil)
        #expect(!engine.isNavigating)
    }

    @Test func equivalentRouteReturnsTheReusedScopeAfterTeardown() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(destination(HomeDetailRoute.self)) { Sheet(destination(SettingsRoute.self)) }
        })
        await engine.present(HomeDetailRoute())
        let reused = try #require(engine.defaultSpace.rootPath.last)
        await engine.present(SettingsRoute())
        let outgoing = try #require(engine.defaultSpace.rootPath.last)
        engine.routeScopeDidInstallInView(outgoing)
        let request = Task { await engine.requestRouteWhenReady(HomeDetailRoute()) }
        for _ in 0..<1000 where !engine.isNavigating { await Task.yield() }
        #expect(engine.defaultSpace.rootPath.last === reused)
        engine.routeScopeDidLeaveView(outgoing)
        #expect(await request.value === reused)
        #expect(!engine.isNavigating)
    }

    @Test(arguments: [RoutePriority.high, .critical])
    func elevatedPresentationAndReuseReturnTheSpaceRoot(priority: RoutePriority) async throws {
        let engine = RouterEngine(routes: RootRouteMap {} highPriority: {
            Sheet(destination(LoginRoute.self)) { Push(destination(HomeDetailRoute.self)) }
        } criticalPriority: {
            Sheet(destination(CriticalEntry.self)) { Push(destination(HomeDetailRoute.self)) }
        })
        let route: any Route = priority == .high ? LoginRoute() : CriticalEntry()
        let result = await engine.requestRouteWhenReady(route)
        let root = try #require(engine.spaces.space(for: priority)?.root)
        #expect(result === root)
        await engine.present(HomeDetailRoute())
        #expect(await engine.requestRouteWhenReady(route) === root)
        #expect(root.path.isEmpty)
    }

    @Test(arguments: [false, true])
    func nestedInvalidSelectionDoesNotPartiallyRevealItsAncestors(duplicateOwners: Bool) async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches {
                Branch("first") {}
                Branch("second") {
                    Branches {
                        Branch("inner-first") {}
                        Branch("inner-second") { Push(destination(SettingsRoute.self)) }
                    }
                }
            }
        })
        let inner = try #require(engine.root.branchScopes["second"])
        if duplicateOwners {
            for _ in 0..<2 {
                inner.bindRoutingHost(RoutePresentationHostID(), automatic: false, environment: inner.sourceEnvironment,
                    selection: AnyRouteBranchSelection(Binding.constant("inner-first")))
            }
        } else {
            inner.bindRoutingHost(RoutePresentationHostID(), automatic: false, environment: inner.sourceEnvironment,
                selection: AnyRouteBranchSelection(Binding.constant(0)))
        }
        await Router(engine: engine, scope: engine.root).branch("second").branch("inner-second").present(SettingsRoute())
        #expect(engine.root.activeBranch == AnyHashable("first"))
        #expect(inner.activeBranch == AnyHashable("inner-first"))
        #expect(inner.branchScopes.values.allSatisfy { $0.path.isEmpty })
        #expect(engine.pendingRoute == nil)
    }

    @Test func invalidEnclosingSelectionDoesNotRevealAnOuterTabForADeeperDestination() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches {
                Branch("first") {}
                Branch("second") {
                    Branches {
                        Branch("inner-first") {}
                        Branch("inner-second") {
                            Push(destination(RootRoute.self)) { Push(destination(SettingsRoute.self)) }
                        }
                    }
                }
            }
        })
        await Router(engine: engine, scope: engine.root).branch("second").branch("inner-second").present(RootRoute())
        let inner = try #require(engine.root.branchScopes["second"])
        let branch = try #require(inner.branchScopes["inner-second"])
        // The prior implementation returned before deferred insertion. Complete
        // that same native staging step before comparing selection behavior.
        engine.routeScopeDidInstallInView(branch)
        let source = try #require(branch.path.last)
        #expect(engine.activateBranch("first", in: engine.root))
        for _ in 0..<2 {
            inner.bindRoutingHost(RoutePresentationHostID(), automatic: false, environment: inner.sourceEnvironment,
                selection: AnyRouteBranchSelection(Binding.constant("inner-second")))
        }
        await Router(engine: engine, scope: source).present(SettingsRoute())
        #expect(engine.root.activeBranch == AnyHashable("first"))
        #expect(inner.branchScopes["inner-second"]?.path.last === source)
        #expect(engine.pendingRoute == nil)
    }

    @Test func actionRerouteFromABranchRetriesAtItsCommonAncestorDestination() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Sheet(destination(SettingsRoute.self))
            Branches(concurrent: true) {
                Branch("first") { Push(destination(HomeDetailRoute.self)) }
                Branch("second") {}
            }
        }, router: owner) { EmptyView() }
        await owner.current.present(HomeDetailRoute())
        let branch = try #require(owner.engine.root.branchScopes["first"])
        let source = try #require(branch.path.last)
        owner.engine.routeScopeDidInstallInView(source)
        var events: [String] = []
        let action = AncestorRerouteAction { events.append($0) }
        await Router(engine: owner.engine, scope: source).perform(action)
        for _ in 0..<1000 where owner.engine.defaultSpace.rootPath.isEmpty { await Task.yield() }
        let target = try #require(owner.engine.defaultSpace.rootPath.last)
        target.installHookDeclarations(hookDeclarations: [
            ActionInterceptor(AncestorRerouteAction.self) { invocation in
                events.append("destination interceptor")
                try? await invocation()
            }.declaration,
        ])
        #expect(events == ["reroute"])
        owner.engine.routeScopeDidInstallInView(target)
        for _ in 0..<1000 where events.count < 3 { await Task.yield() }
        #expect(events == ["reroute", "destination interceptor", "ran"])
    }

    @Test func supersededBufferedRequestReturnsNilAndLatestReturnsItsDestination() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Sheet(destination(SettingsRoute.self))
            Sheet(destination(LoginRoute.self))
            Sheet(destination(HomeDetailRoute.self))
        }, router: owner) { EmptyView() }
        let origin = RouteRequestOrigin(scope: owner.engine.root)
        await owner.current.present(SettingsRoute())
        let outgoing = try #require(owner.engine.defaultSpace.rootPath.last)
        owner.engine.routeScopeDidInstallInView(outgoing)
        let unwind = Task { await owner.current.unwind(to: .root) }
        for _ in 0..<1000 where !owner.engine.isNavigating { await Task.yield() }
        let first = Task { await owner.engine.requestRouteWhenReady(LoginRoute(), origin: origin) }
        for _ in 0..<1000 where owner.engine.pendingRoute == nil { await Task.yield() }
        let latest = Task { await owner.engine.requestRouteWhenReady(HomeDetailRoute(), origin: origin) }
        for _ in 0..<1000 where !(owner.engine.pendingRoute?.route is HomeDetailRoute) { await Task.yield() }
        #expect(await first.value == nil)
        owner.engine.routeScopeDidLeaveView(outgoing)
        #expect(await unwind.value)
        #expect(await latest.value === owner.engine.defaultSpace.rootPath.last)
        #expect(owner.engine.defaultSpace.rootPath.last?.route is HomeDetailRoute)
        #expect(owner.engine.pendingRoute == nil)
    }

    private func destination<R: Route>(_ type: R.Type) -> RouteDestination<R> {
        RouteDestination(type) { _, _ in EmptyView() }
    }
}

@MainActor
private struct AncestorRerouteAction: Action {
    let record: (String) -> Void
    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        guard context.isRunning(in: SettingsRoute.self) else {
            record("reroute")
            throw .reroute(SettingsRoute())
        }
        record("ran")
    }
}

private struct CriticalEntry: Route, Equatable {}
