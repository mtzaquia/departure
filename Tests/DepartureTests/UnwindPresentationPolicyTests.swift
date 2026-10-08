import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct UnwindPresentationPolicyTests {
    @Test(arguments: [RoutePriority.default, .high, .critical])
    func oldNativeBindingCannotDismissANewInstanceWithTheSameRouteID(priority: RoutePriority) async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() })
        } highPriority: {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
        } criticalPriority: {
            Sheet(RouteDestination(AlertRoute.self) { _, _ in EmptyView() })
        })
        let owner = RootRouter(engine: engine)
        let route: any Route = switch priority {
        case .default: LoginRoute()
        case .high: SettingsRoute()
        case .critical: AlertRoute()
        }
        await owner.current.present(route)
        let original = try #require(engine.spaces.space(for: priority)?.currentRouteScope)
        engine.routeScopeDidInstallInView(original)
        let target: RouterEngine.PresentationTarget = priority == .default ? .local(engine.root, nil) : .priority(priority)
        let binding = engine.presentationBinding(for: target, matching: .sheet)
        #expect(binding.wrappedValue?.scope === original)
        binding.wrappedValue = nil
        engine.routeScopeDidLeaveView(original)
        await owner.current.present(route)
        let replacement = try #require(binding.wrappedValue?.scope)
        #expect(replacement !== original)
        #expect(replacement.id == original.id)
        binding.wrappedValue = nil
        #expect(binding.wrappedValue?.scope === replacement)
        #expect(engine.isNavigationEligible(replacement))
    }

    @Test func outgoingBranchBindingsKeepTheirCapturedEnvironmentWithoutRoutingAuthority() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
                Branches(concurrent: true) {
                    Branch("modal") {
                        Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() }) {
                            Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() })
                        }
                    }
                }
            }
        })
        let owner = RootRouter(engine: engine)
        await owner.current.present(LoginRoute())
        let container = try #require(engine.defaultSpace.rootPath.last)
        let branch = try #require(container.branchScopes["modal"])
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "nl_NL")
        branch.updateSourceEnvironment(environment)
        await owner.current.branch("modal").present(SettingsRoute())
        let sheet = try #require(branch.path.last)
        environment.locale = Locale(identifier: "de_DE")
        sheet.updateSourceEnvironment(environment)
        await owner.current.present(HomeDetailRoute())
        let push = try #require(branch.path.last)
        for scope in [container, sheet, push] { engine.routeScopeDidInstallInView(scope) }
        let sheetBinding = engine.routePresentationBinding(from: branch, matching: .sheet)
        let pushBinding = engine.routePresentationBinding(from: sheet, matching: .push)
        let unwind = Task { await owner.current.unwind(to: .root) }
        for _ in 0..<1000 where !engine.defaultSpace.rootPath.isEmpty { await Task.yield() }
        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(sheetBinding.wrappedValue?.scope === sheet)
        #expect(pushBinding.wrappedValue?.scope === push)
        environment.locale = Locale(identifier: "fr_FR")
        branch.updateSourceEnvironment(environment)
        sheet.updateSourceEnvironment(environment)
        #expect(sheetBinding.wrappedValue?.sourceEnvironment.locale.identifier == "nl_NL")
        #expect(pushBinding.wrappedValue?.sourceEnvironment.locale.identifier == "de_DE")
        sheetBinding.wrappedValue = nil
        pushBinding.wrappedValue = nil
        #expect(engine.navigationOperations.count == 1)
        #expect(!engine.isNavigationEligible(sheet))
        #expect(!engine.isNavigationEligible(push))
        for scope in [container, sheet, push] { engine.routeScopeDidLeaveView(scope) }
        #expect(await unwind.value)
        #expect(sheetBinding.wrappedValue == nil)
        #expect(pushBinding.wrappedValue == nil)
    }

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
        engine.defaultSpace.rootPath.replaceTestPath(scopes)
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
        for _ in 0..<100 where !engine.defaultSpace.rootPath.isEmpty { await Task.yield() }

        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(engine.hasOutgoingPresentations)
        #expect(!engine.pushPresentationDismissalDisablesAnimations(from: engine.root))
        #expect(engine.pushPresentationDismissalDisablesAnimations(from: scopes[0]))
        #expect(engine.pushPresentationDismissalDisablesAnimations(from: scopes[1]))
        for host in hosts {
            #expect(engine.routePresentationBinding(from: host, matching: .push).wrappedValue == nil)
        }

        for scope in scopes { engine.routeScopeDidLeaveView(scope) }
        #expect(await unwind.value)
        #expect(engine.hasOutgoingPresentations == false)
    }

    @Test(arguments: [RoutePriority.default, .high, .critical])
    func equivalentRoutesKeepDepartingModalStacks(priority: RoutePriority) async throws {
        let engine = RouterEngine()
        engine.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, kind: .sheet(priority: priority))._routeDeclarations)]
        )
        await Router(engine: engine, scope: engine.root).present(LoginRoute())
        let space = try #require(engine.spaces.space(for: priority))
        let retained = space.priority == .default ? try #require(space.rootPath.last) : space.root
        let notifications = PolicyNotifications()
        retained.installHookDeclarations(hookDeclarations: [
            UnwindHandler(HomeDetailRoute.self) { notifications.count += 1 }.declaration,
        ])
        retained.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, kind: .sheet(priority: .default))._routeDeclarations)]
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
        for _ in 0..<1000 where space.rootPath.count > (space.priority == .default ? 1 : 0) { await Task.yield() }

        #expect(space.rootPath.scopes.elementsEqual(space.priority == .default ? [retained] : [], by: { $0 === $1 }))
        #expect(engine.hasOutgoingPresentations)
        #expect(engine.routePresentationBinding(from: retained, matching: .sheet).wrappedValue == nil)
        #expect(engine.routePresentationBinding(from: sheet, matching: .push).wrappedValue?.scope === push)
        #expect(notifications.count == 0)

        engine.routeScopeDidLeaveView(sheet)
        engine.routeScopeDidLeaveView(push)
        await request.value
        #expect(space.rootPath.scopes.elementsEqual(space.priority == .default ? [retained] : [], by: { $0 === $1 }))
        #expect(engine.hasOutgoingPresentations == false)
        #expect(notifications.count == 0)
    }
}

@MainActor private final class PolicyNotifications { var count = 0 }
