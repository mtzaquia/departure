import SwiftUI
import Testing
@testable import Departure

@MainActor
struct RouteScopeLedgerTests {
    @Test func newerRouteSourceReplacesOlderAndRestoresItOnTeardown() {
        let scope = RouteScope(id: "root", route: nil)
        let first = AnyHashable("first")
        let second = AnyHashable("second")
        var firstEnvironment = EnvironmentValues()
        firstEnvironment.locale = Locale(identifier: "nl_NL")
        var secondEnvironment = EnvironmentValues()
        secondEnvironment.locale = Locale(identifier: "fr_FR")

        scope.installRouteDeclarations(sourceID: first, id: "first-id", branchSelection: nil,
            routeDeclarations: [RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations)],
            sourceEnvironment: firstEnvironment)
        scope.installRouteDeclarations(sourceID: second, id: "second-id", branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
                RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations),
            ], sourceEnvironment: secondEnvironment)

        #expect(scope.id == AnyHashable("second-id"))
        #expect(scope.sourceEnvironment.locale.identifier == "fr_FR")
        #expect(scope.firstRouteAttachment(for: SettingsRoute.self)?.declaration.presentationKind == .push)
        #expect(scope.firstRouteAttachment(for: HomeDetailRoute.self) != nil)

        scope.uninstallRouteDeclarations(sourceID: second)
        #expect(scope.id == AnyHashable("first-id"))
        #expect(scope.sourceEnvironment.locale.identifier == "nl_NL")
        #expect(scope.firstRouteAttachment(for: SettingsRoute.self)?.declaration.presentationKind == .sheet)
        #expect(scope.firstRouteAttachment(for: HomeDetailRoute.self) == nil)

        scope.uninstallRouteDeclarations(sourceID: first)
        #expect(scope.id == AnyHashable("root"))
        #expect(scope.firstRouteAttachment(for: SettingsRoute.self) == nil)
    }

    @Test func routeRemovalPreservesIndependentHooksAndBranchEnvironment() {
        let scope = RouteScope(id: "branch", route: nil)
        var base = EnvironmentValues()
        base.locale = Locale(identifier: "nl_NL")
        scope.updateSourceEnvironment(base)
        scope.installHookDeclarations(sourceID: "hooks", hookDeclarations: [
            ActionInterceptor(ContextProbeAction.self) { _ in }.declaration,
        ])

        var routeEnvironment = EnvironmentValues()
        routeEnvironment.locale = Locale(identifier: "fr_FR")
        scope.installRouteDeclarations(sourceID: "routes", id: nil, branchSelection: nil,
            routeDeclarations: [RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations)],
            sourceEnvironment: routeEnvironment)
        #expect(scope.sourceEnvironment.locale.identifier == "fr_FR")
        #expect(scope.hookAttachments.count == 1)

        scope.uninstallRouteDeclarations(sourceID: "routes")
        #expect(scope.sourceEnvironment.locale.identifier == "nl_NL")
        #expect(scope.hookAttachments.count == 1)

        scope.uninstallHookDeclarations(sourceID: "hooks")
        #expect(scope.hookAttachments.isEmpty)
    }

    @Test func newerHookSourceReplacesOlderAndRestoresItOnTeardown() {
        let scope = RouteScope(id: "root", route: nil)
        scope.installHookDeclarations(sourceID: "first", hookDeclarations: [
            ActionInterceptor(ContextProbeAction.self) { _ in }.declaration,
        ])
        scope.installHookDeclarations(sourceID: "second", hookDeclarations: [
            UnwindHandler(SettingsRoute.self) {}.declaration,
        ])

        #expect(scope.hookAttachments.count == 1)
        #expect(scope.hookAttachments.first?.identity == .unwindHandler(ObjectIdentifier(SettingsRoute.self)))
        scope.uninstallHookDeclarations(sourceID: "second")
        #expect(scope.hookAttachments.count == 1)
        #expect(scope.hookAttachments.first?.identity == .actionInterceptor(ObjectIdentifier(ContextProbeAction.self)))
        scope.uninstallHookDeclarations(sourceID: "first")
        #expect(scope.hookAttachments.isEmpty)
    }

    @Test func newerBranchHostReplacesOlderAndRestoresItOnTeardown() {
        let parent = RouteScope(id: "parent", route: nil)
        let first = RouteScope(id: "first", route: nil)
        let second = RouteScope(id: "second", route: nil)

        #expect(parent.registerBranchScope(first, for: "tab"))
        #expect(parent.registerBranchScope(second, for: "tab"))
        #expect(parent.branchScopes["tab"] === second)
        #expect(first.participation.isBranchHostRegistered == false)
        #expect(second.participation.isBranchHostRegistered)

        parent.unregisterBranchScope(second, for: "tab")
        #expect(parent.branchScopes["tab"] === first)
        #expect(second.parent == nil)
        #expect(second.participation.isBranchHostRegistered == false)
        #expect(first.parent === parent)
        #expect(first.participation.isBranchHostRegistered)

        parent.unregisterBranchScope(first, for: "tab")
        #expect(parent.branchScopes["tab"] == nil)
        #expect(first.parent == nil)
        #expect(first.participation.isBranchHostRegistered == false)
    }

    @Test func branchHostRekeyDoesNotLeaveAnOldRegistrationBehind() {
        let parent = RouteScope(id: "parent", route: nil)
        let branch = RouteScope(id: "branch", route: nil)

        #expect(parent.registerBranchScope(branch, for: "first"))
        #expect(parent.registerBranchScope(branch, for: "second"))
        #expect(parent.branchScopes["first"] == nil)
        #expect(parent.branchScopes["second"] === branch)
        #expect(branch.branchID == AnyHashable("second"))
    }
}
