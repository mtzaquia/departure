import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct UnwindPresentationPolicyTests {
    enum PushJump: String, CaseIterable, Sendable {
        case ancestor
        case id
        case capturedAction
    }

    @Test(arguments: PushJump.allCases)
    func capturedPushOnlyJumpsShareAnimationPolicy(jump: PushJump) async throws {
        let engine = RouterEngine()
        let scopes = (1...3).map { RouteScope(id: $0, route: NumberedRoute(number: $0)) }
        let hosts = [engine.root] + Array(scopes.dropLast())
        for (host, scope) in zip(hosts, scopes) {
            host.defineTestMap(
                id: nil,
                selection: nil,
                definitions: [RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(NumberedRoute.self) { route, _ in EmptyView() }, kind: .push)._routeDeclarations)]
            )
            scope.attachPresentation(to: host, declaration: try #require(host.routeAttachments.first))
            engine.routeScopeDidInstallInView(scope)
        }
        engine.normalSpace.rootPath.replaceTestPath(scopes)
        let router = Router(engine: engine, scope: scopes[0])
        let unwind = Task {
            switch jump {
            case .ancestor:
                await router.unwind(to: .topmostAncestor)
            case .id:
                await router.unwind(to: .id(engine.root.id))
            case .capturedAction:
                await UnwindRouteAction(router: engine, routeScope: scopes[0])()
            }
        }
        for _ in 0..<100 where !engine.normalSpace.rootPath.isEmpty { await Task.yield() }

        #expect(engine.normalSpace.rootPath.isEmpty)
        #expect(engine.unwindPresentationSnapshot != nil)
        #expect(!engine.pushPresentationDismissalDisablesAnimations(from: engine.root))
        #expect(engine.pushPresentationDismissalDisablesAnimations(from: scopes[0]))
        #expect(engine.pushPresentationDismissalDisablesAnimations(from: scopes[1]))
        for host in hosts {
            #expect(engine.routePresentationBinding(from: host, matching: .push).wrappedValue == nil)
        }

        for scope in scopes { engine.routeScopeDidLeaveView(scope) }
        #expect(await unwind.value)
        #expect(engine.unwindPresentationSnapshot == nil)
    }

    @Test(arguments: [RoutePriority.normal, .high, .critical])
    func equivalentRoutesKeepDepartingModalStacks(priority: RoutePriority) async throws {
        let engine = RouterEngine()
        engine.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, kind: .sheet(priority: priority))._routeDeclarations)]
        )
        await Router(engine: engine, scope: engine.root).present(LoginRoute())
        let space = try #require(engine.spaces.space(for: priority))
        let retained = space.priority == .normal ? try #require(space.rootPath.last) : space.root
        retained.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, kind: .sheet(priority: .normal))._routeDeclarations)]
        )
        await Router(engine: engine, scope: retained).present(SettingsRoute())
        let sheet = try #require(space.rootPath.last)
        sheet.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(HomeDetailRoute.self) { route, _ in EmptyView() }, kind: .push)._routeDeclarations)]
        )
        await Router(engine: engine, scope: sheet).present(HomeDetailRoute())
        let push = try #require(space.rootPath.last)
        engine.routeScopeDidInstallInView(sheet)
        engine.routeScopeDidInstallInView(push)

        let request = Task { await Router(engine: engine, scope: push).present(LoginRoute()) }
        for _ in 0..<1000 where space.rootPath.count > (space.priority == .normal ? 1 : 0) { await Task.yield() }

        #expect(space.rootPath.scopes.elementsEqual(space.priority == .normal ? [retained] : [], by: { $0 === $1 }))
        #expect(engine.unwindPresentationSnapshot != nil)
        #expect(engine.routePresentationBinding(from: retained, matching: .sheet).wrappedValue == nil)
        #expect(engine.routePresentationBinding(from: sheet, matching: .push).wrappedValue?.scope === push)

        engine.routeScopeDidLeaveView(sheet)
        engine.routeScopeDidLeaveView(push)
        await request.value
        #expect(space.rootPath.scopes.elementsEqual(space.priority == .normal ? [retained] : [], by: { $0 === $1 }))
        #expect(engine.unwindPresentationSnapshot == nil)
    }
}
