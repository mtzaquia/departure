import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NavigationOperationTests {
    @Test(arguments: [RoutePriority.high, .critical])
    func overlappingOwnerRemovalsKeepEachOutgoingStackUntilItsOwnCompletion(firstToFinish: RoutePriority) async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Sheet(destination(SettingsRoute.self))
        } highPriority: {
            Sheet(destination(LoginRoute.self)) {
                Push(destination(HomeDetailRoute.self)) {
                    Push(destination(TransactionRoute.self))
                }
            }
        } criticalPriority: {
            Sheet(destination(AlertRoute.self)) {
                Push(destination(HomeDetailRoute.self)) {
                    Push(destination(TransactionRoute.self))
                }
            }
        }, router: owner) { EmptyView() }
        let engine = owner.engine
        await owner.current.present(LoginRoute())
        await owner.current.present(HomeDetailRoute())
        await owner.current.present(TransactionRoute())
        let high = try #require(engine.spaces.highSpace)
        await owner.current.present(AlertRoute())
        await owner.current.present(HomeDetailRoute())
        await owner.current.present(TransactionRoute())
        let critical = try #require(engine.spaces.criticalSpace)
        let highScopes = [high.root] + high.rootPath.scopes
        let criticalScopes = [critical.root] + critical.rootPath.scopes
        for scope in highScopes + criticalScopes { engine.routeScopeDidInstallInView(scope) }

        let removeHigh = Task { await owner.dismissSpace(.high) }
        for _ in 0..<1000 where engine.spaces.highSpace != nil { await Task.yield() }
        let removeCritical = Task { await owner.dismissSpace(.critical) }
        for _ in 0..<1000 where engine.spaces.criticalSpace != nil { await Task.yield() }
        #expect(engine.navigationOperations.count == 2)
        // Both outgoing trees are unreachable to routing, but their native stacks stay intact.
        for scopes in [highScopes, criticalScopes] {
            for (host, push) in zip(scopes, scopes.dropFirst()) {
                #expect(engine.routePresentationBinding(from: host, matching: .push).wrappedValue?.scope === push)
            }
        }
        let next = Task { await owner.current.present(SettingsRoute()) }
        for _ in 0..<1000 where engine.pendingRoute == nil { await Task.yield() }
        #expect(engine.pendingRoute != nil)

        let finished = firstToFinish == .high ? highScopes : criticalScopes
        let remaining = firstToFinish == .high ? criticalScopes : highScopes
        for scope in finished { engine.routeScopeDidLeaveView(scope) }
        if firstToFinish == .high { #expect(await removeHigh.value) }
        else { #expect(await removeCritical.value) }
        #expect(engine.navigationOperations.count == 1)
        #expect(engine.defaultSpace.rootPath.isEmpty)
        for (host, push) in zip(remaining, remaining.dropFirst()) {
            #expect(engine.routePresentationBinding(from: host, matching: .push).wrappedValue?.scope === push)
        }
        for scope in finished {
            #expect(engine.routePresentationBinding(from: scope, matching: .push).wrappedValue == nil)
        }

        for scope in remaining { engine.routeScopeDidLeaveView(scope) }
        if firstToFinish == .high { #expect(await removeCritical.value) }
        else { #expect(await removeHigh.value) }
        await next.value
        #expect(!engine.isNavigating)
        #expect(!engine.hasOutgoingPresentations)
        #expect(engine.pendingRoute == nil)
        #expect(engine.defaultSpace.rootPath.last?.route is SettingsRoute)
    }

    @Test func cancelledReplacementCompletesTeardownWithoutPresentingItsContinuation() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Sheet(destination(SettingsRoute.self))
            Sheet(destination(LoginRoute.self))
        }, router: owner) { EmptyView() }
        await owner.current.present(SettingsRoute())
        let old = try #require(owner.engine.defaultSpace.rootPath.last)
        owner.engine.routeScopeDidInstallInView(old)
        let oldUnwind = UnwindRouteAction(router: owner.engine, routeScope: old)
        let root = Router(engine: owner.engine, scope: owner.engine.root)
        let request = Task { await root.present(LoginRoute()) }
        for _ in 0..<1000 where !owner.engine.defaultSpace.rootPath.isEmpty { await Task.yield() }
        #expect(owner.engine.isNavigating)
        request.cancel()
        owner.engine.routeScopeDidLeaveView(old)
        await request.value
        #expect(owner.engine.defaultSpace.rootPath.isEmpty)
        #expect(!owner.engine.isNavigating)
        #expect(owner.engine.pendingRoute == nil)
        #expect(!(await oldUnwind()))
        await root.present(LoginRoute())
        #expect(owner.engine.defaultSpace.rootPath.last?.route is LoginRoute)
    }

    private func destination<R: Route>(_ type: R.Type) -> RouteDestination<R> {
        RouteDestination(type) { _, _ in EmptyView() }
    }
}
