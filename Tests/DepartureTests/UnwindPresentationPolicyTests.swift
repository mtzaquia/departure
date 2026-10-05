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
            host.installRouteDeclarations(
                id: nil,
                branchSelection: nil,
                routeDeclarations: [RouteScopeDeclaration(routes: Push(NumberedRoute.self)._routeDeclarations)]
            )
            scope.attachPresentation(to: host, declaration: try #require(host.routeAttachments.first))
            engine.routeScopeDidInstallInView(scope)
        }
        engine.normalTree.rootPath.scopes = scopes
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
        for _ in 0..<100 where !engine.normalTree.rootPath.isEmpty { await Task.yield() }

        #expect(engine.normalTree.rootPath.isEmpty)
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
        engine.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [RouteScopeDeclaration(routes: Sheet(LoginRoute.self, priority: priority)._routeDeclarations)]
        )
        await Router(engine: engine, scope: engine.root).present(LoginRoute())
        let tree = try #require(engine.routeForest.tree(for: priority))
        let retained = try #require(tree.rootPath.last)
        retained.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations)]
        )
        await Router(engine: engine, scope: retained).present(SettingsRoute())
        let sheet = try #require(tree.rootPath.last)
        sheet.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations)]
        )
        await Router(engine: engine, scope: sheet).present(HomeDetailRoute())
        let push = try #require(tree.rootPath.last)
        engine.routeScopeDidInstallInView(sheet)
        engine.routeScopeDidInstallInView(push)

        let request = Task { await Router(engine: engine, scope: push).present(LoginRoute()) }
        for _ in 0..<100 where tree.rootPath.count > 1 { await Task.yield() }

        #expect(tree.rootPath.scopes.elementsEqual([retained], by: { $0 === $1 }))
        #expect(engine.unwindPresentationSnapshot != nil)
        #expect(engine.unwindPresentationSnapshot?.preservesModalPresentationBindings == false)
        #expect(engine.routePresentationBinding(from: retained, matching: .sheet).wrappedValue == nil)
        #expect(engine.routePresentationBinding(from: sheet, matching: .push).wrappedValue?.scope === push)

        engine.routeScopeDidLeaveView(sheet)
        engine.routeScopeDidLeaveView(push)
        await request.value
        #expect(tree.rootPath.scopes.elementsEqual([retained], by: { $0 === $1 }))
        #expect(engine.unwindPresentationSnapshot == nil)
    }
}
