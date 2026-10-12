import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite
struct HookMergingTests {
    @Test(arguments: [false, true])
    func actionSourcesComposeUpdateAndDetachIndependently(removeFirst: Bool) async {
        let engine = RouterEngine()
        let probe = HookMergingProbe()
        engine.root.installHookDeclarations(sourceID: "first", hookDeclarations: [
            ActionInterceptor(FirstMergedAction.self) { _ in probe.events.append("first") }.declaration,
        ])
        engine.root.installHookDeclarations(sourceID: "second", hookDeclarations: [
            ActionInterceptor(SecondMergedAction.self) { _ in probe.events.append("second") }.declaration,
        ])
        await engine.performAction(FirstMergedAction(probe: probe))
        await engine.performAction(SecondMergedAction(probe: probe))
        #expect(probe.events == ["first", "second"])

        // Replacing captured closures must refresh the source even when keys stay the same.
        engine.root.installHookDeclarations(sourceID: "first", hookDeclarations: [
            ActionInterceptor(FirstMergedAction.self) { _ in probe.events.append("updated") }.declaration,
        ])
        await engine.performAction(FirstMergedAction(probe: probe))
        await engine.performAction(SecondMergedAction(probe: probe))
        #expect(probe.events == ["first", "second", "updated", "second"])

        engine.root.uninstallHookDeclarations(sourceID: removeFirst ? "first" : "second")
        probe.events = []
        await engine.performAction(FirstMergedAction(probe: probe))
        await engine.performAction(SecondMergedAction(probe: probe))
        #expect(probe.events == (removeFirst ? ["first-body", "second"] : ["updated", "second-body"]))
    }

    @Test func updatingOneSourceRemovesOnlyItsOldKeys() async {
        let engine = RouterEngine()
        let probe = HookMergingProbe()
        engine.root.installHookDeclarations(sourceID: "first", hookDeclarations: [
            ActionInterceptor(FirstMergedAction.self) { _ in probe.events.append("first") }.declaration,
        ])
        engine.root.installHookDeclarations(sourceID: "second", hookDeclarations: [
            ActionInterceptor(SecondMergedAction.self) { _ in probe.events.append("second") }.declaration,
        ])
        engine.root.installHookDeclarations(sourceID: "first", hookDeclarations: [
            UnwindHandler(SettingsRoute.self) {}.declaration,
        ])
        await engine.performAction(FirstMergedAction(probe: probe))
        await engine.performAction(SecondMergedAction(probe: probe))
        #expect(probe.events == ["first-body", "second"])
        #expect(engine.root.hookAttachments.count == 2)
    }

    @Test(arguments: [false, true])
    func duplicateInterceptorsDisableOnlyTheirKeyAndRecover(removeFirst: Bool) async {
        let engine = RouterEngine()
        let probe = HookMergingProbe()
        for source in ["first", "second"] {
            engine.root.installHookDeclarations(sourceID: AnyHashable(source), hookDeclarations: [
                ActionInterceptor(FirstMergedAction.self) { _ in probe.events.append(source) }.declaration,
            ])
        }
        engine.root.installHookDeclarations(sourceID: "distinct", hookDeclarations: [
            ActionInterceptor(SecondMergedAction.self) { _ in probe.events.append("distinct") }.declaration,
        ])
        await engine.performAction(FirstMergedAction(probe: probe))
        await engine.performAction(SecondMergedAction(probe: probe))
        #expect(probe.events == ["distinct"])

        // A refresh must not turn one of the duplicates into a winner.
        engine.root.installHookDeclarations(sourceID: "first", hookDeclarations: [
            ActionInterceptor(FirstMergedAction.self) { _ in probe.events.append("updated") }.declaration,
        ])
        await engine.performAction(FirstMergedAction(probe: probe))
        #expect(probe.events == ["distinct"])
        engine.root.uninstallHookDeclarations(sourceID: removeFirst ? "first" : "second")
        await engine.performAction(FirstMergedAction(probe: probe))
        #expect(probe.events == ["distinct", removeFirst ? "second" : "updated"])
    }

