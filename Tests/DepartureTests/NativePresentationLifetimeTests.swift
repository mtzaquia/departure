import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite(.timeLimit(.minutes(1)))
struct NativePresentationLifetimeTests {


    @Test func unadmittedSuccessorIsPreparedInTheSameSynchronization() {
        let first = PresentedRoute(scope: RouteScope(id: "first", route: nil))
        let next = PresentedRoute(scope: RouteScope(id: "next", route: nil))
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(first) { .init(route: $0) }
        lifetime.synchronize(next) { .init(route: $0) }

        #expect(lifetime.isPresented)
        #expect(lifetime.presentation?.id == next.id)
        #expect(!first.scope.isAwaitingPresentationEnd)
        #expect(next.scope.isAwaitingPresentationEnd)
    }

    @Test func preparedContentWithoutALifecycleBridgeWaitsForNativeCompletion() throws {
        let engine = RouterEngine()
        let first = PresentedRoute(scope: RouteScope(id: "first", route: nil))
        let next = PresentedRoute(scope: RouteScope(id: "next", route: nil))
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(first) { .init(route: $0) }
        // SwiftUI evaluates the modal content builder before making its native views.
        lifetime.didCreateDestination(of: first.id)
        lifetime.synchronize(nil) { .init(route: $0) }
        lifetime.synchronize(next) { .init(route: $0) }
        #expect(lifetime.presentation?.id == first.id)
        #expect(first.scope.isAwaitingPresentationEnd)
        #expect(!lifetime.isPresented)
        #expect(!lifetime.isAdmitted)

        lifetime.completeDismissal(of: first.id, in: engine)
        #expect(!first.scope.isAwaitingPresentationEnd)
        lifetime.synchronize(next) { .init(route: $0) }
        #expect(try #require(lifetime.presentation).id == next.id)
        lifetime.completeDismissal(of: first.id, in: engine)
        #expect(lifetime.presentation?.id == next.id)
        #expect(lifetime.isPresented)
    }

