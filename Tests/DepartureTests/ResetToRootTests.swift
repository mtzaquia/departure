import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite(.timeLimit(.minutes(1))) struct ResetToRootTests {
    @Test(arguments: [RoutePriority.default, .high, .critical], [false, true])
    func resetRetainsTheSpaceRootAndDeliversTheSourcePayload(priority: RoutePriority, usePayload: Bool) async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(SettingsRoute.self)
            HighPriority { Cover(MessageRoute.self) { Push(SettingsRoute.self) } }
            CriticalPriority { Cover(NumberedRoute.self) { Push(SettingsRoute.self) } }
        } destinations: {
            testDestination(SettingsRoute.self)
            testDestination(MessageRoute.self)
            testDestination(NumberedRoute.self)
        })
        if priority == .high { await engine.present(MessageRoute()) }
        if priority == .critical { await engine.present(NumberedRoute(number: 1)) }
        let space = try #require(engine.spaces.space(for: priority))
        let root = space.root
        let presentation = root.routePresentation
        var received: [String] = []
        root.installHookDeclarations(sourceID: "receiver", hookDeclarations: [
            UnwindHandler(SettingsRoute.self) { received.append("no payload") }.declaration,
            UnwindHandler(SettingsRoute.self, expecting: String.self) { received.append($0) }.declaration
        ])
        let rootRouter = Router(engine: engine, scope: root)
        #expect(!(await rootRouter.resetToRoot()))
        #expect(received.isEmpty)
        await rootRouter.present(SettingsRoute())
        let source = try #require(space.rootPath.last)
        let router = Router(engine: engine, scope: source)
        if usePayload { #expect(await router.resetToRoot(payload: "done")) }
        else { #expect(await router.resetToRoot()) }
        #expect(received == [usePayload ? "done" : "no payload"])
        #expect(engine.spaces.space(for: priority) === space)
        #expect(space.root === root)
        #expect(root.routePresentation == presentation)
        #expect(space.rootPath.isEmpty)
        #expect(!(await rootRouter.resetToRoot()))
        #expect(received.count == 1)
    }

    @Test(arguments: [false, true])
    func optionalNilRemainsATypedPayloadForResetAndCapturedDismissal(useReset: Bool) async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(SettingsRoute.self)
        } destinations: { testDestination(SettingsRoute.self) })
        var payloads: [String?] = []
        var payloadFreeCalls = 0
        engine.root.installHookDeclarations(sourceID: "receiver", hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: Optional<String>.self) { payloads.append($0) }.declaration,
            UnwindHandler(SettingsRoute.self) { payloadFreeCalls += 1 }.declaration
        ])
        await engine.present(SettingsRoute())
        let source = try #require(engine.defaultSpace.rootPath.last)
        if useReset {
            #expect(await Router(engine: engine, scope: source).resetToRoot(payload: Optional<String>.none))
        } else {
            #expect(await engine.unwindRouteAction(from: source)(payload: Optional<String>.none))
        }
        try #require(payloads.count == 1)
        #expect(payloads[0] == nil)
        #expect(payloadFreeCalls == 0)
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }

    #if DEBUG
    @Test func logIdentifiesResetRatherThanADismissalTarget() {
        let event = DepartureLogEvent.resetToRootRequested
        #expect(event.logLevel == .normal)
        #expect(event.renderedMessage == "[unwind] ⇢ requested reset to priority-space root")
    }
    #endif
}
