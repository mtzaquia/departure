import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite(.timeLimit(.minutes(1))) struct CrossPriorityUnwindTests {
    enum Removal: Sendable { case unwindRoute, scoped, owner, native }

    @Test(arguments: [Removal.unwindRoute, .scoped, .owner, .native])
    func lowerHandlerEntersBeforeCommitAndItsPresentationWaitsForRemoval(removal: Removal) async throws {
        let owner = fixture()
        let engine = owner.engine
        await owner.default.present(HomeDetailRoute())
        let landing = try #require(engine.defaultSpace.rootPath.last)
        let probe = Probe()
        landing.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LoginRoute.self) {
                #expect(engine.spaces.highSpace != nil)
                #expect(engine.routePhase(for: landing) == .inactive)
                #expect(engine.isNavigating)
                probe.events.append("handler")
                await owner.default.present(SettingsRoute())
                probe.events.append("completed")
            }.declaration,
        ])
        await owner.current.present(LoginRoute())
        let high = try #require(engine.spaces.highSpace?.root)
        engine.routeScopeDidInstallInView(high)
        let unwind = Task {
            switch removal {
            case .unwindRoute: return await UnwindRouteAction(router: engine, routeScope: high)()
            case .scoped: return await Router(engine: engine, scope: high).dismissSpace()
            case .owner: return await owner.dismissSpace(.high)
            case .native:
                let binding = engine.elevatedRoutePresentationBinding(priority: .high, matching: .sheet)
                binding.wrappedValue = nil
                binding.wrappedValue = nil
                return true
            }
        }
        await waitFor { engine.spaces.highSpace == nil && engine.pendingRoute != nil }
        #expect(probe.events == ["handler"])
        #expect(engine.defaultSpace.rootPath.last === landing)
        #expect(engine.isNavigating)
        engine.routeScopeDidLeaveView(high)
        #expect(await unwind.value)
        await waitFor { probe.events.count == 2 }
        #expect(probe.events == ["handler", "completed"])
        #expect(engine.defaultSpace.rootPath.last?.route is SettingsRoute)
    }

    @Test func lowerHandlerPresentationDropsAfterALocalResetKeepsTheHigherSpace() async throws {
        let owner = fixture()
        let engine = owner.engine
        let probe = Probe()
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(HigherChild.self) {
                #expect(engine.spaces.highSpace?.rootPath.last?.route is HigherChild)
                #expect(engine.isNavigating)
                probe.events.append("handler")
                await owner.default.present(SettingsRoute())
                probe.events.append("completed")
            }.declaration,
        ])
        await owner.current.present(LoginRoute())
        await owner.current.present(HigherChild())
        let space = try #require(engine.spaces.highSpace)
        #expect(await owner.current.unwind(to: .root))
        await waitFor { probe.events.count == 2 }
        #expect(probe.events == ["handler", "completed"])
        #expect(engine.spaces.highSpace === space)
        #expect(space.rootPath.isEmpty)
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }

    @Test func payloadFromAnElevatedRootReachesTheLowerHandler() async {
        let owner = fixture()
        let probe = Probe()
        owner.engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LoginRoute.self, expecting: Int.self) { value in
                #expect(owner.engine.spaces.highSpace != nil)
                probe.events.append("value:\(value)")
            }.declaration,
        ])
        await owner.current.present(LoginRoute())
        #expect(await owner.current.unwind(to: .topmostAncestor, payload: 42))
        #expect(probe.events == ["value:42"])
        #expect(owner.engine.spaces.highSpace == nil)
    }

    @Test func latestCoveredPresentationSupersedesTheEarlierAttemptBeforeCoverageIsChecked() async throws {
        let owner = fixture()
        let engine = owner.engine
        let probe = Probe()
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(HigherChild.self) {
                probe.events.append("handler")
                await owner.default.present(HomeDetailRoute())
                probe.events.append("superseded")
            }.declaration,
        ])
        await owner.current.present(LoginRoute())
        await owner.current.present(HigherChild())
        let child = try #require(engine.spaces.highSpace?.rootPath.last)
        engine.routeScopeDidInstallInView(child)
        let unwind = Task { await owner.current.unwind(to: .root) }
        await waitFor { engine.pendingRoute != nil && engine.spaces.highSpace?.rootPath.isEmpty == true }
        let latest = Task {
            await owner.default.present(SettingsRoute())
            probe.events.append("dropped")
        }
        await waitFor { probe.events == ["handler", "superseded"] }
        #expect(engine.pendingRoute != nil)
        #expect(engine.defaultSpace.rootPath.isEmpty)
        engine.routeScopeDidLeaveView(child)
        #expect(await unwind.value)
        await latest.value
        #expect(probe.events == ["handler", "superseded", "dropped"])
        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(engine.spaces.highSpace != nil)
    }

    @Test(arguments: [false, true])
    func nearestLowerPriorityWinsAndAConflictPreventsFurtherFallback(conflict: Bool) async throws {
        let owner = fixture()
        let probe = Probe()
        owner.engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LockRoute.self) { probe.events.append("default") }.declaration,
        ])
        await owner.current.present(LoginRoute())
        let high = try #require(owner.engine.spaces.highSpace?.root)
        high.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LockRoute.self) { probe.events.append("high") }.declaration,
        ])
        if conflict {
            high.installHookDeclarations(sourceID: "second", hookDeclarations: [
                UnwindHandler(LockRoute.self) { probe.events.append("conflict") }.declaration,
            ])
        }
        await owner.current.present(LockRoute())
        #expect(await owner.current.dismissSpace())
        #expect(probe.events == (conflict ? [] : ["high"]))
        #expect(owner.engine.spaces.highSpace?.root === high)
    }

    @Test(arguments: [false, true])
    func localHandlerWinsAndALocalConflictBlocksLowerHandlers(conflict: Bool) async throws {
        let owner = fixture()
        let probe = Probe()
        owner.engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(HigherChild.self) { probe.events.append("default") }.declaration,
        ])
        await owner.current.present(LoginRoute())
        let high = try #require(owner.engine.spaces.highSpace?.root)
        high.installHookDeclarations(hookDeclarations: [
            UnwindHandler(HigherChild.self) { probe.events.append("local") }.declaration,
        ])
        if conflict {
            high.installHookDeclarations(sourceID: "second", hookDeclarations: [
                UnwindHandler(HigherChild.self) { probe.events.append("conflict") }.declaration,
            ])
        }
        await owner.current.present(HigherChild())
        #expect(await owner.current.unwind(to: .root))
        #expect(probe.events == (conflict ? [] : ["local"]))
    }

    @Test func combinedRemovalSkipsHandlersInTheAlsoRemovedLowerSpace() async throws {
        let owner = fixture()
        let probe = Probe()
        owner.engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LoginRoute.self) { probe.events.append("high") }.declaration,
            UnwindHandler(LockRoute.self) { probe.events.append("critical") }.declaration,
        ])
        await owner.current.present(LoginRoute())
        let high = try #require(owner.engine.spaces.highSpace?.root)
        high.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LockRoute.self) { probe.events.append("outgoing-high") }.declaration,
        ])
        await owner.current.present(LockRoute())
        #expect(await owner.dismissSpaces())
        #expect(probe.events == ["critical", "high"])
        #expect(owner.engine.spaces.activeSpace === owner.engine.defaultSpace)
    }

    @Test func coveredOwnerRemovalNotifiesWithoutNavigatingBehindCritical() async throws {
        let owner = fixture()
        let probe = Probe()
        owner.engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LoginRoute.self) {
                probe.events.append("handler")
                await owner.default.present(SettingsRoute())
                probe.events.append("completed")
            }.declaration,
        ])
        await owner.current.present(LoginRoute())
        await owner.current.present(LockRoute())
        let critical = try #require(owner.engine.spaces.criticalSpace)
        #expect(await owner.dismissSpace(.high))
        await waitFor { probe.events.count == 2 }
        #expect(probe.events == ["handler", "completed"])
        #expect(owner.engine.defaultSpace.rootPath.isEmpty)
        #expect(owner.engine.spaces.criticalSpace === critical)
    }

    @Test func elevatedReplacementNotifiesWithoutExposingDefaultNavigation() async {
        let owner = fixture()
        let probe = Probe()
        owner.engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LoginRoute.self) {
                #expect(owner.engine.spaces.highSpace?.root.route is LoginRoute)
                probe.events.append("handler")
                await owner.default.present(SettingsRoute())
                probe.events.append("completed")
            }.declaration,
        ])
        await owner.current.present(LoginRoute())
        await owner.current.present(OtherHighRoot())
        await waitFor { probe.events.count == 2 }
        #expect(probe.events == ["handler", "completed"])
        #expect(owner.engine.spaces.highSpace?.root.route is OtherHighRoot)
        #expect(owner.engine.defaultSpace.rootPath.isEmpty)
    }

    private func fixture() -> RootRouter {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() })
            Push(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
        } highPriority: {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
                Push(RouteDestination(HigherChild.self) { _, _ in EmptyView() })
            }
            Cover(RouteDestination(OtherHighRoot.self) { _, _ in EmptyView() })
        } criticalPriority: {
            Cover(RouteDestination(LockRoute.self) { _, _ in EmptyView() })
        }, router: owner) { EmptyView() }
        return owner
    }
}

@MainActor private final class Probe { var events: [String] = [] }
private struct HigherChild: Route {}
private struct OtherHighRoot: Route {}

@MainActor private func waitFor(_ condition: () -> Bool) async {
    for _ in 0..<1000 where !condition() { await Task.yield() }
    #expect(condition())
}
