//
//  Copyright (c) 2026 @mtzaquia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import SwiftUI
//
//  Copyright (c) 2026 @mtzaquia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Testing
@testable import Departure

@MainActor
@Suite
struct UnwindHookTests {
    @Test(arguments: [UnwindSource.explicit, .native, .repeatedNative, .repeatedExplicit])
    func nativeAndExplicitUnwindsEnterHandlerBeforeCommitAndDeferPresentation(native: UnwindSource) async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            testSheet(testDestination(LoginRoute.self))
            testPush(testDestination(SettingsRoute.self))
        })
        let root = Router(engine: engine, scope: engine.root)
        await root.present(LoginRoute())
        let source = try #require(engine.tree.rootPath.last)
        engine.routeScopeDidInstallInView(source)
        let recorder = UnwindRecorder()
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LoginRoute.self) {
                #expect(engine.tree.routePath(containing: source) != nil)
                #expect(engine.tree.rootPath.last === source)
                #expect(engine.isNavigating)
                recorder.events.append("handler")
                await root.present(SettingsRoute())
                recorder.events.append("presented")
            }.declaration,
        ])

        let unwind = Task {
            if native == .native || native == .repeatedNative {
                let binding = engine.routePresentationBinding(from: engine.root, matching: .sheet)
                binding.wrappedValue = nil
                if native == .repeatedNative { binding.wrappedValue = nil }
            } else if native == .repeatedExplicit {
                let scoped = Router(engine: engine, scope: source)
                async let first = scoped.unwind(.current)
                async let second = scoped.unwind(.current)
                let results = await (first, second)
                #expect(results.0 || results.1)
            } else {
                #expect(await Router(engine: engine, scope: source).unwind(.current))
            }
        }
        await waitUntil { engine.tree.rootPath.isEmpty && recorder.events == ["handler"] }
        #expect(engine.tree.rootPath.isEmpty)
        #expect(recorder.events == ["handler"])
        #expect(engine.isNavigating)
        #expect(engine.pendingRoute != nil)

        engine.routeScopeDidLeaveView(source)
        await unwind.value
        await recorder.waitForEventCount(2)
        #expect(recorder.events == ["handler", "presented"])
        #expect(engine.tree.rootPath.last?.route is SettingsRoute)
    }

    @Test func landedScopeHandlerFiresForDismissedFlow() async throws {
        let router = RouterEngine()
        let recorder = UnwindRecorder()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(CardsListRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )

        await router.present(CardsListRoute())
        let cardsListScope = try #require(router.tree.rootPath.last)
        cardsListScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(AddMethodRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        cardsListScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(AddMethodRoute.self, expecting: String.self) { payload in
                    recorder.payloads.append(payload)
                }.declaration,
            ]
        )

        await router.present(AddMethodRoute())
        let addMethodScope = try #require(router.tree.rootPath.last)
        addMethodScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(AddCardRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations),
            ]
        )

        await router.present(AddCardRoute())
        await Router(engine: router).unwind(from: AddMethodRoute.self, payload: "card-added")

        #expect(recorder.payloads == ["card-added"])
        #expect(router.tree.rootPath.scopes.count == 1)
        #expect(router.tree.rootPath.scopes.last === cardsListScope)
    }

    @Test func nearestUnwindHandlerWinsOverFartherAncestor() async throws {
        let router = RouterEngine()
        let recorder = UnwindRecorder()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(CardsListRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        router.root.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(AddCardRoute.self) {
                    recorder.events.append("root")
                }.declaration,
            ]
        )

        await router.present(CardsListRoute())
        let cardsListScope = try #require(router.tree.rootPath.last)
        cardsListScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(AddMethodRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        cardsListScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(AddCardRoute.self) {
                    recorder.events.append("cards")
                }.declaration,
            ]
        )

        await router.present(AddMethodRoute())
        let addMethodScope = try #require(router.tree.rootPath.last)
        addMethodScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(AddCardRoute.self), presentation: .init(style: .cover(.slide)))._routeDeclarations),
            ]
        )

        await router.present(AddCardRoute())
        await Router(engine: router).unwind(from: AddCardRoute.self)

        #expect(recorder.events == ["cards"])
    }

    @Test func siblingBranchUnwindHandlerDoesNotFire() async {
        let router = RouterEngine()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let sourceScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let recorder = UnwindRecorder()

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.setActiveBranch(AnyHashable(AppTab.home))
        landingScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(SettingsRoute.self) {
                    recorder.events.append("ancestor")
                }.declaration,
            ]
        )
        homeScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(SettingsRoute.self) {
                    recorder.events.append("home")
                }.declaration,
            ]
        )
        walletScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(SettingsRoute.self) {
                    recorder.events.append("wallet")
                }.declaration,
            ]
        )
        homeScope.path.replaceTestPath([sourceScope])
        landingScope.attachTestBranch(homeScope, for: AppTab.home)
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.unwind(.current)

        #expect(recorder.events == ["home"])
        #expect(homeScope.path.isEmpty)
    }

    @Test func currentAndRouteTypeUnwindsReachContainerHook() async {
        #expect(await branchUnwindEvents(useRouteType: false) == ["container"])
        #expect(await branchUnwindEvents(useRouteType: true) == ["container"])
    }

    @Test func payloadHandlerReceivesPayloadWhenChildUnwindsToDeclaringScope() async {
        let router = RouterEngine()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self, expecting: String.self) { payload in
                    recorder.payloads.append(payload)
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([parentScope, childScope])

        await router.unwind(.current, payload: "done")

        #expect(recorder.payloads == ["done"])
        #expect(router.tree.rootPath.count == 1)
    }

    @Test func payloadHandlerDoesNotTriggerWhenPayloadTypeMismatches() async {
        let router = RouterEngine()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self, expecting: Int.self) { payload in
                    recorder.ints.append(payload)
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([parentScope, childScope])

        await router.unwind(.current, payload: "wrong")

        #expect(recorder.ints.isEmpty)
        #expect(router.tree.rootPath.count == 1)
    }

    @Test func noPayloadHandlerTriggersForRouteTypeTarget() async {
        let router = RouterEngine()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("parent")
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([parentScope, childScope])

        await Router(engine: router).unwind(from: LoginRoute.self)

        #expect(recorder.events == ["parent"])
        #expect(router.tree.rootPath.count == 1)
    }

    @Test func unwindRouteActionStartsFromAssignedScopeWhenItIsNotCurrent() async {
        let router = RouterEngine()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let sourceScope = RouteScope(id: CardsListRoute().id, route: CardsListRoute())
        let childScope = RouteScope(id: AddMethodRoute().id, route: AddMethodRoute())
        let topScope = RouteScope(id: AddCardRoute().id, route: AddCardRoute())
        let recorder = UnwindRecorder()

        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(CardsListRoute.self, expecting: String.self) { payload in
                    recorder.payloads.append(payload)
                    recorder.events.append("parent")
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([parentScope, sourceScope, childScope, topScope])

        let didUnwind = await UnwindRouteAction(router: router, routeScope: sourceScope)(payload: "done")
        await waitUntil {
            router.tree.rootPath.scopes.count == 1
            && router.tree.rootPath.scopes.first === parentScope
        }
        await recorder.waitForEventCount(1)

        #expect(didUnwind)
        #expect(recorder.events == ["parent"])
        #expect(recorder.payloads == ["done"])
        #expect(router.tree.rootPath.scopes.count == 1)
        #expect(router.tree.rootPath.scopes.first === parentScope)
    }

    @Test func unwindRouteActionClearsPathsOwnedByAssignedScopeWithoutDescendantHandlers() async {
        let router = RouterEngine()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let settingsScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let appearanceScope = RouteScope(id: AddMethodRoute().id, route: AddMethodRoute())
        let authenticationScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))
        landingScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("landing")
                }.declaration,
            ]
        )
        settingsScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("settings")
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([landingScope])
        settingsScope.path.replaceTestPath([appearanceScope, authenticationScope])
        landingScope.attachTestBranch(settingsScope, for: AppTab.wallet)

        let didUnwind = await UnwindRouteAction(router: router, routeScope: landingScope)()
        await Task.yield()

        #expect(didUnwind)
        #expect(recorder.events.isEmpty)
        #expect(router.tree.rootPath.isEmpty)
        #expect(router.tree.routePath(containing: settingsScope) == nil)
    }

    @Test func inactiveUnwindRouteActionReportsNoRoute() async {
        #expect(await UnwindRouteAction()() == false)
    }

    @Test func unwindRouteActionDoesNotRetainItsAssignedScope() async {
        let router = RouterEngine()
        weak var releasedScope: RouteScope?
        let action = {
            let scope = RouteScope(id: LoginRoute().id, route: LoginRoute())
            releasedScope = scope
            return UnwindRouteAction(router: router, routeScope: scope)
        }()

        #expect(releasedScope == nil)
        #expect(await action() == false)
    }

    @Test func unwindRouteActionHasStableIdentityForSameRouterAndScope() {
        let router = RouterEngine()
        let scope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let otherScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())

        #expect(UnwindRouteAction(router: router, routeScope: scope) == UnwindRouteAction(router: router, routeScope: scope))
        #expect(UnwindRouteAction(router: router, routeScope: scope) != UnwindRouteAction(router: router, routeScope: otherScope))
        #expect(UnwindRouteAction(router: router, routeScope: scope) != UnwindRouteAction())
    }

    @Test func presentationReuseDoesNotTriggerTargetScopeHandlerForDismissedRoute() async throws {
        let router = RouterEngine()
        let recorder = UnwindRecorder()

        router.root.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(NumberedRoute.self), presentation: .init(style: .push))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )

        await router.present(NumberedRoute(number: 1))
        let numberedScope = try #require(router.tree.rootPath.last)
        numberedScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        numberedScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(SettingsRoute.self) {
                    recorder.events.append("numbered")
                }.declaration,
            ]
        )

        await router.present(SettingsRoute())
        #expect(router.tree.rootPath.count == 2)

        await router.present(NumberedRoute(number: 1))

        #expect(router.tree.rootPath.count == 1)
        #expect(router.tree.rootPath.last === numberedScope)
        #expect(recorder.events.isEmpty)

        await router.present(SettingsRoute())
        #expect(await router.unwind(.current))
        #expect(recorder.events == ["numbered"])
    }

    @Test func rootTargetTriggersRootScopeHook() async {
        let router = RouterEngine()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        router.root.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("root")
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([parentScope, childScope])

        await router.resetToRoot()

        #expect(recorder.events == ["root"])
        #expect(router.tree.rootPath.isEmpty)
    }

    @Test func rootTargetTriggersRootScopeHookForBranchLocalSourceRoute() async {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let recorder = UnwindRecorder()

        router.tree.rootPath.replaceTestPath([landingScope])
        router.root.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(SettingsRoute.self) {
                    recorder.events.append("root")
                }.declaration,
            ]
        )
        landingScope.defineTestMap(
            id: RootRoute().id,
            selection: AnyRouteBranchSelection(selection),
            definitions: RouteDeclarationBuilder.buildBlock(
                BranchDeclarationBuilder.buildExpression(
                    Branch(AppTab.wallet) {
                        testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))
                    }
                )
            )
        )
        walletScope.defineTestMap(
            id: AnyHashable(AppTab.wallet),
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())
        await router.resetToRoot()

        #expect(recorder.events == ["root"])
        #expect(router.tree.rootPath.isEmpty)
        #expect(router.tree.routePath(containing: walletScope) == nil)
    }

    @Test func routeTypeUnwindTriggersBranchRootHook() async {
        let router = RouterEngine()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let settingsScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let recorder = UnwindRecorder()

        router.tree.rootPath.replaceTestPath([landingScope])
        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))
        landingScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(SettingsRoute.self) {
                    recorder.events.append("container")
                }.declaration,
            ]
        )
        walletScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(SettingsRoute.self) {
                    recorder.events.append("branch-root")
                }.declaration,
            ]
        )
        walletScope.path.replaceTestPath([settingsScope])
        landingScope.attachTestBranch(walletScope, for: AppTab.wallet)

        await Router(engine: router).unwind(from: SettingsRoute.self)

        #expect(recorder.events == ["branch-root"])
        #expect(walletScope.path.isEmpty)
    }

    @Test func payloadHandlerRunsWhenUnwindIsAccepted() async {
        let router = RouterEngine()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self, expecting: String.self) { payload in
                    recorder.payloads.append(payload)
                    recorder.events.append("handler")
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([parentScope, childScope])

        await router.unwind(.current, payload: "done")

        #expect(recorder.payloads == ["done"])
        #expect(recorder.events == ["handler"])
        #expect(router.tree.rootPath.count == 1)
    }

    @Test func routerUnwindDoesNotWaitForAsyncHandlerBody() async {
        let router = RouterEngine()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler-started")
                    await recorder.waitForRelease()
                    recorder.events.append("handler-finished")
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([parentScope, childScope])

        let unwindTask = Task {
            await router.unwind(.current)
            recorder.events.append("unwind-returned")
        }
        await recorder.waitForEventCount(1)
        _ = await unwindTask.value

        #expect(recorder.events == ["handler-started", "unwind-returned"])
        #expect(router.tree.rootPath.count == 1)

        recorder.release()
        await recorder.waitForEventCount(3)

        #expect(recorder.events == ["handler-started", "unwind-returned", "handler-finished"])
    }

    @Test func handlerCanPresentRouteAfterRouterUnwindFinishes() async {
        let router = RouterEngine()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                    await Router(engine: router, scope: parentScope).present(SettingsRoute())
                    recorder.events.append("presented")
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([parentScope, childScope])
        router.routeScopeDidInstallInView(childScope)

        let unwindTask = Task {
            await router.unwind(.current)
        }
        await recorder.waitForEventCount(1)
        await waitUntil {
            router.tree.rootPath.scopes.count == 1
            && router.tree.rootPath.scopes.first === parentScope
        }

        #expect(router.tree.rootPath.scopes.count == 1)
        #expect(router.tree.rootPath.scopes.first === parentScope)
        #expect(recorder.events == ["handler"])

        router.routeScopeDidLeaveView(childScope)
        _ = await unwindTask.value
        await recorder.waitForEventCount(2)

        #expect(recorder.events == ["handler", "presented"])
        #expect(router.tree.rootPath.scopes.count == 2)
        #expect(router.tree.rootPath.scopes.last?.route is SettingsRoute)
    }

    @Test func swiftUIDismissHandlerCanPresentRouteAfterDismissalFinishes() async throws {
        let router = RouterEngine()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let recorder = UnwindRecorder()

        parentScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations
                    + testDeclaration(testDestination(SettingsRoute.self), presentation: .init(style: .push))._routeDeclarations),
            ]
        )
        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                    await Router(engine: router, scope: parentScope).present(SettingsRoute())
                    recorder.events.append("presented")
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([parentScope])

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.tree.rootPath.last)
        router.routeScopeDidInstallInView(dismissedScope)

        router.routePresentationBinding(from: parentScope, matching: .sheet).wrappedValue = nil
        await recorder.waitForEventCount(1)
        await waitUntil { router.tree.rootPath.scopes.count == 1 }

        #expect(router.tree.rootPath.scopes.count == 1)
        #expect(router.tree.rootPath.scopes.first === parentScope)
        #expect(recorder.events == ["handler"])

        router.routeScopeDidLeaveView(dismissedScope)
        await recorder.waitForEventCount(2)

        #expect(recorder.events == ["handler", "presented"])
        #expect(router.tree.rootPath.scopes.count == 2)
        #expect(router.tree.rootPath.scopes.last?.route is SettingsRoute)
    }

    @Test func swiftUIDismissTriggersNoPayloadHandlerOnlyOnce() async throws {
        let router = RouterEngine()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let recorder = UnwindRecorder()

        parentScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([parentScope])

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.tree.rootPath.last)
        router.routeScopeDidInstallInView(dismissedScope)

        let binding = router.routePresentationBinding(from: parentScope, matching: .sheet)
        binding.wrappedValue = nil
        binding.wrappedValue = nil
        router.routeScopeDidLeaveView(dismissedScope)
        await recorder.waitForEventCount(1)
        await Task.yield()

        #expect(recorder.events == ["handler"])
    }

    @Test func routerUnwindTriggersNoPayloadHandlerOnlyOnceWhenPresentationBindingAlsoDismisses() async throws {
        let router = RouterEngine()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let recorder = UnwindRecorder()

        parentScope.defineTestMap(
            id: nil,
            selection: nil,
            definitions: [
                RouteScopeDeclaration(routes: testDeclaration(testDestination(LoginRoute.self), presentation: .init(style: .sheet))._routeDeclarations),
            ]
        )
        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                }.declaration,
            ]
        )
        router.tree.rootPath.replaceTestPath([parentScope])

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.tree.rootPath.last)
        router.routeScopeDidInstallInView(dismissedScope)

        let unwindTask = Task {
            await Router(engine: router).unwind(from: LoginRoute.self)
        }
        await Task.yield()

        router.routePresentationBinding(from: parentScope, matching: .sheet).wrappedValue = nil
        router.routeScopeDidLeaveView(dismissedScope)
        _ = await unwindTask.value
        await recorder.waitForEventCount(1)
        await Task.yield()

        #expect(recorder.events == ["handler"])
    }

    @Test func repeatedRouteInstancesDeliverIndependently() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            testSheet(testDestination(LoginRoute.self))
        }, router: owner) { EmptyView() }
        let recorder = UnwindRecorder()
        owner.engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LoginRoute.self) { recorder.events.append("handler") }.declaration,
        ])
        await owner.root.present(LoginRoute())
        let first = try #require(owner.engine.tree.rootPath.last)
        #expect(await owner.current.unwind(.current))
        await recorder.waitForEventCount(1)
        #expect(recorder.events == ["handler"])

        // Retain the outgoing instance while the same domain route is presented again.
        await owner.root.present(LoginRoute())
        let second = try #require(owner.engine.tree.rootPath.last)
        #expect(first !== second)
        #expect(first.id == second.id)
        #expect(await owner.current.unwind(.current))
        await recorder.waitForEventCount(2)
        #expect(recorder.events == ["handler", "handler"])
    }

}

