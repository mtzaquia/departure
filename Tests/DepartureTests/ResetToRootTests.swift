import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite(.timeLimit(.minutes(1))) struct ResetToRootTests {


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
        let source = try #require(engine.tree.rootPath.last)
        if useReset {
            #expect(await Router(engine: engine, scope: source).resetToRoot(payload: Optional<String>.none))
        } else {
            #expect(await engine.unwindRouteAction(from: source)(payload: Optional<String>.none))
        }
        try #require(payloads.count == 1)
        #expect(payloads[0] == nil)
        #expect(payloadFreeCalls == 0)
        #expect(engine.tree.rootPath.isEmpty)
    }

    #if DEBUG
    @Test func logIdentifiesResetRatherThanADismissalTarget() {
        let event = DepartureLogEvent.resetToRootRequested
        #expect(event.logLevel == .normal)
        #expect(event.renderedMessage == "[unwind] ⇢ requested reset to application root")
    }
    #endif
}
