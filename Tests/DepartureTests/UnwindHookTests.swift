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
    @Test func ancestorHandlerFiresWhenUnwindLandsOnDescendantScope() async {
        let router = Router()
        let recorder = UnwindRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(ChallengeRoute.self, priority: .high)._routeDeclarations
                    + Cover(LockRoute.self, priority: .critical)._routeDeclarations
                ),
            ]
        )
        router.root.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LockRoute.self, expecting: String.self) { payload in
                    recorder.payloads.append(payload)
                }.declaration,
            ]
        )

        await router.present(ChallengeRoute())
        await router.present(LockRoute())

        #expect(router.routeForest.highTree?.rootPath.scopes.count == 1)
        #expect(router.routeForest.highTree?.rootPath.scopes.first?.route is ChallengeRoute)
        #expect(router.routeForest.criticalTree?.rootPath.scopes.count == 1)
        #expect(router.routeForest.criticalTree?.rootPath.scopes.last?.route is LockRoute)

        await router.unwind(to: .topmostAncestor, payload: "unlocked")

        #expect(recorder.payloads == ["unlocked"])
        #expect(router.routeForest.criticalTree == nil)
        #expect(router.routeForest.highTree?.rootPath.scopes.count == 1)
        #expect(router.routeForest.highTree?.rootPath.scopes.last?.route is ChallengeRoute)
    }

    @Test func landedScopeHandlerFiresForLowerDeclaredRoute() async throws {
        let router = Router()
        let recorder = UnwindRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(CardsListRoute.self)._routeDeclarations),
            ]
        )

        await router.present(CardsListRoute())
        let cardsListScope = try #require(router.normalTree.rootPath.last)
        cardsListScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(AddMethodRoute.self)._routeDeclarations),
            ]
        )
        cardsListScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(AddCardRoute.self, expecting: String.self) { payload in
                    recorder.payloads.append(payload)
                }.declaration,
            ]
        )

        await router.present(AddMethodRoute())
        let addMethodScope = try #require(router.normalTree.rootPath.last)
        addMethodScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(AddCardRoute.self)._routeDeclarations),
            ]
        )

        await router.present(AddCardRoute())
        await router.unwind(to: .id(CardsListRoute().id), payload: "card-added")

        #expect(recorder.payloads == ["card-added"])
        #expect(router.normalTree.rootPath.scopes.count == 1)
        #expect(router.normalTree.rootPath.scopes.last === cardsListScope)
    }

    @Test func nearestUnwindHandlerWinsOverFartherAncestor() async throws {
        let router = Router()
        let recorder = UnwindRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(CardsListRoute.self)._routeDeclarations),
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
        let cardsListScope = try #require(router.normalTree.rootPath.last)
        cardsListScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(AddMethodRoute.self)._routeDeclarations),
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
        let addMethodScope = try #require(router.normalTree.rootPath.last)
        addMethodScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(AddCardRoute.self)._routeDeclarations),
            ]
        )

        await router.present(AddCardRoute())
        await router.unwind(to: .id(CardsListRoute().id))

        #expect(recorder.events == ["cards"])
    }

    @Test func siblingBranchUnwindHandlerDoesNotFire() async {
        let router = Router()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let sourceScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let recorder = UnwindRecorder()

        router.normalTree.rootPath.scopes = [landingScope]
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
        homeScope.path.scopes = [sourceScope]
        landingScope.registerBranchScope(homeScope, for: AppTab.home)
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.unwind(to: .topmostAncestor)

        #expect(recorder.events == ["home"])
        #expect(homeScope.path.isEmpty)
    }

    @Test func unwindTargetChangesLandingButNotHandlerLookupRule() async {
        let topmostAncestorEvents = await branchUnwindEvents(to: .topmostAncestor)
        let explicitIDEvents = await branchUnwindEvents(to: .id(AppTab.home))
        let nearestBranchEvents = await branchUnwindEvents(to: .nearestBranch)

        #expect(topmostAncestorEvents == ["container"])
        #expect(explicitIDEvents == ["container"])
        #expect(nearestBranchEvents == ["container"])
    }

    @Test func swiftUIDismissBubblesHandlerFromDescendantLandingToAncestor() async throws {
        let router = Router()
        let recorder = UnwindRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Cover(ChallengeRoute.self, priority: .high)._routeDeclarations
                    + Cover(LockRoute.self, priority: .critical)._routeDeclarations
                ),
            ]
        )
        router.root.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LockRoute.self) {
                    recorder.events.append("root")
                }.declaration,
            ]
        )

        await router.present(ChallengeRoute())
        await router.present(LockRoute())
        let lockScope = try #require(router.routeForest.criticalTree?.rootPath.last)
        router.routeScopeDidInstallInView(lockScope)

        router.elevatedRoutePresentationBinding(priority: .critical, matching: .cover(.slide)).wrappedValue = nil
        await recorder.waitForEventCount(1)

        #expect(recorder.events == ["root"])
        #expect(router.routeForest.criticalTree == nil)
        #expect(router.routeForest.highTree?.rootPath.scopes.count == 1)
        #expect(router.routeForest.highTree?.rootPath.scopes.last?.route is ChallengeRoute)

        router.routeScopeDidLeaveView(lockScope)
    }

    @Test func payloadHandlerReceivesPayloadWhenChildUnwindsToDeclaringScope() async {
        let router = Router()
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
        router.normalTree.rootPath.scopes = [parentScope, childScope]

        await router.unwind(to: .topmostAncestor, payload: "done")

        #expect(recorder.payloads == ["done"])
        #expect(router.normalTree.rootPath.count == 1)
    }

    @Test func payloadHandlerDoesNotTriggerWhenPayloadTypeMismatches() async {
        let router = Router()
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
        router.normalTree.rootPath.scopes = [parentScope, childScope]

        await router.unwind(to: .topmostAncestor, payload: "wrong")

        #expect(recorder.ints.isEmpty)
        #expect(router.normalTree.rootPath.count == 1)
    }

    @Test func noPayloadHandlerTriggersForExplicitIDTarget() async {
        let router = Router()
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
        router.normalTree.rootPath.scopes = [parentScope, childScope]

        await router.unwind(to: .id(RootRoute().id))

        #expect(recorder.events == ["parent"])
        #expect(router.normalTree.rootPath.count == 1)
    }

    @Test func unwindRouteActionStartsFromAssignedScopeWhenItIsNotCurrent() async {
        let router = Router()
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
        router.normalTree.rootPath.scopes = [parentScope, sourceScope, childScope, topScope]

        let didUnwind = await UnwindRouteAction(router: router, routeScope: sourceScope)(payload: "done")
        await waitUntil {
            router.normalTree.rootPath.scopes.count == 1
            && router.normalTree.rootPath.scopes.first === parentScope
        }
        await recorder.waitForEventCount(1)

        #expect(didUnwind)
        #expect(recorder.events == ["parent"])
        #expect(recorder.payloads == ["done"])
        #expect(router.normalTree.rootPath.scopes.count == 1)
        #expect(router.normalTree.rootPath.scopes.first === parentScope)
    }

    @Test func unwindRouteActionClearsPathsOwnedByAssignedScopeWithoutDescendantHandlers() async {
        let router = Router()
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
        router.normalTree.rootPath.scopes = [landingScope]
        settingsScope.path.scopes = [appearanceScope, authenticationScope]
        landingScope.registerBranchScope(settingsScope, for: AppTab.wallet)

        let didUnwind = await UnwindRouteAction(router: router, routeScope: landingScope)()
        await Task.yield()

        #expect(didUnwind)
        #expect(recorder.events.isEmpty)
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(settingsScope.path.isEmpty)
    }

    @Test func inactiveUnwindRouteActionReportsNoRoute() async {
        #expect(await UnwindRouteAction()() == false)
    }

    @Test func unwindRouteActionHasStableIdentityForSameRouterAndScope() {
        let router = Router()
        let scope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let otherScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())

        #expect(UnwindRouteAction(router: router, routeScope: scope) == UnwindRouteAction(router: router, routeScope: scope))
        #expect(UnwindRouteAction(router: router, routeScope: scope) != UnwindRouteAction(router: router, routeScope: otherScope))
        #expect(UnwindRouteAction(router: router, routeScope: scope) != UnwindRouteAction())
    }

    @Test func autoUnwindToEquivalentRouteTriggersTargetScopeHandlerForDismissedRoute() async throws {
        let router = Router()
        let recorder = UnwindRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Push(NumberedRoute.self)._routeDeclarations
                    + Push(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )

        await router.present(NumberedRoute(number: 1))
        let numberedScope = try #require(router.normalTree.rootPath.last)
        numberedScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
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
        #expect(router.normalTree.rootPath.count == 2)

        await router.present(NumberedRoute(number: 1))

        #expect(router.normalTree.rootPath.count == 1)
        #expect(router.normalTree.rootPath.last === numberedScope)
        #expect(recorder.events == ["numbered"])
    }

    @Test func rootTargetTriggersRootScopeHook() async {
        let router = Router()
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
        router.normalTree.rootPath.scopes = [parentScope, childScope]

        await router.unwind(to: .root)

        #expect(recorder.events == ["root"])
        #expect(router.normalTree.rootPath.isEmpty)
    }

    @Test func rootTargetTriggersRootScopeHookForBranchLocalSourceRoute() async {
        let router = Router()
        let (selection, _) = tabSelection(.wallet)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let recorder = UnwindRecorder()

        router.normalTree.rootPath.scopes = [landingScope]
        router.root.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(SettingsRoute.self) {
                    recorder.events.append("root")
                }.declaration,
            ]
        )
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.wallet) {
                        Push(SettingsRoute.self)
                    }
                )
            )
        )
        walletScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.requestRoute(SettingsRoute())
        await router.unwind(to: .root)

        #expect(recorder.events == ["root"])
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(walletScope.path.isEmpty)
    }

    @Test func nearestBranchTriggersContainerHookInsteadOfBranchRootHook() async {
        let router = Router()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let settingsScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let recorder = UnwindRecorder()

        router.normalTree.rootPath.scopes = [landingScope]
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
        walletScope.path.scopes = [settingsScope]
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.unwind(to: .nearestBranch)

        #expect(recorder.events == ["container"])
        #expect(walletScope.path.isEmpty)
    }

    @Test func explicitBranchRootIDTriggersBranchRootHook() async {
        let router = Router()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let settingsScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let recorder = UnwindRecorder()

        router.normalTree.rootPath.scopes = [landingScope]
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
        walletScope.path.scopes = [settingsScope]
        landingScope.registerBranchScope(walletScope, for: AppTab.wallet)

        await router.unwind(to: .id(AppTab.wallet))

        #expect(recorder.events == ["branch-root"])
        #expect(walletScope.path.isEmpty)
    }

    @Test func payloadHandlerRunsWhenUnwindIsAccepted() async {
        let router = Router()
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
        router.normalTree.rootPath.scopes = [parentScope, childScope]

        await router.unwind(to: .topmostAncestor, payload: "done")

        #expect(recorder.payloads == ["done"])
        #expect(recorder.events == ["handler"])
        #expect(router.normalTree.rootPath.count == 1)
    }

    @Test func routerUnwindDoesNotWaitForAsyncHandlerBody() async {
        let router = Router()
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
        router.normalTree.rootPath.scopes = [parentScope, childScope]

        let unwindTask = Task {
            await router.unwind(to: .topmostAncestor)
            recorder.events.append("unwind-returned")
        }
        await recorder.waitForEventCount(1)
        _ = await unwindTask.value

        #expect(recorder.events == ["handler-started", "unwind-returned"])
        #expect(router.normalTree.rootPath.count == 1)

        recorder.release()
        await recorder.waitForEventCount(3)

        #expect(recorder.events == ["handler-started", "unwind-returned", "handler-finished"])
    }

    @Test func handlerCanPresentRouteAfterRouterUnwindFinishes() async {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )
        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                    await router.present(SettingsRoute())
                    recorder.events.append("presented")
                }.declaration,
            ]
        )
        router.normalTree.rootPath.scopes = [parentScope, childScope]
        router.routeScopeDidInstallInView(childScope)

        let unwindTask = Task {
            await router.unwind(to: .topmostAncestor)
        }
        await recorder.waitForEventCount(1)
        await waitUntil {
            router.normalTree.rootPath.scopes.count == 1
            && router.normalTree.rootPath.scopes.first === parentScope
        }

        #expect(router.normalTree.rootPath.scopes.count == 1)
        #expect(router.normalTree.rootPath.scopes.first === parentScope)
        #expect(recorder.events == ["handler"])

        router.routeScopeDidLeaveView(childScope)
        _ = await unwindTask.value
        await recorder.waitForEventCount(2)

        #expect(recorder.events == ["handler", "presented"])
        #expect(router.normalTree.rootPath.scopes.count == 2)
        #expect(router.normalTree.rootPath.scopes.last?.route is SettingsRoute)
    }

    @Test func swiftUIDismissHandlerCanPresentRouteAfterDismissalFinishes() async throws {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let recorder = UnwindRecorder()

        parentScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Sheet(LoginRoute.self)._routeDeclarations
                    + Push(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )
        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                    await router.present(SettingsRoute())
                    recorder.events.append("presented")
                }.declaration,
            ]
        )
        router.normalTree.rootPath.scopes = [parentScope]

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(dismissedScope)

        router.routePresentationBinding(from: parentScope, matching: .sheet).wrappedValue = nil
        await recorder.waitForEventCount(1)

        #expect(router.normalTree.rootPath.scopes.count == 1)
        #expect(router.normalTree.rootPath.scopes.first === parentScope)
        #expect(recorder.events == ["handler"])

        router.routeScopeDidLeaveView(dismissedScope)
        await recorder.waitForEventCount(2)

        #expect(recorder.events == ["handler", "presented"])
        #expect(router.normalTree.rootPath.scopes.count == 2)
        #expect(router.normalTree.rootPath.scopes.last?.route is SettingsRoute)
    }

    @Test func swiftUIDismissTriggersNoPayloadHandlerOnlyOnce() async throws {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let recorder = UnwindRecorder()

        parentScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(LoginRoute.self)._routeDeclarations),
            ]
        )
        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                }.declaration,
            ]
        )
        router.normalTree.rootPath.scopes = [parentScope]

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.normalTree.rootPath.last)
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
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let recorder = UnwindRecorder()

        parentScope.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(LoginRoute.self)._routeDeclarations),
            ]
        )
        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                }.declaration,
            ]
        )
        router.normalTree.rootPath.scopes = [parentScope]

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.normalTree.rootPath.last)
        router.routeScopeDidInstallInView(dismissedScope)

        let unwindTask = Task {
            await router.unwind(to: .id(RootRoute().id))
        }
        await Task.yield()

        router.routePresentationBinding(from: parentScope, matching: .sheet).wrappedValue = nil
        router.routeScopeDidLeaveView(dismissedScope)
        _ = await unwindTask.value
        await recorder.waitForEventCount(1)
        await Task.yield()

        #expect(recorder.events == ["handler"])
    }

    @Test func staleDeliveredUnwindHandlerKeyDoesNotSuppressNewScope() async {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let sourceScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                }.declaration,
            ]
        )

        var staleSourceScope: RouteScope? = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let collidingKey = Router.UnwindHandlerDeliveryKey(
            sourceScopeID: ObjectIdentifier(sourceScope),
            targetScopeID: parentScope.id
        )
        router.deliveredUnwindHandlers[collidingKey] = Router.DeliveredUnwindHandler(
            sourceScope: staleSourceScope
        )
        staleSourceScope = nil

        await router.deliverUnwindHandlers(
            for: sourceScope,
            payload: nil,
            in: parentScope,
            removing: [sourceScope]
        )
        await recorder.waitForEventCount(1)

        #expect(recorder.events == ["handler"])
    }

    @Test func routerUnwindTriggersHandlerForHighPriorityPresentation() async throws {
        let router = Router()
        let recorder = UnwindRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ]
        )
        router.root.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                }.declaration,
            ]
        )

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.routeForest.highTree?.rootPath.last)
        router.routeScopeDidInstallInView(dismissedScope)

        let unwindTask = Task {
            await router.unwind(to: .topmostAncestor)
        }
        await waitUntil {
            router.routeForest.highTree == nil
        }

        #expect(router.routeForest.highTree == nil)
        await recorder.waitForEventCount(1)
        #expect(recorder.events == ["handler"])

        router.routeScopeDidLeaveView(dismissedScope)
        _ = await unwindTask.value

        #expect(recorder.events == ["handler"])
    }

    @Test func swiftUIDismissTriggersNoPayloadHandlerForHighPriorityPresentation() async throws {
        let router = Router()
        let recorder = UnwindRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ]
        )
        router.root.installHookDeclarations(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                }.declaration,
            ]
        )

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.routeForest.highTree?.rootPath.last)
        router.routeScopeDidInstallInView(dismissedScope)

        router.elevatedRoutePresentationBinding(priority: .high, matching: .cover(.slide)).wrappedValue = nil
        await Task.yield()

        #expect(router.routeForest.highTree == nil)
        await recorder.waitForEventCount(1)
        #expect(recorder.events == ["handler"])

        router.routeScopeDidLeaveView(dismissedScope)
        await recorder.waitForEventCount(1)

        #expect(recorder.events == ["handler"])
    }
}

@MainActor
private final class UnwindRecorder {
    var events: [String] = []
    var ints: [Int] = []
    var payloads: [String] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForEventCount(_ count: Int) async {
        for _ in 0..<100 where events.count < count {
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
private func branchUnwindEvents(to target: Router.UnwindTarget) async -> [String] {
    let router = Router()
    let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
    let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
    let sourceScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
    let recorder = UnwindRecorder()

    router.normalTree.rootPath.scopes = [landingScope]
    landingScope.setActiveBranch(AnyHashable(AppTab.home))
    landingScope.installHookDeclarations(
        hookDeclarations: [
            UnwindHandler(SettingsRoute.self) {
                recorder.events.append("container")
            }.declaration,
        ]
    )
    homeScope.path.scopes = [sourceScope]
    landingScope.registerBranchScope(homeScope, for: AppTab.home)

    await router.unwind(to: target)
    return recorder.events
}

@MainActor
private func waitUntil(_ predicate: () -> Bool) async {
    for _ in 0..<100 where predicate() == false {
        await Task.yield()
    }
}
