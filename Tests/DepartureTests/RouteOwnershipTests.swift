import Observation
import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RouteOwnershipTests {
    @Test func detachingABranchedModalReleasesItsEntireSubtree() async throws {
        let (engine, probe) = try await detachModalSubtree()
        #expect(probe.scope == nil)
        #expect(engine.root.lane.modal == nil)
        #expect(engine.normalSpace.rootPath.isEmpty)
    }

    @Test func outgoingSnapshotRetainsObjectsWithoutOccupyingTheLiveLane() async throws {
        let engine: RouterEngine
        let probe: RoutingOwnershipProbe
        var snapshot: RouteDestinationSnapshot?
        (engine, snapshot, probe) = try await snapshotDetachedModalSubtree()
        #expect(probe.scope != nil)
        #expect(snapshot!.route.scope.belongs(to: engine.normalSpace) == false)
        #expect(engine.normalSpace.rootPath.position(of: snapshot!.route.scope) == nil)
        #expect(engine.root.lane.modal == nil)

        let root = Router(engine: engine, scope: engine.root)
        await root.present(LoginRoute())
        let replacement = try #require(engine.normalSpace.rootPath.last)
        let branch = try #require(replacement.branchScopes["modal"])
        engine.hostDidAttach(branch, view: nil, id: UUID())
        await Router(engine: engine, scope: replacement).branch("modal").present(MessageRoute())
        let modal = try #require(branch.path.last)
        #expect(engine.root.lane.modal === modal)
        #expect(modal !== probe.scope)

        // The outgoing destination remains intact for its native exit.
        #expect(snapshot!.route.scope.branchScopes["modal"]?.path.last === probe.scope)
        snapshot = nil
        #expect(probe.scope == nil)
    }

    @Test func laneObservationInvalidatesWhenItsOccupantsOwningEdgeIsCut() async throws {
        let (engine, container, modal) = try await modalSubtree()
        let changes = OwnershipObservationCount()
        withObservationTracking {
            #expect(engine.root.lane.modal === modal)
        } onChange: {
            MainActor.assumeIsolated { changes.value += 1 }
        }
        engine.normalSpace.rootPath.keepThrough(.owner)
        #expect(changes.value == 1)
        #expect(engine.root.lane.modal == nil)
        #expect(container.branchScopes["modal"]?.path.last === modal)
    }

    @Test func storedRoutingEnvironmentDoesNotRetainItsScopeOrEngine() async {
        let (probe, source, scoped, action) = storedRoutingEnvironment()
        #expect(probe.engine == nil)
        #expect(probe.scope == nil)
        #expect(source.values.routeScope == nil)
        #expect(source.values.router.engine == nil)
        #expect(source.values.locale.identifier == "nl_NL")
        #expect(await action() == false)
        await scoped.present(LoginRoute())
        #expect(await scoped.unwind(to: .root) == false)
    }

    @Test func explicitlyCreatedRouterOwnsItsContainer() {
        var router: RootRouter? = RootRouter()
        let probe = RoutingOwnershipProbe(engine: router!.engine, scope: router!.engine.root)
        #expect(probe.engine != nil)
        #expect(probe.scope != nil)
        router = nil
        #expect(probe.engine == nil)
        #expect(probe.scope == nil)
    }
}

@MainActor
private func modalSubtree() async throws -> (RouterEngine, RouteScope, RouteScope) {
    let engine = RouterEngine(routes: RootRouteMap {
        Push(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
            Branches {
                Branch("modal") { Sheet(RouteDestination(MessageRoute.self) { _, _ in EmptyView() }) }
            }
        }
    })
    let root = Router(engine: engine, scope: engine.root)
    await root.present(LoginRoute())
    let container = try #require(engine.normalSpace.rootPath.last)
    let branch = try #require(container.branchScopes["modal"])
    engine.hostDidAttach(branch, view: nil, id: UUID())
    await Router(engine: engine, scope: container).branch("modal").present(MessageRoute())
    let modal = try #require(branch.path.last)
    return (engine, container, modal)
}

@MainActor
private func detachModalSubtree() async throws -> (RouterEngine, RoutingOwnershipProbe) {
    let (engine, _, modal) = try await modalSubtree()
    let probe = RoutingOwnershipProbe(engine: engine, scope: modal)
    engine.normalSpace.rootPath.keepThrough(.owner)
    return (engine, probe)
}

@MainActor
private func snapshotDetachedModalSubtree() async throws -> (RouterEngine, RouteDestinationSnapshot, RoutingOwnershipProbe) {
    let (engine, container, modal) = try await modalSubtree()
    let probe = RoutingOwnershipProbe(engine: engine, scope: modal)
    let snapshot = RouteDestinationSnapshot(route: .init(
        scope: container, declaration: try #require(container.presentationDeclaration)
    ))
    engine.normalSpace.rootPath.keepThrough(.owner)
    return (engine, snapshot, probe)
}

@MainActor
private func storedRoutingEnvironment() -> (RoutingOwnershipProbe, RouteSourceEnvironment, Router, UnwindRouteAction) {
    let engine = RouterEngine()
    let scope = engine.root
    let scoped = Router(engine: engine, scope: scope)
    let action = UnwindRouteAction(router: engine, routeScope: scope)
    var environment = EnvironmentValues()
    environment.routerEngine = engine
    environment.routeScope = scope
    environment.router = scoped
    environment.unwindRoute = action
    environment.locale = Locale(identifier: "nl_NL")
    scope.bindRoutingHost(RoutePresentationHostID(), automatic: true, environment: environment)
    return (RoutingOwnershipProbe(engine: engine, scope: scope), scope.sourceEnvironmentReference, scoped, action)
}

@MainActor private final class OwnershipObservationCount { var value = 0 }

@MainActor
private final class RoutingOwnershipProbe {
    weak var engine: RouterEngine?
    weak var scope: RouteScope?

    init(engine: RouterEngine, scope: RouteScope) {
        self.engine = engine
        self.scope = scope
    }
}
