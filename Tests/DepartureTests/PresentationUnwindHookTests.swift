import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite(.timeLimit(.minutes(1))) struct PresentationUnwindHookTests {
    enum Style: CaseIterable, Sendable { case push, replace, sheet, cover }

    @Test(arguments: Style.allCases)
    func equalityReuseSkipsHandlersAndStillWaitsForOutgoingTeardown(style: Style) async throws {
        let owner = localFixture(style)
        let engine = owner.engine
        let events = Events()
        await owner.current.present(Parent(value: 1))
        let retained = try #require(engine.defaultSpace.rootPath.last)
        retained.installHookDeclarations(hookDeclarations: [
            UnwindHandler(Child.self) { events.values.append("child") }.declaration,
        ])
        await owner.current.present(Child())
        let outgoing = try #require(engine.defaultSpace.rootPath.last)
        engine.routeScopeDidInstallInView(outgoing)
        let request = Task { await owner.current.present(Parent(value: 1)) }
        await waitUntil { engine.defaultSpace.rootPath.count == 1 }
        #expect(engine.defaultSpace.rootPath.last === retained)
        #expect(events.values.isEmpty)
        #expect(engine.isNavigating)
        // Outgoing native write-back cannot turn presentation cleanup into notification.
        engine.routePresentationBinding(from: retained, matching: .push).wrappedValue = nil
        #expect(events.values.isEmpty)
        engine.routeScopeDidLeaveView(outgoing)
        await request.value
        #expect(!engine.isNavigating)
        #expect(!engine.hasOutgoingPresentations)
        #expect(events.values.isEmpty)

        await owner.current.present(Child())
        #expect(await owner.current.unwind(to: .topmostAncestor))
        #expect(events.values == ["child"])
    }

    @Test(arguments: Style.allCases)
    func ancestorCrawlbackSkipsHandlersWhenPresentingADifferentValue(style: Style) async throws {
        let owner = localFixture(style)
        let engine = owner.engine
        let events = Events()
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(Parent.self) { events.values.append("parent") }.declaration,
            UnwindHandler(Child.self) { events.values.append("child") }.declaration,
        ])
        await owner.current.present(Parent(value: 1))
        let old = try #require(engine.defaultSpace.rootPath.last)
        await owner.current.present(Child())
        await owner.current.present(Parent(value: 2))
        #expect(engine.defaultSpace.rootPath.count == 1)
        #expect(engine.defaultSpace.rootPath.last !== old)
        #expect((engine.defaultSpace.rootPath.last?.route as? Parent)?.value == 2)
        #expect(events.values.isEmpty)
        #expect(await owner.current.unwind(to: .topmostAncestor))
        #expect(events.values == ["parent"])
    }

    @Test(arguments: [RoutePriority.high, .critical], [false, true])
    func elevatedEqualityReuseSkipsLocalAndLowerSpaceHandlers(priority: RoutePriority, local: Bool) async throws {
        let owner = elevatedFixture(priority)
        let engine = owner.engine
        let events = Events()
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(Child.self) { events.values.append("lower") }.declaration,
        ])
        await owner.current.present(Parent(value: 1))
        let space = try #require(engine.spaces.space(for: priority))
        if local {
            space.root.installHookDeclarations(hookDeclarations: [
                UnwindHandler(Child.self) { events.values.append("local") }.declaration,
            ])
        }
        await owner.current.present(Child())
        await owner.current.present(Parent(value: 1))
        #expect(engine.spaces.space(for: priority) === space)
        #expect(space.rootPath.isEmpty)
        #expect(events.values.isEmpty)
        await owner.current.present(Child())
        #expect(await owner.current.unwind(to: .root))
        #expect(events.values == [local ? "local" : "lower"])
    }

    @Test(arguments: [RoutePriority.high, .critical])
    func elevatedReplacementSkipsLowerHandlersButExplicitRemovalStillNotifies(priority: RoutePriority) async throws {
        let owner = elevatedFixture(priority)
        let engine = owner.engine
        let events = Events()
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(Parent.self) { events.values.append("parent") }.declaration,
        ])
        await owner.current.present(Parent(value: 1))
        let old = try #require(engine.spaces.space(for: priority))
        await owner.current.present(Child())
        await owner.current.present(Parent(value: 2))
        #expect(engine.spaces.space(for: priority) !== old)
        #expect((engine.spaces.space(for: priority)?.root.route as? Parent)?.value == 2)
        #expect(events.values.isEmpty)
        #expect(await owner.current.dismissSpace())
        #expect(events.values == ["parent"])
    }

    private func localFixture(_ style: Style) -> RootRouter {
        let owner = RootRouter()
        let children = RouteMap { Push(destination(Child.self)) }
        _ = WithRouter(routes: RootRouteMap {
            switch style {
            case .push: Push(destination(Parent.self)) { children }
            case .replace: Replace(destination(Parent.self)) { children }
            case .sheet: Sheet(destination(Parent.self)) { children }
            case .cover: Cover(destination(Parent.self)) { children }
            }
        }, router: owner) { EmptyView() }
        return owner
    }

    private func elevatedFixture(_ priority: RoutePriority) -> RootRouter {
        let owner = RootRouter()
        let entries = ModalRouteMap {
            Sheet(destination(Parent.self)) { Push(destination(Child.self)) }
        }
        _ = WithRouter(routes: RootRouteMap {} highPriority: {
            if priority == .high { entries }
        } criticalPriority: {
            if priority == .critical { entries }
        }, router: owner) { EmptyView() }
        return owner
    }

    private func destination<R: Route>(_ type: R.Type) -> RouteDestination<R> {
        RouteDestination(type) { _, _ in EmptyView() }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
        #expect(condition())
    }
}

@MainActor private final class Events { var values: [String] = [] }
private struct Parent: Route, Equatable { let value: Int }
private struct Child: Route {}
