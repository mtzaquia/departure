import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite(.timeLimit(.minutes(1)))
struct UnwindExecutionTests {
    enum Removal: Sendable { case scoped, owner }
    enum Cancellation: Sendable { case beforeCommit, afterCommit }

    @Test(arguments: [Removal.scoped, .owner], [Cancellation.beforeCommit, .afterCommit])
    func cancellationPreservesTheCommitBoundary(removal: Removal, cancellation: Cancellation) async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
            Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() })
        } highPriority: {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() })
        }, router: owner) { EmptyView() }
        let engine = owner.engine
        let surviving = owner.default
        if removal == .scoped { await owner.current.present(SettingsRoute()) }
        else { await owner.current.present(LoginRoute()) }
        let source = owner.current
        let departing = engine.currentRouteScope
        let probe = CancellationProbe()
        defer {
            probe.task = nil
            engine.root.uninstallHookDeclarations(sourceID: "cancellation")
        }

        if cancellation == .beforeCommit {
            let cancel: @MainActor @Sendable () async -> Void = {
                #expect(engine.spaces.routePath(containing: departing) != nil)
                #expect(engine.isNavigating)
                probe.notifications += 1
                probe.task?.cancel()
            }
            engine.root.installHookDeclarations(sourceID: "cancellation", hookDeclarations: removal == .scoped
                ? [UnwindHandler(SettingsRoute.self, handle: cancel).declaration]
                : [UnwindHandler(LoginRoute.self, handle: cancel).declaration])
        } else {
            engine.routeScopeDidInstallInView(departing)
        }

        let task = Task {
            if removal == .scoped { await source.unwind(to: .topmostAncestor) }
            else { await owner.dismissSpace(.high) }
        }
        probe.task = task
        if cancellation == .beforeCommit {
            #expect(!((await task.value)))
            #expect(probe.notifications == 1)
            #expect(engine.currentRouteScope === departing)
        } else {
            await waitUntil { engine.spaces.routePath(containing: departing) == nil }
            task.cancel()
            let followUp = Task { await surviving.present(HomeDetailRoute()) }
            await waitUntil { engine.pendingRoute != nil }
            #expect(engine.isNavigating)
            #expect(engine.defaultSpace.rootPath.isEmpty)
            engine.routeScopeDidLeaveView(departing)
            #expect(await task.value)
            await followUp.value
            #expect(engine.defaultSpace.rootPath.last?.route is HomeDetailRoute)
        }
        #expect(!engine.isNavigating)
        #expect(!engine.hasOutgoingPresentations)
        #expect(engine.pendingRoute == nil)
    }

    @Test func nativeWritebackWithoutAHandlerCommitsBeforeReturning() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
        })
        await engine.present(SettingsRoute())
        let departing = try #require(engine.defaultSpace.rootPath.last)
        engine.routeScopeDidInstallInView(departing)

        engine.routePresentationBinding(from: engine.root, matching: .sheet).wrappedValue = nil
        #expect(engine.defaultSpace.rootPath.isEmpty)
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
