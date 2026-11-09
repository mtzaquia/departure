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
        let retained = try #require(engine.tree.rootPath.last)
        retained.installHookDeclarations(hookDeclarations: [
            UnwindHandler(Child.self) { events.values.append("child") }.declaration,
        ])
        await owner.current.present(Child())
        let outgoing = try #require(engine.tree.rootPath.last)
        engine.routeScopeDidInstallInView(outgoing)
        let request = Task { await owner.current.present(Parent(value: 1)) }
        await waitUntil { engine.tree.rootPath.count == 1 }
        #expect(engine.tree.rootPath.last === retained)
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
        #expect(await owner.current.unwind(.current))
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
        let old = try #require(engine.tree.rootPath.last)
        await owner.current.present(Child())
        await owner.current.present(Parent(value: 2))
        #expect(engine.tree.rootPath.count == 1)
        #expect(engine.tree.rootPath.last !== old)
        #expect((engine.tree.rootPath.last?.route as? Parent)?.value == 2)
        #expect(events.values.isEmpty)
        #expect(await owner.current.unwind(.current))
        #expect(events.values == ["parent"])
    }

    private func localFixture(_ style: Style) -> RootRouter {
        let owner = RootRouter()
        let children = RouteMap { testPush(destination(Child.self)) }
        _ = WithRouter(routes: RootRouteMap {
            switch style {
            case .push: testPush(destination(Parent.self)) { children }
            case .replace: testReplace(destination(Parent.self)) { children }
            case .sheet: testSheet(destination(Parent.self)) { children }
            case .cover: testCover(destination(Parent.self)) { children }
            }
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
