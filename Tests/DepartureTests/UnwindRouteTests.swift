import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite struct UnwindRouteTests {
    @Test func localAndAncestorActionsCaptureDifferentScopes() async throws {
        let (engine, parent, _, leaf) = try await flow()
        let local = engine.unwindRouteAction(from: leaf)
        let ancestor = engine.unwindRouteAction(from: leaf, selection: .routeType(SettingsRoute.self))
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
        #expect(engine.unwindRouteAction(from: inner, selection: .routeType(NumberedRoute.self))
            == UnwindRouteAction(router: engine, routeScope: inner))
        await Router(engine: engine, scope: inner).present(HomeDetailRoute())
        let leaf = try #require(engine.defaultSpace.rootPath.last)
        let action = engine.unwindRouteAction(from: leaf, selection: .routeType(NumberedRoute.self))
        #expect(action == UnwindRouteAction(router: engine, routeScope: inner))
        #expect(await action())
        #expect(engine.defaultSpace.rootPath.last === outer)
    }

    @Test func missingAndRemovedReadersNeverFallBack() async throws {
        let (engine, parent, _, leaf) = try await flow()
        let missing = engine.unwindRouteAction(from: leaf, selection: .routeType(MessageRoute.self))
        #expect(!(await missing()))
        #expect(!(await missing(payload: "ignored")))
        #expect(engine.defaultSpace.rootPath.last === leaf)
        #expect(!(await engine.unwindRouteAction(from: nil)()))
        #expect(await UnwindRouteAction(router: engine, routeScope: leaf)())
        let removed = engine.unwindRouteAction(from: leaf, selection: .routeType(SettingsRoute.self))
        #expect(!(await removed()))
        #expect(engine.defaultSpace.rootPath.scopes.contains { $0 === parent })
    }

    @Test func retainedAncestorActionNeverRetargetsAReplacementInstance() async throws {
        let (engine, parent, _, leaf) = try await flow()
        let action = engine.unwindRouteAction(from: leaf, selection: .routeType(SettingsRoute.self))
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
        #expect(!(await engine.unwindRouteAction(from: second, selection: .routeType(SettingsRoute.self))()))
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
        #expect(!(await engine.unwindRouteAction(from: upper, selection: .routeType(SettingsRoute.self))()))
        let lowerAction = engine.unwindRouteAction(from: lower, selection: .routeType(SettingsRoute.self))
        #expect(lowerAction == UnwindRouteAction(router: engine, routeScope: parent))
        #expect(!(await lowerAction()))
        #expect(await engine.unwindRouteAction(from: upper, selection: .routeType(MessageRoute.self))())
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
        let action = engine.unwindRouteAction(from: leaf, selection: .routeType(SettingsRoute.self))
        #expect(await action(payload: "completed"))
        #expect(received == "completed")
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }

    @Test func missingTargetWarningIdentifiesRequestedType() {
        let event = DepartureWarningEvent.unwindRouteTargetMissing(target: .routeType(SettingsRoute.self))
        #expect(event.renderedMessage == "[unwind] ⊘ could not find a live SettingsRoute from the source scope")
    }

    @Test(arguments: [false, true])
    func policiesMatchBetweenRouterAndReader(useReader: Bool) async throws {
        let cases: [(Router.UnwindTarget, Int, String)] = [
            (.current, 3, "message"), (.nearestModal, 2, "numbered"),
            (.root, 0, "message")
        ]
        for (policy, remaining, expectedSource) in cases {
            let (engine, leaf) = try await policyFlow()
            var received: String?
            engine.root.installHookDeclarations(sourceID: "receiver", hookDeclarations: [
                UnwindHandler(MessageRoute.self, expecting: String.self) { received = "message:\($0)" }.declaration,
                UnwindHandler(NumberedRoute.self, expecting: String.self) { received = "numbered:\($0)" }.declaration
            ])
            // The public reader and router accept the very same policy value.
            _ = UnwindRoute(policy)
            let accepted: Bool
            if useReader {
                accepted = await engine.unwindRouteAction(from: leaf, target: policy)(payload: "done")
            } else {
                accepted = await Router(engine: engine, scope: leaf).unwind(policy, payload: "done")
            }
            #expect(accepted, "policy: \(policy), reader: \(useReader)")
            #expect(engine.root.branchScopes["flow"]?.path.count == remaining)
            #expect(engine.root.branchScopes["other"]?.path.count == (policy == .root ? 0 : 1))
            #expect(received == "\(expectedSource):done")
        }
    }

    @Test(arguments: [false, true])
    func routeTypeOverloadDismissesMatchedFlow(usePayload: Bool) async throws {
        let (engine, _, _, leaf) = try await flow()
        var received: String?
        engine.root.installHookDeclarations(sourceID: "receiver", hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: String.self) { received = $0 }.declaration
        ])
        let router = Router(engine: engine, scope: leaf)
        if usePayload {
            #expect(await router.unwind(from: SettingsRoute.self, payload: "done"))
            #expect(received == "done")
        } else {
            #expect(await router.unwind(from: SettingsRoute.self))
            #expect(received == nil)
        }
        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(!(await router.unwind(from: SettingsRoute.self)))
    }

    @Test func capturedModalIncludesLaterPushesAndDoesNotRetargetAReplacement() async throws {
        let (engine, leaf) = try await policyFlow()
        let modal = try #require(engine.root.branchScopes["flow"]?.path.scopes.dropLast().last)
        let action = engine.unwindRouteAction(from: modal, target: .nearestModal)
        #expect(await engine.unwindRouteAction(from: leaf)())
        await Router(engine: engine, scope: modal).present(MessageRoute())
        #expect(await action())
        #expect(engine.root.branchScopes["flow"]?.path.count == 2)
        #expect(!(await engine.unwindRouteAction(from: leaf)()))
        let child = try #require(engine.root.branchScopes["flow"]?.path.last)
        await Router(engine: engine, scope: child).present(NumberedRoute(number: 2))
        let replacement = try #require(engine.root.branchScopes["flow"]?.path.last)
        await Router(engine: engine, scope: replacement).present(MessageRoute())
        #expect(!(await action()))
        #expect(engine.root.branchScopes["flow"]?.path.count == 4)
    }

    @Test func capturedRootResetRequiresItsOriginalRequester() async throws {
        let (engine, _, _, leaf) = try await flow()
        let reset = engine.unwindRouteAction(from: leaf, target: .root)
        #expect(await engine.unwindRouteAction(from: leaf)())
        #expect(!(await reset()))
        #expect(engine.defaultSpace.rootPath.count == 2)
    }

    @Test func missingModalNeverFallsBackToLocalDismissal() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(SettingsRoute.self)
        } destinations: { testDestination(SettingsRoute.self) })
        await engine.present(SettingsRoute())
        let scope = try #require(engine.defaultSpace.rootPath.last)
        #expect(!(await Router(engine: engine, scope: scope).unwind(.nearestModal)))
        #expect(!(await engine.unwindRouteAction(from: scope, target: .nearestModal)()))
        #expect(engine.defaultSpace.rootPath.last === scope)
        #expect(!(await Router(engine: engine, scope: scope).unwind(from: NumberedRoute.self)))
    }

    @Test func nearestModalDoesNotCrossPrioritySpaces() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(SettingsRoute.self)
            HighPriority { Cover(MessageRoute.self) { Push(NumberedRoute.self) } }
        } destinations: {
            testDestination(SettingsRoute.self)
            testDestination(MessageRoute.self)
            testDestination(NumberedRoute.self)
        })
        await engine.present(SettingsRoute())
        let lower = try #require(engine.defaultSpace.rootPath.last)
        let action = engine.unwindRouteAction(from: lower, target: .nearestModal)
        await engine.present(MessageRoute())
        let high = try #require(engine.spaces.highSpace)
        await Router(engine: engine, scope: high.root).present(NumberedRoute(number: 1))
        let upper = try #require(high.rootPath.last)
        #expect(!(await action()))
        #expect(await Router(engine: engine, scope: upper).unwind(.nearestModal))
        #expect(engine.spaces.highSpace == nil)
        #expect(engine.defaultSpace.rootPath.last === lower)
        #expect(await action())
    }

    private func policyFlow() async throws -> (RouterEngine, RouteScope) {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches(concurrent: true) {
                Branch("flow") {
                    Sheet(SettingsRoute.self) {
                        Push(HomeDetailRoute.self) {
                            Sheet(NumberedRoute.self) { Push(MessageRoute.self) }
                        }
                    }
                }
                Branch("other") { Push(HomeDetailRoute.self) }
            }
        } destinations: {
            testDestination(SettingsRoute.self)
            testDestination(HomeDetailRoute.self)
            testDestination(NumberedRoute.self)
            testDestination(MessageRoute.self)
        })
        await Router(engine: engine, scope: engine.root).branch("other").present(HomeDetailRoute())
        await Router(engine: engine, scope: engine.root).branch("flow").present(SettingsRoute())
        let branch = try #require(engine.root.branchScopes["flow"])
        var current = try #require(branch.path.last)
        await Router(engine: engine, scope: current).present(HomeDetailRoute())
        current = try #require(branch.path.last)
        await Router(engine: engine, scope: current).present(NumberedRoute(number: 1))
        current = try #require(branch.path.last)
        await Router(engine: engine, scope: current).present(MessageRoute())
        return (engine, try #require(branch.path.last))
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
