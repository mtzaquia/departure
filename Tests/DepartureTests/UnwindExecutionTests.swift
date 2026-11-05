import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite(.timeLimit(.minutes(1)))
struct UnwindExecutionTests {
    enum Removal: Sendable { case scoped, owner }
    enum Cancellation: Sendable { case beforeCommit, afterCommit }

    @Test func nativeWritebackWithoutAHandlerCommitsBeforeReturning() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            testSheet(testDestination(SettingsRoute.self))
        })
        await engine.present(SettingsRoute())
        let departing = try #require(engine.tree.rootPath.last)
        engine.routeScopeDidInstallInView(departing)

        engine.routePresentationBinding(from: engine.root, matching: .sheet).wrappedValue = nil
        #expect(engine.tree.rootPath.isEmpty)
        #expect(engine.isNavigating)
        engine.routeScopeDidLeaveView(departing)
        await waitUntil { !engine.isNavigating }
        #expect(!engine.hasOutgoingPresentations)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
        #expect(condition())
    }
}

@MainActor private final class CancellationProbe {
    var notifications = 0
    var task: Task<Bool, Never>?
}
