import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SheetReplacementTests {
    @Test(arguments: ["root", "branch", "pushed"])
    func replacementBeforeInstallationKeepsOnlyTheSuccessor(host: String) async throws {
        let map: RootRouteMap
        switch host {
        case "branch":
            map = RootRouteMap {
                Branches { Branch("home") { Sheet(NumberedRoute.self) } }
            } destinations: { RouteDestination(NumberedRoute.self) { _, _ in EmptyView() } }
        case "pushed":
            map = RootRouteMap {
                Push(SettingsRoute.self) { Sheet(NumberedRoute.self) }
            } destinations: {
                RouteDestination(SettingsRoute.self) { _, _ in EmptyView() }
                RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }
            }
        default:
            map = RootRouteMap { Sheet(NumberedRoute.self) } destinations: {
                RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }
            }
        }
        let engine = RouterEngine(routes: map)
        let source: RouteScope
        if host == "branch" {
            source = try #require(engine.root.branchScopes["home"])
        } else if host == "pushed" {
            await Router(engine: engine, scope: engine.root).present(SettingsRoute())
            source = try #require(engine.defaultSpace.rootPath.last)
            engine.routeScopeDidInstallInView(source)
        } else {
            source = engine.root
        }
        let origin = RouteRequestOrigin(scope: source)
        let first = try #require(await engine.requestRouteWhenReady(NumberedRoute(number: 1), origin: origin))
        let next = try #require(await engine.requestRouteWhenReady(NumberedRoute(number: 2), origin: origin))

        let path = try #require(engine.spaces.routePath(containing: next))
        #expect(path.scopes.compactMap { ($0.route as? NumberedRoute)?.number } == [2])
        #expect(path.last === next)
        #expect(engine.spaces.routePath(containing: first) == nil)
        #expect(engine.spaces.routePath(containing: source) != nil)
        #expect(!engine.isNavigating)
        #expect(engine.pendingRoute == nil)
    }
}
