import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NavigationOperationTests {
    @Test(arguments: [false, true])
    func branchContinuationKeepsItsCallerUntilInsertionOrSupersession(insert: Bool) async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches { Branch("host") { testPush(destination(SettingsRoute.self)) } }
        })
        let branch = try #require(engine.root.branchScopes["host"])
        let match = try #require(engine.tree.firstDeclaration(including: SettingsRoute.self)?.declaration)
        let operation = RouterEngine.NavigationOperation(awaitingHost: .init(route: SettingsRoute(), match: match))
        engine.replacePendingRoute(.presentation(operation))
        var started = false, completed = false
        let caller = Task {
            started = true
            let destination = await operation.waitForPresentation()
            completed = true
            return destination
        }
        for _ in 0..<1000 where !started { await Task.yield() }
        #expect(!completed)
        if insert { engine.routeScopeDidInstallInView(branch) }
        else { engine.replacePendingRoute(nil) }
        let presentedScope = await caller.value
        #expect(completed)
        #expect(presentedScope === (insert ? branch.path.last : nil))
        #expect(branch.path.count == (insert ? 1 : 0))
        engine.resumePendingRoute(for: "host", in: engine.root)
        #expect(branch.path.count == (insert ? 1 : 0))
        #expect(engine.pendingRoute == nil)
    }

    @Test func cancelledReplacementCompletesTeardownWithoutPresentingItsContinuation() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            testSheet(destination(SettingsRoute.self))
            testSheet(destination(LoginRoute.self))
        }, router: owner) { EmptyView() }
        await owner.current.present(SettingsRoute())
        let old = try #require(owner.engine.tree.rootPath.last)
        owner.engine.routeScopeDidInstallInView(old)
        let oldUnwind = UnwindRouteAction(router: owner.engine, routeScope: old)
        let root = Router(engine: owner.engine, scope: owner.engine.root)
        let request = Task { await root.present(LoginRoute()) }
        for _ in 0..<1000 where !owner.engine.tree.rootPath.isEmpty { await Task.yield() }
        #expect(owner.engine.isNavigating)
        request.cancel()
        owner.engine.routeScopeDidLeaveView(old)
        await request.value
        #expect(owner.engine.tree.rootPath.isEmpty)
        #expect(!owner.engine.isNavigating)
        #expect(owner.engine.pendingRoute == nil)
        #expect(!(await oldUnwind()))
        await root.present(LoginRoute())
        #expect(owner.engine.tree.rootPath.last?.route is LoginRoute)
    }

    private func destination<R: Route>(_ type: R.Type) -> RouteDestination<R> {
        RouteDestination(type) { _, _ in EmptyView() }
    }
}