    @Test func duplicatesWithinOneBuilderCanBeCorrectedByUpdatingIt() async {
        let engine = RouterEngine()
        let probe = HookMergingProbe()
        let hook = ActionInterceptor(FirstMergedAction.self) { _ in probe.events.append("hook") }.declaration
        engine.root.installHookDeclarations(hookDeclarations: [hook, hook])
        await engine.performAction(FirstMergedAction(probe: probe))
        #expect(probe.events.isEmpty)
        engine.root.installHookDeclarations(hookDeclarations: [hook])
        await engine.performAction(FirstMergedAction(probe: probe))
        #expect(probe.events == ["hook"])
    }

    @Test func conflictingUnwindHandlersDoNotFallBackToAncestorAndRecover() async throws {
        let engine = RouterEngine()
        let probe = HookMergingProbe()
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(LoginRoute.self)._routeDeclarations),
        ])
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(SettingsRoute.self) { probe.events.append("ancestor") }.declaration,
        ])
        await engine.present(LoginRoute())
        let receiver = try #require(engine.normalTree.rootPath.last)
        receiver.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
        ])
        for source in ["first", "second"] {
            receiver.installHookDeclarations(sourceID: AnyHashable(source), hookDeclarations: [
                UnwindHandler(SettingsRoute.self) { probe.events.append(source) }.declaration,
            ])
        }
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor)
        #expect(probe.events.isEmpty)
        receiver.uninstallHookDeclarations(sourceID: "second")
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor)
        #expect(probe.events == ["first"])
    }

    @Test func rebuildingRouteDeclarationsPreservesMergedHooksAndConflicts() async {
        let engine = RouterEngine()
        let probe = HookMergingProbe()
        for source in ["first", "second"] {
            engine.root.installHookDeclarations(sourceID: AnyHashable(source), hookDeclarations: [
                ActionInterceptor(FirstMergedAction.self) { _ in probe.events.append(source) }.declaration,
            ])
        }
        engine.root.installHookDeclarations(sourceID: "distinct", hookDeclarations: [
            ActionInterceptor(SecondMergedAction.self) { _ in probe.events.append("distinct") }.declaration,
        ])
        engine.root.installRouteDeclarations(id: "updated", branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
        ])
        await engine.performAction(FirstMergedAction(probe: probe))
        await engine.performAction(SecondMergedAction(probe: probe))
        #expect(probe.events == ["distinct"])
        engine.root.uninstallRouteDeclarations(sourceID: "default")
        await engine.performAction(FirstMergedAction(probe: probe))
        await engine.performAction(SecondMergedAction(probe: probe))
        #expect(probe.events == ["distinct", "distinct"])
    }

    @Test func unwindHandlersComposeByRouteAndPayloadAndDisableOnlyDuplicateKeys() async {
        let engine = RouterEngine()
        let probe = HookMergingProbe()
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
        ])
        engine.root.installHookDeclarations(sourceID: "string", hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: String.self) { probe.events.append($0) }.declaration,
        ])
        engine.root.installHookDeclarations(sourceID: "int", hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: Int.self) { probe.events.append(String($0)) }.declaration,
        ])
        engine.root.installHookDeclarations(sourceID: "payload-free", hookDeclarations: [
            UnwindHandler(SettingsRoute.self) { probe.events.append("payload-free") }.declaration,
        ])
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor, payload: "text")
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor, payload: 42)
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor)
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor, payload: true)
        #expect(probe.events == ["text", "42", "payload-free"])

        engine.root.installHookDeclarations(sourceID: "duplicate", hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: String.self) { probe.events.append("duplicate:" + $0) }.declaration,
        ])
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor, payload: "blocked")
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor, payload: 43)
        #expect(probe.events == ["text", "42", "payload-free", "43"])
        engine.root.uninstallHookDeclarations(sourceID: "duplicate")
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor, payload: "restored")
        #expect(probe.events == ["text", "42", "payload-free", "43", "restored"])
    }

    @Test func explicitOptionalNilPayloadIsDistinctFromPayloadFreeUnwind() async throws {
        let engine = RouterEngine()
        let probe = HookMergingProbe()
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
        ])
        engine.root.installHookDeclarations(sourceID: "typed", hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: String?.self) { value in
                probe.events.append(value ?? "optional-nil")
            }.declaration,
        ])
        engine.root.installHookDeclarations(sourceID: "payload-free", hookDeclarations: [
            UnwindHandler(SettingsRoute.self) { probe.events.append("payload-free") }.declaration,
        ])
        await engine.present(SettingsRoute())
        let first = try #require(engine.normalTree.rootPath.last)
        #expect(await Router(engine: engine, scope: first).unwind(to: .topmostAncestor, payload: Optional<String>.none))
        #expect(probe.events == ["optional-nil"])
        await engine.present(SettingsRoute())
        let second = try #require(engine.normalTree.rootPath.last)
        #expect(await Router(engine: engine, scope: second).unwind(to: .topmostAncestor))
        #expect(probe.events == ["optional-nil", "payload-free"])
    }

    @Test func compatibleTypedHandlerAcceptsSubclassPayload() async {
        let engine = RouterEngine()
        let probe = HookMergingProbe()
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
        ])
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: MergedPayload.self) { _ in probe.events.append("base") }.declaration,
        ])
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor, payload: MergedChildPayload())
        #expect(probe.events == ["base"])
    }

    @Test func exactPayloadMatchWinsAndAmbiguousCompatibleHandlersAreDisabled() async {
        let engine = RouterEngine()
        let probe = HookMergingProbe()
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
        ])
        engine.root.installHookDeclarations(sourceID: "compatible", hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: MergedPayload.self) { _ in probe.events.append("base") }.declaration,
            UnwindHandler(SettingsRoute.self, expecting: (any MergedPayloadMarker).self) { _ in probe.events.append("protocol") }.declaration,
        ])
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor, payload: MergedChildPayload())
        #expect(probe.events.isEmpty)
        engine.root.installHookDeclarations(sourceID: "exact", hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: MergedChildPayload.self) { _ in probe.events.append("exact") }.declaration,
        ])
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor, payload: MergedChildPayload())
        #expect(probe.events == ["exact"])
    }

    @Test func separateSourcesHandleActionsAndUnwindsTogether() async {
        let engine = RouterEngine()
        let probe = HookMergingProbe()
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
        ])
        engine.root.installHookDeclarations(sourceID: "actions", hookDeclarations: [
            ActionInterceptor(FirstMergedAction.self) { _ in probe.events.append("action") }.declaration,
        ])
        engine.root.installHookDeclarations(sourceID: "unwinds", hookDeclarations: [
            UnwindHandler(SettingsRoute.self) { probe.events.append("unwind") }.declaration,
        ])
        await engine.performAction(FirstMergedAction(probe: probe))
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor)
        #expect(probe.events == ["action", "unwind"])

        engine.root.uninstallHookDeclarations(sourceID: "actions")
        await engine.performAction(FirstMergedAction(probe: probe))
        await engine.present(SettingsRoute())
        await engine.unwind(to: .topmostAncestor)
        #expect(probe.events == ["action", "unwind", "first-body", "unwind"])
    }
}

@MainActor
private final class HookMergingProbe {
    var events: [String] = []
}

private struct FirstMergedAction: Action {
    let probe: HookMergingProbe
    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        probe.events.append("first-body")
    }
}

private struct SecondMergedAction: Action {
    let probe: HookMergingProbe
    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        probe.events.append("second-body")
    }
}

private protocol MergedPayloadMarker {}
private class MergedPayload {}
private final class MergedChildPayload: MergedPayload, MergedPayloadMarker {}
