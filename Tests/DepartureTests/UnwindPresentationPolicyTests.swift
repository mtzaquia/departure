import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct UnwindPresentationPolicyTests {


    @Test func outgoingBranchBindingsKeepTheirCapturedEnvironmentWithoutRoutingAuthority() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            testPush(testDestination(LoginRoute.self)) {
                Branches(concurrent: true) {
                    Branch("modal") {
                        testSheet(testDestination(SettingsRoute.self)) {
                            testPush(testDestination(HomeDetailRoute.self))
                        }
                    }
                }
            }
        })
        let owner = RootRouter(engine: engine)
        await owner.current.present(LoginRoute())
        let container = try #require(engine.tree.rootPath.last)
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
        let unwind = Task { await owner.current.resetToRoot() }
        for _ in 0..<1000 where !engine.tree.rootPath.isEmpty { await Task.yield() }
        #expect(engine.tree.rootPath.isEmpty)
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
        case routeType
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
                definitions: [RouteScopeDeclaration(routes: testDeclaration(testDestination(NumberedRoute.self), presentation: .init(style: .push))._routeDeclarations)]
            )
            scope.attachPresentation(to: host, declaration: try #require(host.routeAttachments.first))
            engine.routeScopeDidInstallInView(scope)
        }
        engine.tree.rootPath.replaceTestPath(scopes)
        let router = Router(engine: engine, scope: scopes[0])
        let unwind = Task {
            switch jump {
            case .ancestor:
                await router.unwind(.current)
            case .routeType:
                await router.unwind(from: NumberedRoute.self)
            case .capturedAction:
                await UnwindRouteAction(router: engine, routeScope: scopes[0])()
            }
        }
        for _ in 0..<100 where !engine.tree.rootPath.isEmpty { await Task.yield() }

        #expect(engine.tree.rootPath.isEmpty)
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


}

@MainActor private final class PolicyNotifications { var count = 0 }
