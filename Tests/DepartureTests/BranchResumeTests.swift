import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BranchResumeTests {
    @Test(arguments: [false, true])
    func hostRegistrationResumesAfterItsCallback(removeBeforeResume: Bool) async throws {
        let (engine, branch, pending) = try await pendingBranchPresentation()
        engine.resumePendingRoute(for: AppTab.home, in: engine.root)
        engine.resumePendingRoute(for: AppTab.home, in: engine.root)
        #expect(branch.path.isEmpty)
        #expect(engine.pendingRoute === pending)

        if removeBeforeResume {
            engine.root.unregisterBranchScope(branch, for: AppTab.home)
            for _ in 0..<20 { await Task.yield() }
            #expect(branch.path.isEmpty)
            #expect(engine.pendingRoute === pending)
            engine.root.registerBranchScope(branch, for: AppTab.home)
            engine.resumePendingRoute(for: AppTab.home, in: engine.root)
        }

        for _ in 0..<1000 where engine.pendingRoute != nil { await Task.yield() }
        #expect(engine.pendingRoute == nil)
        #expect(branch.path.count == 1)
        #expect(branch.path.last?.route as? NumberedRoute == NumberedRoute(number: 1))
    }

    @Test func anOlderHostWakeDoesNotConsumeAReplacementPendingAppend() async throws {
        let (engine, branch, pending) = try await pendingBranchPresentation()
        engine.resumePendingRoute(for: AppTab.home, in: engine.root)
        let append = try #require(pending.append)
        let replacement = RouterEngine.PendingRoute(route: NumberedRoute(number: 2), state: .append(append))
        engine.replacePendingRoute(replacement)
        for _ in 0..<20 { await Task.yield() }
        #expect(branch.path.isEmpty)
        #expect(engine.pendingRoute === replacement)

        engine.resumePendingRoute(for: AppTab.home, in: engine.root)
        for _ in 0..<1000 where engine.pendingRoute != nil { await Task.yield() }
        #expect(engine.pendingRoute == nil)
        #expect(branch.path.count == 1)
        #expect(branch.path.last?.route as? NumberedRoute == NumberedRoute(number: 2))
    }

    private func pendingBranchPresentation() async throws -> (RouterEngine, RouteScope, RouterEngine.PendingRoute) {
        let engine = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        engine.root.installRouteDeclarations(id: nil, branchSelection: AnyRouteBranchSelection(selection), routeDeclarations: [
            RouteScopeDeclaration(branch: AppTab.home, routes: Sheet(NumberedRoute.self)._routeDeclarations),
            RouteScopeDeclaration(branch: AppTab.wallet, routes: Push(TransactionRoute.self)._routeDeclarations),
        ])
        await engine.requestRoute(NumberedRoute(number: 1))
        let pending = try #require(engine.pendingRoute)
        let branch = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        branch.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(NumberedRoute.self)._routeDeclarations),
        ])
        engine.root.registerBranchScope(branch, for: AppTab.home)
        return (engine, branch, pending)
    }
}