    @Test func offWindowDestinationUpdateCannotHoldAReplacementWaitingForDismissal() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(NumberedRoute.self)
        } destinations: { RouteDestination(NumberedRoute.self) { _, _ in EmptyView() } })
        let origin = RouteRequestOrigin(scope: engine.root)
        let first = try #require(await engine.requestRouteWhenReady(NumberedRoute(number: 1), origin: origin))
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: first)) { .init(route: $0) }
        lifetime.didCreateDestination(of: ObjectIdentifier(first))
        // updateUIView reports this event before the destination enters a window.
        lifetime.handleDestinationEvent(.updated(isInstalledInWindow: false), of: ObjectIdentifier(first))
        let replacement = Task { await engine.requestRouteWhenReady(NumberedRoute(number: 2), origin: origin) }
        await waitUntil { engine.isNavigating && engine.tree.rootPath.isEmpty }
        lifetime.synchronize(nil) { .init(route: $0) }

        #expect(first.isAwaitingPresentationEnd)
        #expect(lifetime.presentation?.route.scope === first)
        lifetime.didDismantleDestination(of: ObjectIdentifier(first))
        #expect(!first.isAwaitingPresentationEnd)
        #expect(lifetime.presentation == nil)
        // Cleanup also proves a stale native event cannot invalidate the eventual successor.
        lifetime.completeDismissal(of: ObjectIdentifier(first), in: engine)
        let next = try #require(await replacement.value)
        #expect(next === engine.tree.rootPath.last)
        #expect((next.route as? NumberedRoute)?.number == 2)
        #expect(!engine.isNavigating)
        lifetime.synchronize(.init(scope: next)) { .init(route: $0) }
        lifetime.completeDismissal(of: ObjectIdentifier(first), in: engine)
        #expect(lifetime.presentation?.route.scope === next)
    }

    @Test func windowArrivalDuringCancelledPreparationStillWaitsForNativeDismissal() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(NumberedRoute.self)
        } destinations: { RouteDestination(NumberedRoute.self) { _, _ in EmptyView() } })
        let origin = RouteRequestOrigin(scope: engine.root)
        let first = try #require(await engine.requestRouteWhenReady(NumberedRoute(number: 1), origin: origin))
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: first)) { .init(route: $0) }
        lifetime.didCreateDestination(of: ObjectIdentifier(first))
        var returned = false
        let replacement = Task {
            let destination = await engine.requestRouteWhenReady(NumberedRoute(number: 2), origin: origin)
            returned = true
            return destination
        }
        await waitUntil { engine.isNavigating && engine.tree.rootPath.isEmpty }
        lifetime.synchronize(nil) { .init(route: $0) }
        // UIKit may finish installing content after the request to dismiss it.
        lifetime.didAdmitPresentation(of: ObjectIdentifier(first))
        lifetime.didDismantleDestination(of: ObjectIdentifier(first))
        #expect(first.isAwaitingPresentationEnd)
        #expect(!returned)
        lifetime.completeDismissal(of: ObjectIdentifier(first), in: engine)
        let next = try #require(await replacement.value)
        #expect((next.route as? NumberedRoute)?.number == 2)
        #expect(!engine.isNavigating)
    }

    @Test func multipleUnadmittedReplacementsKeepOnlyTheLatestAndIgnoreStaleEvents() {
        let engine = RouterEngine()
        let routes = (1...3).map { PresentedRoute(scope: RouteScope(id: $0, route: nil)) }
        let lifetime = NativePresentationLifetime()
        var builds = 0
        for route in routes {
            lifetime.synchronize(route) { builds += 1; return .init(route: $0) }
        }
        #expect(builds == 3)
        #expect(lifetime.presentation?.id == routes[2].id)
        for old in routes.prefix(2) {
            #expect(!old.scope.isAwaitingPresentationEnd)
            lifetime.didAdmitPresentation(of: old.id)
            #expect(!lifetime.beginDismissal(of: old.id))
            lifetime.completeDismissal(of: old.id, in: engine)
        }
        #expect(lifetime.isPresented)
        #expect(lifetime.presentation?.id == routes[2].id)
    }

    @Test func retainsOutgoingContentAndRejectsSuccessorsUntilCompletion() {
        let engine = RouterEngine()
        let first = PresentedRoute(scope: RouteScope(id: "first", route: nil))
        let next = PresentedRoute(scope: RouteScope(id: "next", route: nil))
        let lifetime = NativePresentationLifetime()
        var builds = 0
        let build: (PresentedRoute) -> RouteDestinationSnapshot = { builds += 1; return .init(route: $0) }
        lifetime.synchronize(first, build: build)
        lifetime.didAdmitPresentation(of: first.id)
        lifetime.synchronize(first, build: build)
        #expect(builds == 1)
        #expect(lifetime.isPresented)
        lifetime.synchronize(next, build: build)
        #expect(!lifetime.isPresented)
        #expect(lifetime.presentation?.id == first.id)
        #expect(first.scope.isAwaitingPresentationEnd)
        lifetime.completeDismissal(of: next.id, in: engine)
        #expect(lifetime.presentation?.id == first.id)
        lifetime.completeDismissal(of: first.id, in: engine)
        #expect(!first.scope.isAwaitingPresentationEnd)
        // An asynchronous handler may not yet have removed the old desired route.
        lifetime.synchronize(first, build: build)
        #expect(lifetime.presentation == nil)
        lifetime.synchronize(next, build: build)
        lifetime.completeDismissal(of: first.id, in: engine)
        #expect(lifetime.presentation?.id == next.id)
        #expect(lifetime.isPresented)
        #expect(builds == 2)
    }

    @Test func modalWaitUsesNativeCompletionEvenAfterDestinationHostDetaches() async throws {
        let engine = makeEngine()
        await engine.present(SettingsRoute())
        let scope = try #require(engine.tree.rootPath.last)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: scope)) { .init(route: $0) }
        engine.routeScopeDidInstallInView(scope)
        lifetime.didAdmitPresentation(of: ObjectIdentifier(scope))
        var returned = false
        let unwind = Task { let result = await engine.unwindPrevious(from: scope); returned = true; return result }
        await waitUntil { engine.tree.rootPath.isEmpty }
        engine.routeScopeDidLeaveView(scope)
        await Task.yield()
        #expect(!returned)
        #expect(engine.isNavigating)
        lifetime.synchronize(nil) { .init(route: $0) }
        #expect(scope.isAwaitingPresentationEnd)
        #expect(!returned)
        lifetime.completeDismissal(of: ObjectIdentifier(scope), in: engine)
        #expect(await unwind.value)
        #expect(!engine.isNavigating)
    }

    @Test func nativeCompletionDoesNotWaitForRetainedDestinationBridge() async throws {
        let engine = makeEngine()
        await engine.present(SettingsRoute())
        let scope = try #require(engine.tree.rootPath.last)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: scope)) { .init(route: $0) }
        engine.routeScopeDidInstallInView(scope)
        lifetime.didAdmitPresentation(of: ObjectIdentifier(scope))
        let unwind = Task { await engine.unwindPrevious(from: scope) }
        await waitUntil { engine.tree.rootPath.isEmpty }
        lifetime.completeDismissal(of: ObjectIdentifier(scope), in: engine)
        #expect(await unwind.value)
        #expect(scope.isInstalledInView)
        #expect(!engine.isNavigating)
        engine.routeScopeDidLeaveView(scope)
    }

    #if canImport(AppKit)


    #endif

    @Test func childOnlyPopStillWaitsForItsOwnHost() async throws {
        let (engine, modal, child, lifetime) = try await pushedFlow()
        defer { engine.routeScopeDidLeaveView(modal) }
        var completed: Bool?
        let unwind = Task { completed = await UnwindRouteAction(router: engine, routeScope: child)() }
        defer { unwind.cancel() }
        await waitUntil { !engine.isNavigationEligible(child) }
        #expect(completed == nil)
        #expect(child.isAwaitingPresentationEnd)
        #expect(lifetime.isPresented)
        engine.routeScopeDidLeaveView(child)
        await waitUntil { completed != nil }
        #expect(completed == true)
        #expect(engine.isNavigationEligible(modal))
        #expect(modal.isAwaitingPresentationEnd)
        lifetime.completeDismissal(of: ObjectIdentifier(modal), in: engine)
        await waitUntil { !engine.isNavigating }
    }

    #if canImport(AppKit)
    @Test func enclosingDismissalAlsoCompletesAnAlreadyWaitingChildPop() async throws {
        let (engine, modal, child, lifetime) = try await pushedFlow()
        defer {
            engine.routeScopeDidLeaveView(child)
            engine.routeScopeDidLeaveView(modal)
        }
        var childCompleted: Bool?, modalCompleted: Bool?
        let pop = Task { childCompleted = await UnwindRouteAction(router: engine, routeScope: child)() }
        defer { pop.cancel() }
        await waitUntil { !engine.isNavigationEligible(child) }
        #expect(childCompleted == nil)
        let dismiss = Task { modalCompleted = await UnwindRouteAction(router: engine, routeScope: modal)() }
        defer { dismiss.cancel() }
        await waitUntil { !engine.isNavigationEligible(modal) }
        #expect(childCompleted == nil)
        #expect(modalCompleted == nil)
        lifetime.synchronize(nil) { .init(route: $0) }
        lifetime.completeDismissal(of: ObjectIdentifier(modal), in: engine)
        await waitUntil { childCompleted != nil && modalCompleted != nil }
        #expect(childCompleted == true)
        #expect(modalCompleted == true)
        #expect(child.isInstalledInView)
        #expect(!engine.isNavigating)
    }

    #endif

    @Test func staleOwnerCannotRemoveAStillLiveOccurrenceWithAReplacementOwner() async throws {
        let engine = makeEngine()
        await engine.present(SettingsRoute())
        let scope = try #require(engine.tree.rootPath.last)
        let first = NativePresentationLifetime(), replacement = NativePresentationLifetime()
        for owner in [first, replacement] { owner.synchronize(.init(scope: scope)) { .init(route: $0) } }
        first.completeDismissal(of: ObjectIdentifier(scope), in: engine)
        #expect(engine.tree.rootPath.last === scope)
        #expect(scope.isAwaitingPresentationEnd)
        replacement.completeDismissal(of: ObjectIdentifier(scope), in: engine)
        #expect(engine.tree.rootPath.isEmpty)
    }

    @Test func completedOccurrenceIsReleasedByARC() {
        let engine = RouterEngine()
        let lifetime = NativePresentationLifetime()
        weak var retained: RouteScope?
        do {
            let scope = RouteScope(id: "temporary", route: nil)
            retained = scope
            lifetime.synchronize(.init(scope: scope)) { .init(route: $0) }
            lifetime.completeDismissal(of: ObjectIdentifier(scope), in: engine)
        }
        #expect(retained == nil)
        let next = RouteScope(id: "temporary", route: nil)
        lifetime.synchronize(.init(scope: next)) { .init(route: $0) }
        #expect(lifetime.presentation?.route.scope === next)
    }

    @Test func nativeCompletionDoesNotStartAnotherUnwindBeforeTheFirstCommits() async throws {
        let engine = makeEngine()
        await engine.present(SettingsRoute())
        let scope = try #require(engine.tree.rootPath.last)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: scope)) { .init(route: $0) }
        lifetime.didAdmitPresentation(of: ObjectIdentifier(scope))
        engine.root.installHookDeclarations(hookDeclarations: [UnwindHandler(SettingsRoute.self) {}.declaration])

        lifetime.requestDismissal(of: ObjectIdentifier(scope), in: engine)
        #expect(engine.navigationOperations.count == 1)
        lifetime.completeDismissal(of: ObjectIdentifier(scope), in: engine)
        #expect(engine.navigationOperations.count == 1)
        await waitUntil { engine.tree.rootPath.isEmpty && !engine.isNavigating }
    }

    @Test func cancellationBeforeNativeAdmissionDoesNotWaitForANonexistentDismissal() {
        let scope = RouteScope(id: "not mounted", route: nil)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: scope)) { .init(route: $0) }
        #expect(scope.isAwaitingPresentationEnd)
        lifetime.synchronize(nil) { .init(route: $0) }
        #expect(!scope.isAwaitingPresentationEnd)
        #expect(lifetime.presentation == nil)
        lifetime.didAdmitPresentation(of: ObjectIdentifier(scope))
        #expect(lifetime.presentation == nil)
    }

    private func pushedFlow() async throws
        -> (RouterEngine, RouteScope, RouteScope, NativePresentationLifetime) {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(SettingsRoute.self) { Push(HomeDetailRoute.self) }
        } destinations: {
            testDestination(SettingsRoute.self)
            testDestination(HomeDetailRoute.self)
        })
        await engine.present(SettingsRoute())
        let tree = engine.tree
        let modal = try #require(tree.rootPath.last)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: modal)) { .init(route: $0) }
        lifetime.didAdmitPresentation(of: ObjectIdentifier(modal))
        engine.routeScopeDidInstallInView(modal)
        await Router(engine: engine, scope: modal).present(HomeDetailRoute())
        let child = try #require(tree.rootPath.last)
        engine.routeScopeDidInstallInView(child)
        return (engine, modal, child, lifetime)
    }

    private func makeEngine() -> RouterEngine {
        RouterEngine(routes: RootRouteMap {
            testSheet(testDestination(SettingsRoute.self))

            GlobalMap {
                testSheet(testDestination(LoginRoute.self))
            }
            GlobalMap {
                testCover(testDestination(AlertRoute.self))
            }
        })
    }
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
        #expect(condition())
    }
}