enum UnwindSource: Sendable { case explicit, native, repeatedNative, repeatedExplicit }

@MainActor
private final class UnwindRecorder {
    var events: [String] = []
    var ints: [Int] = []
    var payloads: [String] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForEventCount(_ count: Int) async {
        for _ in 0..<1000 where events.count < count {
            await Task.yield()
        }
    }

    func waitForRelease() async {
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private func branchUnwindEvents(useRouteType: Bool) async -> [String] {
    let router = RouterEngine()
    let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
    let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
    let sourceScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
    let recorder = UnwindRecorder()

    router.tree.rootPath.replaceTestPath([landingScope])
    landingScope.setActiveBranch(AnyHashable(AppTab.home))
    landingScope.installHookDeclarations(
        hookDeclarations: [
            UnwindHandler(SettingsRoute.self) {
                recorder.events.append("container")
            }.declaration,
        ]
    )
    homeScope.path.replaceTestPath([sourceScope])
    landingScope.attachTestBranch(homeScope, for: AppTab.home)

    if useRouteType { await Router(engine: router).unwind(from: SettingsRoute.self) }
    else { await router.unwind(.current) }
    return recorder.events
}

@MainActor
private func waitUntil(_ predicate: () -> Bool) async {
    for _ in 0..<100 where predicate() == false {
        await Task.yield()
    }
}
