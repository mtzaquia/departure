import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite struct RouteScopeHostTests {
    @Test func nativeTeardownDoesNotRemoveDefinitions() {
        let engine = RouterEngine(routes: RootRouteMap { Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }) })
        engine.routeScopeDidInstallInView(engine.root)
        engine.routeScopeDidLeaveView(engine.root)
        #expect(engine.root.definitions.routeBinding(for: HomeDetailRoute.self) != nil)
        #expect(!engine.root.isInstalledInView)
    }
    @Test func environmentUpdatesDoNotReplaceDefinitions() {
        let engine = RouterEngine(routes: RootRouteMap { Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() }) })
        let identity = engine.root.routeAttachments.map(\.identity)
        var environment = EnvironmentValues(); environment.locale = Locale(identifier: "nl_NL")
        engine.root.updateSourceEnvironment(environment)
        #expect(engine.root.routeAttachments.map(\.identity) == identity)
        #expect(engine.root.sourceEnvironment.locale.identifier == "nl_NL")
    }
    @Test func hookSourcesComposeAndDetachIndependently() {
        let engine = RouterEngine()
        let scope = engine.root
        let action = HookDeclarationIdentity.actionInterceptor(ObjectIdentifier(ContextProbeAction.self))
        let unwind = HookDeclarationIdentity.unwindHandler(ObjectIdentifier(SettingsRoute.self))
        scope.installHookDeclarations(sourceID: "first", hookDeclarations: [ActionInterceptor(ContextProbeAction.self) { _ in }.declaration])
        scope.installHookDeclarations(sourceID: "second", hookDeclarations: [UnwindHandler(SettingsRoute.self) {}.declaration])
        #expect(scope.hookBinding(for: action, in: engine.spaces) != nil)
        #expect(scope.hookBinding(for: unwind, in: engine.spaces) != nil)
        scope.uninstallHookDeclarations(sourceID: "second")
        #expect(scope.hookBinding(for: action, in: engine.spaces) != nil)
        #expect(scope.hookBinding(for: unwind, in: engine.spaces) == nil)
        scope.uninstallHookDeclarations(sourceID: "first")
        #expect(scope.hookBinding(for: action, in: engine.spaces) == nil)
    }
    @Test func branchScopeIdentitySurvivesNativeTeardown() throws {
        let engine = RouterEngine(routes: RootRouteMap { Branches { Branch("tab") { Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }) } } })
        let branch = try #require(engine.root.branchScopes["tab"])
        engine.routeScopeDidInstallInView(branch)
        engine.routeScopeDidLeaveView(branch)
        #expect(engine.root.branchScopes["tab"] === branch)
        #expect(branch.definitions.routeBinding(for: HomeDetailRoute.self) != nil)
    }
    @Test func staleManagedViewTeardownKeepsReplacement() {
        let scope = RouteScope(id: "root", route: nil)
        let first = UUID(), second = UUID()
        let view = PlatformView()
        scope.attachHost(view, id: first)
        scope.attachHost(view, id: second)
        scope.detachHost(id: first)
        #expect(scope.hostID == second)
        #expect(scope.isInstalledInView)
        // Live hooks retain the native ownership gate.
        #expect(scope.ownership(of: view) == .pending)
    }

    @Test func staleElevatedHostDetachmentCannotClearItsReplacement() async throws {
        let engine = RouterEngine(routes: RootRouteMap {} highPriority: {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() })
        })
        await engine.present(LoginRoute())
        let space = try #require(engine.spaces.highSpace)
        let scope = space.root
        let first = UUID(), replacement = UUID()
        engine.hostDidAttach(scope, view: nil, id: first)
        engine.hostDidAttach(scope, view: nil, id: replacement)
        engine.hostDidDetach(scope, id: first)
        #expect(scope.hostID == replacement)
        #expect(scope.isInstalledInView)
        #expect(engine.spaces.highSpace === space)
        engine.hostDidDetach(scope, id: replacement)
        #expect(!scope.isInstalledInView)
        #expect(engine.spaces.highSpace === space)
        engine.hostDidDetach(scope, id: replacement)
        #expect(engine.spaces.highSpace === space)
    }

    @Test func nativeOwnerDismissalRemovesItsEntireOwnedTreeWhileCovered() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() })
        } highPriority: {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
                Branches(concurrent: true) {
                    Branch("first") {
                        Push(RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }) {
                            Sheet(RouteDestination(MessageRoute.self) { _, _ in EmptyView() })
                        }
                    }
                    Branch("second") { Push(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() }) }
                }
            }
        } criticalPriority: {
            Cover(RouteDestination(AlertRoute.self) { _, _ in EmptyView() })
        })
        await engine.present(HomeDetailRoute())
        let defaultDestination = try #require(engine.defaultSpace.rootPath.last)
        await engine.present(LoginRoute())
        let high = try #require(engine.spaces.highSpace)
        let highRouter = Router(engine: engine, scope: high.root)
        await highRouter.branch("first").present(NumberedRoute(number: 1))
        await highRouter.branch("second").present(SettingsRoute())
        let first = try #require(high.root.branchScopes["first"])
        let second = try #require(high.root.branchScopes["second"])
        let pushed = try #require(first.path.last)
        await Router(engine: engine, scope: pushed).present(MessageRoute())
        let modal = try #require(first.path.last)
        // A request from high uses the owner's critical catalog, not high's tree.
        await highRouter.present(AlertRoute())
        let critical = try #require(engine.spaces.criticalSpace)
        let host = UUID()
        engine.hostDidAttach(high.root, view: nil, id: host)
        engine.hostDidDetach(high.root, id: host)
        #expect(engine.spaces.highSpace === high)
        engine.nativePresentationDidDismiss(high.root)
        #expect(engine.spaces.highSpace == nil)
        #expect(engine.spaces.criticalSpace === critical)
        #expect(engine.defaultSpace.rootPath.last === defaultDestination)
        for removed in [high.root, first, second, pushed, modal] {
            #expect(engine.spaces.routePath(containing: removed) == nil)
        }
        // Retained outgoing objects keep their owned tree without routing authority.
        #expect(first.path.last === modal)
        #expect(second.path.last?.route is SettingsRoute)
    }

    @Test func canonicalHostEventsCompleteReadinessWaitersOnce() async {
        let engine = RouterEngine()
        let scope = engine.root
        let first = UUID(), replacement = UUID()
        var installed = 0, uninstalled = 0
        let installation = Task { await scope.waitUntilInstalled(); installed += 1 }
        await Task.yield()
        engine.hostDidAttach(scope, view: nil, id: first)
        engine.hostDidAttach(scope, view: nil, id: first)
        await installation.value
        #expect(installed == 1)
        let uninstallation = Task { await scope.waitUntilUninstalled(); uninstalled += 1 }
        await Task.yield()
        engine.hostDidAttach(scope, view: nil, id: replacement)
        engine.hostDidDetach(scope, id: first)
        await Task.yield()
        #expect(uninstalled == 0)
        #expect(scope.isInstalledInView)
        engine.hostDidDetach(scope, id: replacement)
        engine.hostDidDetach(scope, id: replacement)
        await uninstallation.value
        #expect(uninstalled == 1)
        #expect(scope.hasEverInstalled)
    }
}
