import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HookBindingTests {
    @Test(arguments: [false, true])
    func sameRouteHandlersComposeByPayloadTypeAndPayloadFreeRequests(reverse: Bool) async throws {
        let engine = RouterEngine(routes: RootRouteMap { Sheet(LoginRoute.self) { _, _ in EmptyView() } })
        let router = Router(engine: engine, scope: engine.root)
        let probe = HookBindingProbe()
        let sources: [(String, AnyHookDeclaration)] = [
            ("string", UnwindHandler(LoginRoute.self, expecting: String.self) { probe.events.append("string:\($0)") }.declaration),
            ("int", UnwindHandler(LoginRoute.self, expecting: Int.self) { probe.events.append("int:\($0)") }.declaration),
            ("payload-free", UnwindHandler(LoginRoute.self) { probe.events.append("payload-free") }.declaration),
        ]
        for (id, hook) in reverse ? Array(sources.reversed()) : sources {
            engine.root.installHookDeclarations(sourceID: id, hookDeclarations: [hook])
        }
        for payload in ["done", 42, nil, true] as [Any?] {
            await router.present(LoginRoute())
            let source = try #require(engine.defaultSpace.rootPath.last)
            let scoped = Router(engine: engine, scope: source)
            if let payload { #expect(await scoped.unwind(to: .topmostAncestor, payload: payload)) }
            else { #expect(await scoped.unwind(to: .topmostAncestor)) }
        }
        #expect(probe.events == ["string:done", "int:42", "payload-free"])
    }

    @Test func anOptionalNilPayloadIsDistinctFromAPayloadFreeUnwind() async throws {
        let engine = RouterEngine(routes: RootRouteMap { Sheet(LoginRoute.self) { _, _ in EmptyView() } })
        let root = Router(engine: engine, scope: engine.root)
        let probe = HookBindingProbe()
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LoginRoute.self, expecting: String?.self) { value in
                #expect(value == nil)
                probe.events.append("optional")
            }.declaration,
            UnwindHandler(LoginRoute.self) { probe.events.append("payload-free") }.declaration,
        ])
        await root.present(LoginRoute())
        var source = try #require(engine.defaultSpace.rootPath.last)
        #expect(await Router(engine: engine, scope: source).unwind(to: .topmostAncestor, payload: Optional<String>.none))
        await root.present(LoginRoute())
        source = try #require(engine.defaultSpace.rootPath.last)
        #expect(await Router(engine: engine, scope: source).unwind(to: .topmostAncestor))
        #expect(probe.events == ["optional", "payload-free"])
    }

    @Test(arguments: [false, true])
    func duplicatePayloadKeyDisablesOnlyThatKeyAndRecovers(reverse: Bool) async throws {
        let engine = RouterEngine(routes: RootRouteMap { Sheet(LoginRoute.self) { _, _ in EmptyView() } })
        let root = Router(engine: engine, scope: engine.root)
        let probe = HookBindingProbe()
        engine.root.installHookDeclarations(sourceID: "int", hookDeclarations: [
            UnwindHandler(LoginRoute.self, expecting: Int.self) { probe.events.append("int:\($0)") }.declaration,
        ])
        for source in reverse ? ["second", "first"] : ["first", "second"] {
            engine.root.installHookDeclarations(sourceID: source, hookDeclarations: [
                UnwindHandler(LoginRoute.self, expecting: String.self) { probe.events.append("\(source):\($0)") }.declaration,
            ])
        }
        let key = HookDeclarationIdentity.unwindHandler(ObjectIdentifier(LoginRoute.self), payload: ObjectIdentifier(String.self))
        guard case .conflict? = engine.root.hookBinding(for: key, in: engine.spaces) else {
            Issue.record("Only the duplicate route/payload pair should conflict")
            return
        }
        for payload in ["blocked", 7] as [Any] {
            await root.present(LoginRoute())
            let source = try #require(engine.defaultSpace.rootPath.last)
            #expect(await Router(engine: engine, scope: source).unwind(to: .topmostAncestor, payload: payload))
        }
        #expect(probe.events == ["int:7"])
        engine.root.uninstallHookDeclarations(sourceID: "second")
        await root.present(LoginRoute())
        let source = try #require(engine.defaultSpace.rootPath.last)
        #expect(await Router(engine: engine, scope: source).unwind(to: .topmostAncestor, payload: "restored"))
        #expect(probe.events == ["int:7", "first:restored"])
    }

    @Test func aDifferentPayloadKeyDoesNotShadowAnAncestorOrHideItsOwnConflict() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(LoginRoute.self) { _, _ in EmptyView() } routes: {
                Sheet(SettingsRoute.self) { _, _ in EmptyView() }
            }
        })
        let root = Router(engine: engine, scope: engine.root)
        let probe = HookBindingProbe()
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: String.self) { probe.events.append("ancestor:\($0)") }.declaration,
        ])
        await root.present(LoginRoute())
        let landing = try #require(engine.defaultSpace.rootPath.last)
        landing.installHookDeclarations(sourceID: "int", hookDeclarations: [
            UnwindHandler(SettingsRoute.self, expecting: Int.self) { probe.events.append("int:\($0)") }.declaration,
        ])
        let landingRouter = Router(engine: engine, scope: landing)
        await landingRouter.present(SettingsRoute())
        var source = try #require(engine.defaultSpace.rootPath.last)
        #expect(await Router(engine: engine, scope: source).unwind(to: .topmostAncestor, payload: "found"))
        #expect(probe.events == ["ancestor:found"])
        let string = UnwindHandler(SettingsRoute.self, expecting: String.self) { probe.events.append("local:\($0)") }.declaration
        landing.installHookDeclarations(sourceID: "duplicate", hookDeclarations: [string, string])
        await landingRouter.present(SettingsRoute())
        source = try #require(engine.defaultSpace.rootPath.last)
        #expect(await Router(engine: engine, scope: source).unwind(to: .topmostAncestor, payload: "blocked"))
        #expect(probe.events == ["ancestor:found"])
    }

    @Test func compatiblePayloadTypesHaveNoMountOrderWinnerAndExactTypesTakePrecedence() async throws {
        let engine = RouterEngine()
        let probe = HookBindingProbe()
        let base = UnwindHandler(LoginRoute.self, expecting: HookPayloadBase.self) { _ in probe.events.append("base") }.declaration
        let tagged = UnwindHandler(LoginRoute.self, expecting: (any HookPayloadTag).self) { _ in probe.events.append("tagged") }.declaration
        let payload = HookPayloadChild()
        engine.root.installHookDeclarations(sourceID: "base", hookDeclarations: [base])
        let compatible = try #require(engine.root.unwindHandlerBinding(for: LoginRoute.self, payload: payload, in: engine.spaces)?.declaration)
        let baseHandler = try #require(compatible.unwindHandler(for: LoginRoute.self))
        await baseHandler.invoke(LoginRoute(), payload, engine.root.id)
        #expect(probe.events == ["base"])
        engine.root.installHookDeclarations(sourceID: "tagged", hookDeclarations: [tagged])
        guard case .conflict? = engine.root.unwindHandlerBinding(for: LoginRoute.self, payload: payload, in: engine.spaces) else {
            Issue.record("Overlapping casts must not choose a mount-order winner")
            return
        }
        let exact = UnwindHandler(LoginRoute.self, expecting: HookPayloadChild.self) { _ in probe.events.append("exact") }.declaration
        engine.root.installHookDeclarations(sourceID: "exact", hookDeclarations: [exact])
        let selected = try #require(engine.root.unwindHandlerBinding(for: LoginRoute.self, payload: payload, in: engine.spaces)?.declaration)
        let exactHandler = try #require(selected.unwindHandler(for: LoginRoute.self))
        await exactHandler.invoke(LoginRoute(), payload, engine.root.id)
        #expect(probe.events == ["base", "exact"])
        #expect(engine.root.unwindHandlerBinding(for: LoginRoute.self, payload: nil, in: engine.spaces) == nil)
    }

    @Test func separateSourcesHandleActionsAndUnwindsTogether() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() })
        })
        let router = Router(engine: engine, scope: engine.root)
        let probe = HookBindingProbe()
        engine.root.installHookDeclarations(sourceID: "actions", hookDeclarations: [
            ActionInterceptor(HookBindingAction.self) { _ in probe.events.append("action") }.declaration,
        ])
        engine.root.installHookDeclarations(sourceID: "unwinds", hookDeclarations: [
            UnwindHandler(LoginRoute.self) { probe.events.append("unwind") }.declaration,
        ])

        await router.perform(HookBindingAction(probe: probe))
        await router.present(LoginRoute())
        let source = try #require(engine.defaultSpace.rootPath.last)
        #expect(await Router(engine: engine, scope: source).unwind(to: .topmostAncestor))
        #expect(probe.events == ["action", "unwind"])

        engine.root.installHookDeclarations(sourceID: "actions", hookDeclarations: [
            ActionInterceptor(HookBindingAction.self) { _ in probe.events.append("updated") }.declaration,
        ])
        await router.perform(HookBindingAction(probe: probe))
        engine.root.uninstallHookDeclarations(sourceID: "actions")
        await router.perform(HookBindingAction(probe: probe))
        await router.present(LoginRoute())
        let second = try #require(engine.defaultSpace.rootPath.last)
        #expect(await Router(engine: engine, scope: second).unwind(to: .topmostAncestor))
        #expect(probe.events == ["action", "unwind", "updated", "body", "unwind"])
    }

    @Test(arguments: [false, true])
    func conflictingInterceptorsDoNotChooseAMountOrderWinner(reverse: Bool) async {
        let engine = RouterEngine()
        let router = Router(engine: engine, scope: engine.root)
        let probe = HookBindingProbe()
        let sources = reverse ? ["second", "first"] : ["first", "second"]
        for source in sources {
            engine.root.installHookDeclarations(sourceID: AnyHashable(source), hookDeclarations: [
                ActionInterceptor(HookBindingAction.self) { _ in probe.events.append(source) }.declaration,
            ])
        }
        engine.root.installHookDeclarations(sourceID: "distinct", hookDeclarations: [
            ActionInterceptor(ContextProbeAction.self) { _ in probe.events.append("distinct") }.declaration,
        ])

        await router.perform(HookBindingAction(probe: probe))
        await router.perform(ContextProbeAction())
        #expect(probe.events == ["distinct"])

        engine.root.uninstallHookDeclarations(sourceID: "second")
        await router.perform(HookBindingAction(probe: probe))
        #expect(probe.events == ["distinct", "first"])
    }

    @Test func updatingOneSourceRemovesOnlyItsOldKeys() async {
        let engine = RouterEngine()
        let router = Router(engine: engine, scope: engine.root)
        let probe = HookBindingProbe()
        let first = ActionInterceptor(HookBindingAction.self) { _ in probe.events.append("first") }.declaration
        engine.root.installHookDeclarations(sourceID: "first", hookDeclarations: [first])
        engine.root.installHookDeclarations(sourceID: "second", hookDeclarations: [
            ActionInterceptor(ContextProbeAction.self) { _ in probe.events.append("second") }.declaration,
        ])
        engine.root.installHookDeclarations(sourceID: "first", hookDeclarations: [])
        await router.perform(HookBindingAction(probe: probe))
        await router.perform(ContextProbeAction())
        #expect(probe.events == ["body", "second"])
    }

    @Test func duplicatesWithinOneSourceAreConflictsAndCanBeCorrected() async {
        let engine = RouterEngine()
        let router = Router(engine: engine, scope: engine.root)
        let probe = HookBindingProbe()
        let hook = ActionInterceptor(HookBindingAction.self) { _ in probe.events.append("unique") }.declaration
        engine.root.installHookDeclarations(hookDeclarations: [hook, hook])
        await router.perform(HookBindingAction(probe: probe))
        #expect(probe.events.isEmpty)
        engine.root.installHookDeclarations(hookDeclarations: [hook])
        await router.perform(HookBindingAction(probe: probe))
        #expect(probe.events == ["unique"])
    }

    @Test func conflictingUnwindHandlersDoNotFallBackToAnAncestor() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
                Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
            }
        })
        let root = Router(engine: engine, scope: engine.root)
        let probe = HookBindingProbe()
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(SettingsRoute.self) { probe.events.append("ancestor") }.declaration,
        ])
        await root.present(LoginRoute())
        let receiver = try #require(engine.defaultSpace.rootPath.last)
        let receiverRouter = Router(engine: engine, scope: receiver)
        for source in ["first", "second"] {
            receiver.installHookDeclarations(sourceID: AnyHashable(source), hookDeclarations: [
                UnwindHandler(SettingsRoute.self) { probe.events.append(source) }.declaration,
            ])
        }
        await receiverRouter.present(SettingsRoute())
        let source = try #require(engine.defaultSpace.rootPath.last)
        #expect(await Router(engine: engine, scope: source).unwind(to: .topmostAncestor))
        #expect(probe.events.isEmpty)

        receiver.uninstallHookDeclarations(sourceID: "second")
        await receiverRouter.present(SettingsRoute())
        let second = try #require(engine.defaultSpace.rootPath.last)
        #expect(await Router(engine: engine, scope: second).unwind(to: .topmostAncestor))
        #expect(probe.events == ["first"])
    }

    @Test func outgoingViewsLoseHooksAtCommitBeforeNativeTeardown() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
                Branches { Branch("tab") {} }
            }
        })
        let root = Router(engine: engine, scope: engine.root)
        let probe = HookBindingProbe()
        engine.root.installHookDeclarations(hookDeclarations: [
            UnwindHandler(LoginRoute.self) { probe.events.append("surviving") }.declaration,
        ])
        await root.present(LoginRoute())
        let source = try #require(engine.defaultSpace.rootPath.last)
        let branch = try #require(source.branchScopes["tab"])
        let snapshot = RouteDestinationSnapshot(route: .init(scope: source))
        let sourceRouter = Router(engine: engine, scope: source)
        let hook = ActionInterceptor(HookBindingAction.self) { _ in probe.events.append("outgoing") }.declaration
        source.installHookDeclarations(hookDeclarations: [hook])
        branch.installHookDeclarations(hookDeclarations: [hook])
        engine.routeScopeDidInstallInView(source)

        let unwind = Task { await sourceRouter.unwind(to: .topmostAncestor) }
        for _ in 0..<1000 where source.belongs(to: engine.defaultSpace) { await Task.yield() }
        #expect(!source.belongs(to: engine.defaultSpace))
        #expect(source.isInstalledInView)
        #expect(snapshot.route.scope === source)
        #expect(source.branchScopes["tab"] === branch)
        let key = HookDeclarationIdentity.actionInterceptor(ObjectIdentifier(HookBindingAction.self))
        #expect(source.hookBinding(for: key, in: engine.spaces) == nil)
        #expect(branch.hookBinding(for: key, in: engine.spaces) == nil)

        // A late update from the retained outgoing view cannot restore eligibility.
        source.installHookDeclarations(hookDeclarations: [hook])
        await sourceRouter.perform(HookBindingAction(probe: probe))
        #expect(probe.events == ["surviving"])
        engine.routeScopeDidLeaveView(source)
        #expect(await unwind.value)
    }

    @Test func removingAnElevatedSpaceInvalidatesHooksWhileItsObjectsRemainAlive() async throws {
        let engine = RouterEngine(routes: RootRouteMap {} highPriority: {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() })
        })
        await Router(engine: engine, scope: engine.root).present(LoginRoute())
        let space = try #require(engine.spaces.highSpace)
        let source = space.root
        let router = Router(engine: engine, scope: source)
        let probe = HookBindingProbe()
        source.installHookDeclarations(hookDeclarations: [
            ActionInterceptor(HookBindingAction.self) { _ in probe.events.append("outgoing") }.declaration,
        ])
        engine.routeScopeDidInstallInView(source)
        let dismissal = Task { await router.dismissSpace() }
        for _ in 0..<1000 where engine.spaces.highSpace != nil { await Task.yield() }
        #expect(engine.spaces.highSpace == nil)
        #expect(source.isInstalledInView)
        #expect(source.belongs(to: space))
        let key = HookDeclarationIdentity.actionInterceptor(ObjectIdentifier(HookBindingAction.self))
        #expect(source.hookBinding(for: key, in: engine.spaces) == nil)
        await router.perform(HookBindingAction(probe: probe))
        #expect(probe.events.isEmpty)
        engine.routeScopeDidLeaveView(source)
        #expect(await dismissal.value)
    }

    @Test func deferredInvocationCannotRetargetASurvivingBranch() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches {
                Branch("tab") { Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) }
            }
        })
        let branch = try #require(engine.root.branchScopes["tab"])
        engine.routeScopeDidInstallInView(branch)
        let router = Router(engine: engine, scope: engine.root).branch("tab")
        await router.present(LoginRoute())
        let source = try #require(branch.path.last)
        let probe = HookBindingProbe()
        source.installHookDeclarations(hookDeclarations: [
            ActionInterceptor(HookBindingAction.self) { invocation in probe.invocation = invocation }.declaration,
        ])
        await router.perform(HookBindingAction(probe: probe))
        let invocation = try #require(probe.invocation)
        probe.invocation = nil
        #expect(await Router(engine: engine, scope: source).unwind(to: .topmostAncestor))
        #expect(branch.path.isEmpty)
        do {
            try await invocation()
            Issue.record("An invocation from the outgoing destination ran in its surviving branch.")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(probe.events.isEmpty)
    }

    @Test func interceptedRerouteStillWaitsForDestinationAndInterceptsTheRetry() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() })
        })
        let probe = HookBindingProbe()
        engine.root.installHookDeclarations(hookDeclarations: [
            ActionInterceptor(HookReroutingAction.self) { invocation in
                probe.events.append("source")
                try? await invocation()
            }.declaration,
        ])
        await Router(engine: engine, scope: engine.root).perform(HookReroutingAction(probe: probe))
        for _ in 0..<1000 where engine.defaultSpace.rootPath.last == nil { await Task.yield() }
        let destination = try #require(engine.defaultSpace.rootPath.last)
        #expect(probe.events == ["source", "reroute"])
        destination.installHookDeclarations(hookDeclarations: [
            ActionInterceptor(HookReroutingAction.self) { invocation in
                probe.events.append("destination")
                try? await invocation()
            }.declaration,
        ])
        await Task.yield()
        #expect(probe.events == ["source", "reroute"])
        engine.routeScopeDidInstallInView(destination)
        for _ in 0..<1000 where probe.events.count < 4 { await Task.yield() }
        #expect(probe.events == ["source", "reroute", "destination", "body"])
    }
}

private protocol HookPayloadTag {}
private class HookPayloadBase {}
private final class HookPayloadChild: HookPayloadBase, HookPayloadTag {}

@MainActor
private final class HookBindingProbe {
    var events: [String] = []
    var invocation: ActionInvocation<Void>?
}

@MainActor
private struct HookBindingAction: Action {
    let probe: HookBindingProbe

    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        probe.events.append("body")
    }
}

@MainActor
private struct HookReroutingAction: Action {
    let probe: HookBindingProbe

    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        guard context.isRunning(in: LoginRoute.self) else {
            probe.events.append("reroute")
            throw .reroute(LoginRoute())
        }
        probe.events.append("body")
    }
}
