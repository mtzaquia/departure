import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite struct RouteScopeReadinessTests {
    @Test(arguments: [false, true])
    func destinationWaitEndsWhenItsScopeLeavesTheLiveTree(elevated: Bool) async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(destination(SettingsRoute.self))
        } highPriority: {
            Sheet(destination(LoginRoute.self))
        })
        if elevated { await engine.present(LoginRoute()) }
        else { await engine.present(SettingsRoute()) }
        let scope = engine.currentRouteScope
        var started = false
        let installation = Task {
            started = true
            return await scope.waitUntilInstalled(in: engine)
        }
        for _ in 0..<1000 where !started { await Task.yield() }
        #expect(!scope.isInstalledInView)
        if elevated { #expect(await engine.dismissSpace(engine.spaces.activeSpace)) }
        else { #expect(await engine.unwind(to: .root)) }
        #expect(!(await installation.value))
        // Outgoing references cannot make a removed destination ready again.
        engine.routeScopeDidInstallInView(scope)
        #expect(!(await scope.waitUntilInstalled(in: engine)))
    }

    @Test func coveringADestinationEndsItsInstallationWait() async {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(destination(SettingsRoute.self))
        } highPriority: {
            Sheet(destination(LoginRoute.self))
        })
        await engine.present(SettingsRoute())
        let scope = engine.currentRouteScope
        var started = false
        let installation = Task {
            started = true
            return await scope.waitUntilInstalled(in: engine)
        }
        for _ in 0..<1000 where !started { await Task.yield() }
        await engine.present(LoginRoute())
        #expect(!(await installation.value))
        #expect(engine.spaces.routePath(containing: scope) != nil)
    }

    @Test func cancellingAnInstallationWaitCompletesWithoutAHostEvent() async {
        let engine = RouterEngine()
        var started = false
        let installation = Task {
            started = true
            return await engine.root.waitUntilInstalled(in: engine)
        }
        for _ in 0..<1000 where !started { await Task.yield() }
        installation.cancel()
        #expect(!(await installation.value))
        #expect(!engine.root.isInstalledInView)
        // A fresh wait still observes installation normally.
        let next = Task { await engine.root.waitUntilInstalled(in: engine) }
        engine.routeScopeDidInstallInView(engine.root)
        #expect(await next.value)
    }

    @Test func removedUninstalledDestinationReleasesItsActionRetry() async throws {
        let engine = RouterEngine(routes: RootRouteMap { Push(destination(SettingsRoute.self)) })
        weak var retained: RetryLifetime?
        var retried = false
        func start() async {
            let lifetime = RetryLifetime()
            retained = lifetime
            await engine.performAction(UninstalledRerouteAction(lifetime: lifetime) { retried = true })
        }
        await start()
        for _ in 0..<1000 where engine.defaultSpace.rootPath.isEmpty { await Task.yield() }
        let destination = try #require(engine.defaultSpace.rootPath.last)
        #expect(retained != nil)
        #expect(!destination.isInstalledInView)
        #expect(await engine.unwind(to: .root))
        for _ in 0..<1000 where retained != nil { await Task.yield() }
        #expect(retained == nil)
        engine.routeScopeDidInstallInView(destination)
        #expect(!retried)
    }

    @Test func physicalWaitsObserveBriefHostTransitions() async {
        let scope = RouteScope(id: "host", route: nil)
        let first = UUID(), replacement = UUID()
        var started = false
        let installation = Task {
            started = true
            return await scope.waitUntilInstalled()
        }
        for _ in 0..<1000 where !started { await Task.yield() }
        scope.attachHost(nil, id: first)
        scope.detachHost(id: first)
        #expect(await installation.value)
        #expect(!scope.isInstalledInView)

        scope.attachHost(nil, id: first)
        started = false
        let uninstallation = Task {
            started = true
            return await scope.waitUntilUninstalled()
        }
        for _ in 0..<1000 where !started { await Task.yield() }
        scope.detachHost(id: first)
        scope.attachHost(nil, id: replacement)
        #expect(await uninstallation.value)
        #expect(scope.isInstalledInView)
    }

    private func destination<R: Route>(_ type: R.Type) -> RouteDestination<R> {
        RouteDestination(type) { _, _ in EmptyView() }
    }
}

private final class RetryLifetime {}

private struct UninstalledRerouteAction: Action {
    let lifetime: RetryLifetime
    let didRetry: () -> Void

    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        guard context.isRunning(in: SettingsRoute.self) else { throw .reroute(SettingsRoute()) }
        didRetry()
    }
}
