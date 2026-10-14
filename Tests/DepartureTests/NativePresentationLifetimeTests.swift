import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite(.timeLimit(.minutes(1)))
struct NativePresentationLifetimeTests {
    @Test(arguments: [false, true])
    func retainedDestinationSnapshotDoesNotRetainItsNativeOwner(customized: Bool) throws {
        let route = PresentedRoute(scope: RouteScope(id: "snapshot", route: nil))
        var lifetime: NativePresentationLifetime? = NativePresentationLifetime()
        weak let owner = lifetime
        lifetime?.synchronize(route) {
            if customized {
                .init(route: $0, destinationBuilder: WindowDestinationBuilder { view, _ in view }, nativePresentation: lifetime)
            } else {
                .init(route: $0, nativePresentation: lifetime)
            }
        }
        let snapshot = try #require(lifetime?.presentation)
        lifetime = nil
        #expect(owner == nil)
        #expect(!route.scope.isAwaitingPresentationEnd)
        withExtendedLifetime(snapshot) {}
    }

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
        await waitUntil { engine.isNavigating && engine.defaultSpace.rootPath.isEmpty }
        lifetime.synchronize(nil) { .init(route: $0) }

        #expect(first.isAwaitingPresentationEnd)
        #expect(lifetime.presentation?.route.scope === first)
        lifetime.didDismantleDestination(of: ObjectIdentifier(first))
        #expect(!first.isAwaitingPresentationEnd)
        #expect(lifetime.presentation == nil)
        // Cleanup also proves a stale native event cannot invalidate the eventual successor.
        lifetime.completeDismissal(of: ObjectIdentifier(first), in: engine)
        let next = try #require(await replacement.value)
        #expect(next === engine.defaultSpace.rootPath.last)
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
        await waitUntil { engine.isNavigating && engine.defaultSpace.rootPath.isEmpty }
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
        let scope = try #require(engine.defaultSpace.rootPath.last)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: scope)) { .init(route: $0) }
        engine.routeScopeDidInstallInView(scope)
        lifetime.didAdmitPresentation(of: ObjectIdentifier(scope))
        var returned = false
        let unwind = Task { let result = await engine.unwindPrevious(from: scope); returned = true; return result }
        await waitUntil { engine.defaultSpace.rootPath.isEmpty }
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
        let scope = try #require(engine.defaultSpace.rootPath.last)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: scope)) { .init(route: $0) }
        engine.routeScopeDidInstallInView(scope)
        lifetime.didAdmitPresentation(of: ObjectIdentifier(scope))
        let unwind = Task { await engine.unwindPrevious(from: scope) }
        await waitUntil { engine.defaultSpace.rootPath.isEmpty }
        lifetime.completeDismissal(of: ObjectIdentifier(scope), in: engine)
        #expect(await unwind.value)
        #expect(scope.isInstalledInView)
        #expect(!engine.isNavigating)
        engine.routeScopeDidLeaveView(scope)
    }

    @Test func ordinaryBridgeTeardownHasNoAuthorityOverAnElevatedSpace() async throws {
        let engine = makeEngine()
        await engine.present(LoginRoute())
        let space = try #require(engine.spaces.highSpace)
        engine.routeScopeDidInstallInView(space.root)
        engine.routeScopeDidLeaveView(space.root)
        #expect(engine.spaces.highSpace === space)
    }

    @Test func coveredNativeOwnerRemovalNotifiesBeforeCommitAndCannotAffectSuccessor() async throws {
        let engine = makeEngine()
        await engine.present(LoginRoute())
        let high = try #require(engine.spaces.highSpace)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: high.root)) { .init(route: $0) }
        await engine.present(AlertRoute())
        let critical = try #require(engine.spaces.criticalSpace)
        var notifications = 0
        engine.root.installHookDeclarations(hookDeclarations: [UnwindHandler(LoginRoute.self) {
            #expect(engine.spaces.highSpace === high)
            notifications += 1
        }.declaration])
        lifetime.completeDismissal(of: ObjectIdentifier(high.root), in: engine)
        await waitUntil { engine.spaces.highSpace == nil && !engine.isNavigating }
        #expect(notifications == 1)
        #expect(engine.spaces.criticalSpace === critical)
        lifetime.completeDismissal(of: ObjectIdentifier(high.root), in: engine)
        #expect(notifications == 1)
    }

    @Test func bufferedPresentationWaitsForNativeCompletionThenRechecksCoverage() async throws {
        let engine = makeEngine()
        await engine.present(LoginRoute())
        let high = try #require(engine.spaces.highSpace)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: high.root)) { .init(route: $0) }
        let removal = Task { await RootRouter(engine: engine).dismissSpace(.high) }
        await waitUntil { engine.spaces.highSpace == nil }
        let presentation = Task { await RootRouter(engine: engine).default.present(SettingsRoute()) }
        await waitUntil { engine.pendingRoute != nil }
        #expect(engine.defaultSpace.rootPath.isEmpty)
        lifetime.completeDismissal(of: ObjectIdentifier(high.root), in: engine)
        #expect(await removal.value)
        await presentation.value
        #expect(engine.defaultSpace.rootPath.last?.route is SettingsRoute)
        #expect(!engine.isNavigating)
    }

    @Test func staleOwnerCannotRemoveAStillLiveOccurrenceWithAReplacementOwner() async throws {
        let engine = makeEngine()
        await engine.present(SettingsRoute())
        let scope = try #require(engine.defaultSpace.rootPath.last)
        let first = NativePresentationLifetime(), replacement = NativePresentationLifetime()
        for owner in [first, replacement] { owner.synchronize(.init(scope: scope)) { .init(route: $0) } }
        first.completeDismissal(of: ObjectIdentifier(scope), in: engine)
        #expect(engine.defaultSpace.rootPath.last === scope)
        #expect(scope.isAwaitingPresentationEnd)
        replacement.completeDismissal(of: ObjectIdentifier(scope), in: engine)
        #expect(engine.defaultSpace.rootPath.isEmpty)
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
        let scope = try #require(engine.defaultSpace.rootPath.last)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: scope)) { .init(route: $0) }
        lifetime.didAdmitPresentation(of: ObjectIdentifier(scope))
        engine.root.installHookDeclarations(hookDeclarations: [UnwindHandler(SettingsRoute.self) {}.declaration])

        lifetime.requestDismissal(of: ObjectIdentifier(scope), in: engine)
        #expect(engine.navigationOperations.count == 1)
        lifetime.completeDismissal(of: ObjectIdentifier(scope), in: engine)
        #expect(engine.navigationOperations.count == 1)
        await waitUntil { engine.defaultSpace.rootPath.isEmpty && !engine.isNavigating }
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

    private func makeEngine() -> RouterEngine {
        RouterEngine(routes: RootRouteMap {
            testSheet(testDestination(SettingsRoute.self))

            HighPriority {
                testSheet(testDestination(LoginRoute.self))
            }
            CriticalPriority {
                testCover(testDestination(AlertRoute.self))
            }
        })
    }
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
        #expect(condition())
    }
}
