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
    @Test func payloadHandlerReceivesPayloadWhenChildUnwindsToDeclaringScope() async {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self, expecting: String.self) { payload in
                    recorder.payloads.append(payload)
                }.declaration,
            ]
        )
        router.rootPath.scopes = [parentScope, childScope]

        await router.unwind(payload: "done")

        #expect(recorder.payloads == ["done"])
        #expect(router.rootPath.count == 1)
    }

    @Test func payloadHandlerDoesNotTriggerWhenPayloadTypeMismatches() async {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self, expecting: Int.self) { payload in
                    recorder.ints.append(payload)
                }.declaration,
            ]
        )
        router.rootPath.scopes = [parentScope, childScope]

        await router.unwind(payload: "wrong")

        #expect(recorder.ints.isEmpty)
        #expect(router.rootPath.count == 1)
    }

    @Test func noPayloadHandlerTriggersForExplicitIDTarget() async {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("parent")
                }.declaration,
            ]
        )
        router.rootPath.scopes = [parentScope, childScope]

        await router.unwind(to: .id(RootRoute().id))

        #expect(recorder.events == ["parent"])
        #expect(router.rootPath.count == 1)
    }

    @Test func rootTargetTriggersRootScopeHook() async {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        router.root.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("root")
                }.declaration,
            ]
        )
        router.rootPath.scopes = [parentScope, childScope]

        await router.unwind(to: .root)

        #expect(recorder.events == ["root"])
        #expect(router.rootPath.isEmpty)
    }

    @Test func nearestBranchTriggersContainerHookInsteadOfBranchRootHook() async {
        let router = Router()
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let settingsScope = RouteScope(id: SettingsRoute().id, route: SettingsRoute())
        let recorder = UnwindRecorder()

        router.rootPath.scopes = [landingScope]
        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))
        landingScope.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(SettingsRoute.self) {
                    recorder.events.append("container")
                }.declaration,
            ]
        )
        walletScope.hydrateHooks(
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

        router.rootPath.scopes = [landingScope]
        landingScope.setActiveBranch(AnyHashable(AppTab.wallet))
        landingScope.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(SettingsRoute.self) {
                    recorder.events.append("container")
                }.declaration,
            ]
        )
        walletScope.hydrateHooks(
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

    @Test func handlerRunsAfterDismissedScopeLeavesViewAndCanPresentRoute() async {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let childScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        let recorder = UnwindRecorder()

        parentScope.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ]
        )
        parentScope.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                    recorder.presentationTask = Task {
                        await router.present(SettingsRoute())
                        recorder.events.append("presented")
                    }
                }.declaration,
            ]
        )
        router.rootPath.scopes = [parentScope, childScope]
        router.routeScopeDidInstallInView(childScope)

        let unwindTask = Task {
            await router.unwind()
        }
        await Task.yield()

        #expect(router.rootPath.scopes.count == 1)
        #expect(router.rootPath.scopes.first === parentScope)
        #expect(recorder.events.isEmpty)

        router.routeScopeDidLeaveView(childScope)
        _ = await unwindTask.value
        await recorder.presentationTask?.value

        #expect(recorder.events == ["handler", "presented"])
        #expect(router.rootPath.scopes.count == 2)
        #expect(router.rootPath.scopes.last?.route is SettingsRoute)
    }

    @Test func swiftUIDismissTriggersNoPayloadHandlerAfterDismissedScopeLeavesViewAndCanPresentRoute() async throws {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let recorder = UnwindRecorder()

        parentScope.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(
                    routes: Sheet(LoginRoute.self)._routeDeclarations
                    + Push(SettingsRoute.self)._routeDeclarations
                ),
            ]
        )
        parentScope.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                    recorder.presentationTask = Task {
                        await router.present(SettingsRoute())
                        recorder.events.append("presented")
                    }
                }.declaration,
            ]
        )
        router.rootPath.scopes = [parentScope]

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.rootPath.last)
        router.routeScopeDidInstallInView(dismissedScope)

        router.routePresentationBinding(from: parentScope, matching: .sheet).wrappedValue = nil
        await Task.yield()

        #expect(router.rootPath.scopes.count == 1)
        #expect(router.rootPath.scopes.first === parentScope)
        #expect(recorder.events.isEmpty)

        router.routeScopeDidLeaveView(dismissedScope)
        await recorder.waitForEventCount(2)
        await recorder.presentationTask?.value

        #expect(recorder.events == ["handler", "presented"])
        #expect(router.rootPath.scopes.count == 2)
        #expect(router.rootPath.scopes.last?.route is SettingsRoute)
    }

    @Test func swiftUIDismissTriggersNoPayloadHandlerOnlyOnce() async throws {
        let router = Router()
        let parentScope = RouteScope(id: RootRoute().id, route: RootRoute())
        let recorder = UnwindRecorder()

        parentScope.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(LoginRoute.self)._routeDeclarations),
            ]
        )
        parentScope.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                }.declaration,
            ]
        )
        router.rootPath.scopes = [parentScope]

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.rootPath.last)
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

        parentScope.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(LoginRoute.self)._routeDeclarations),
            ]
        )
        parentScope.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                }.declaration,
            ]
        )
        router.rootPath.scopes = [parentScope]

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.rootPath.last)
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

    @Test func routerUnwindTriggersHandlerForHighPriorityPresentation() async throws {
        let router = Router()
        let recorder = UnwindRecorder()

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ]
        )
        router.root.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                }.declaration,
            ]
        )

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.rootPath.last)
        router.routeScopeDidInstallInView(dismissedScope)

        let unwindTask = Task {
            await router.unwind()
        }
        await Task.yield()

        #expect(router.rootPath.isEmpty)
        #expect(recorder.events.isEmpty)

        router.routeScopeDidLeaveView(dismissedScope)
        _ = await unwindTask.value

        #expect(recorder.events == ["handler"])
    }

    @Test func swiftUIDismissTriggersNoPayloadHandlerForHighPriorityPresentation() async throws {
        let router = Router()
        let recorder = UnwindRecorder()

        router.root.hydrateRoutes(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ]
        )
        router.root.hydrateHooks(
            hookDeclarations: [
                UnwindHandler(LoginRoute.self) {
                    recorder.events.append("handler")
                }.declaration,
            ]
        )

        await router.present(LoginRoute())
        let dismissedScope = try #require(router.rootPath.last)
        router.routeScopeDidInstallInView(dismissedScope)

        router.highPriorityRoutePresentationBinding(matching: .cover(.slide)).wrappedValue = nil
        await Task.yield()

        #expect(router.rootPath.isEmpty)
        #expect(recorder.events.isEmpty)

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
    var presentationTask: Task<Void, Never>?

    func waitForEventCount(_ count: Int) async {
        for _ in 0..<10 where events.count < count {
            await Task.yield()
        }
    }
}
