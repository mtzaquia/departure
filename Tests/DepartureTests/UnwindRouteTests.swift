import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite struct UnwindRouteTests {
    @Test func localAndAncestorActionsCaptureDifferentScopes() async throws {
        let (engine, parent, _, leaf) = try await flow()
        let local = engine.unwindRouteAction(from: leaf)
        let ancestor = engine.unwindRouteAction(from: leaf, matching: SettingsRoute.self)
        #expect(local == UnwindRouteAction(router: engine, routeScope: leaf))
        #expect(ancestor == UnwindRouteAction(router: engine, routeScope: parent))
        #expect(local != ancestor)
        #expect(await ancestor())
        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(!(await local()))
    }

    @Test func nearestRepeatedTypeWinsAndIncludesCurrentScope() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(NumberedRoute.self) {
                Push(NumberedRoute.self) { Sheet(HomeDetailRoute.self) }
            }
        } destinations: {
            testDestination(NumberedRoute.self)
            testDestination(HomeDetailRoute.self)
        })
        await engine.present(NumberedRoute(number: 1))
        let outer = try #require(engine.defaultSpace.rootPath.last)
        await Router(engine: engine, scope: outer).present(NumberedRoute(number: 2))
        let inner = try #require(engine.defaultSpace.rootPath.last)
        #expect(engine.unwindRouteAction(from: inner, matching: NumberedRoute.self)
            == UnwindRouteAction(router: engine, routeScope: inner))
        await Router(engine: engine, scope: inner).present(HomeDetailRoute())
        let leaf = try #require(engine.defaultSpace.rootPath.last)
        let action = engine.unwindRouteAction(from: leaf, matching: NumberedRoute.self)
        #expect(action == UnwindRouteAction(router: engine, routeScope: inner))
        #expect(await action())
        #expect(engine.defaultSpace.rootPath.last === outer)
    }

    @Test func missingAndRemovedReadersNeverFallBack() async throws {
        let (engine, parent, _, leaf) = try await flow()
        let missing = engine.unwindRouteAction(from: leaf, matching: MessageRoute.self)
        #expect(!(await missing()))
        #expect(!(await missing(payload: "ignored")))
        #expect(engine.defaultSpace.rootPath.last === leaf)
        #expect(!(await engine.unwindRouteAction(from: nil)()))
        #expect(await UnwindRouteAction(router: engine, routeScope: leaf)())
        let removed = engine.unwindRouteAction(from: leaf, matching: SettingsRoute.self)
        #expect(!(await removed()))
        #expect(engine.defaultSpace.rootPath.scopes.contains { $0 === parent })
    }

    @Test func retainedAncestorActionNeverRetargetsAReplacementInstance() async throws {
        let (engine, parent, _, leaf) = try await flow()
        let action = engine.unwindRouteAction(from: leaf, matching: SettingsRoute.self)
        #expect(await action())
        await engine.present(SettingsRoute())
        let replacement = try #require(engine.defaultSpace.rootPath.last)
        #expect(replacement !== parent)
        #expect(!(await action()))
        #expect(engine.defaultSpace.rootPath.last === replacement)
    }

    @Test func lookupNeverSearchesASiblingBranch() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches(concurrent: true) {
                Branch("first") { Push(SettingsRoute.self) }
                Branch("second") { Push(HomeDetailRoute.self) }
            }
        } destinations: {
            testDestination(SettingsRoute.self)
            testDestination(HomeDetailRoute.self)
        })
        await Router(engine: engine, scope: engine.root).branch("first").present(SettingsRoute())
        await Router(engine: engine, scope: engine.root).branch("second").present(HomeDetailRoute())
        let first = try #require(engine.root.branchScopes["first"]?.path.last)
        let second = try #require(engine.root.branchScopes["second"]?.path.last)
        #expect(!(await engine.unwindRouteAction(from: second, matching: SettingsRoute.self)()))
        #expect(engine.root.branchScopes["first"]?.path.last === first)
        #expect(engine.root.branchScopes["second"]?.path.last === second)
    }

    @Test func lookupStaysInItsSpaceAndCoveredCapturesRemainScopeBound() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(SettingsRoute.self) { Push(HomeDetailRoute.self) }
            HighPriority { Cover(MessageRoute.self) { Push(NumberedRoute.self) } }
        } destinations: {
            testDestination(SettingsRoute.self)
            testDestination(HomeDetailRoute.self)
            testDestination(MessageRoute.self)
            testDestination(NumberedRoute.self)
        })
        await engine.present(SettingsRoute())
        let parent = try #require(engine.defaultSpace.rootPath.last)
        await Router(engine: engine, scope: parent).present(HomeDetailRoute())
        let lower = try #require(engine.defaultSpace.rootPath.last)
        await engine.present(MessageRoute())
        let high = try #require(engine.spaces.highSpace)
        await Router(engine: engine, scope: high.root).present(NumberedRoute(number: 1))
        let upper = try #require(high.rootPath.last)
        #expect(!(await engine.unwindRouteAction(from: upper, matching: SettingsRoute.self)()))
        let lowerAction = engine.unwindRouteAction(from: lower, matching: SettingsRoute.self)
        #expect(lowerAction == UnwindRouteAction(router: engine, routeScope: parent))
        #expect(!(await lowerAction()))
        #expect(await engine.unwindRouteAction(from: upper, matching: MessageRoute.self)())
        #expect(engine.spaces.highSpace == nil)
        #expect(await lowerAction())
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }

    @Test func ancestorActionPreservesTypedPayloadDelivery() async throws {
        let (engine, _, _, leaf) = try await flow()
        var received: String?
        engine.root.installHookDeclarations(sourceID: "receiver", hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: String.self) { received = $0 }.declaration
        ])
        let action = engine.unwindRouteAction(from: leaf, matching: SettingsRoute.self)
        #expect(await action(payload: "completed"))
        #expect(received == "completed")
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }

    @Test func missingTargetWarningNamesTheReaderAndRequestedType() {
        let event = DepartureWarningEvent.unwindRouteTargetMissing(routeType: SettingsRoute.self)
        #expect(event.renderedMessage == "[unwind] ⊘ could not find a live SettingsRoute in the unwind reader's scope ancestry")
    }

    private func flow() async throws -> (RouterEngine, RouteScope, RouteScope, RouteScope) {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(SettingsRoute.self) { Push(HomeDetailRoute.self) { Sheet(NumberedRoute.self) } }
        } destinations: {
            testDestination(SettingsRoute.self)
            testDestination(HomeDetailRoute.self)
            testDestination(NumberedRoute.self)
        })
        await engine.present(SettingsRoute())
        let parent = try #require(engine.defaultSpace.rootPath.last)
        await Router(engine: engine, scope: parent).present(HomeDetailRoute())
        let child = try #require(engine.defaultSpace.rootPath.last)
        await Router(engine: engine, scope: child).present(NumberedRoute(number: 1))
        return (engine, parent, child, try #require(engine.defaultSpace.rootPath.last))
    }
}
