import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite struct BranchSelectionTests {
    @Test(arguments: [false, true])
    func duplicateOwnersDisableSelectionUntilOneRemains(removeFirst: Bool) async throws {
        let engine = fixture()
        let first = Selection("first"), second = Selection("second")
        let firstOwner = RoutePresentationHostID(), secondOwner = RoutePresentationHostID()
        bind(first, owner: firstOwner, in: engine)
        bind(second, owner: secondOwner, in: engine)
        #expect(engine.root.hasConflictingBranchSelection)
        #expect(first.value == "first")
        #expect(second.value == "first")

        let router = Router(engine: engine, scope: engine.root)
        await router.branch("second").present(Second())
        #expect(engine.root.activeBranch == AnyHashable("first"))
        #expect(engine.root.branchScopes.values.allSatisfy { $0.path.isEmpty })
        #expect(engine.pendingRoute == nil)

        // A native write cannot choose a winner while configuration is ambiguous.
        second.value = "second"
        engine.synchronizeBranchSelection(ownedBy: secondOwner, in: engine.root)
        #expect(second.value == "first")
        engine.root.unbindRoutingHost(removeFirst ? firstOwner : secondOwner)
        #expect(!engine.root.hasConflictingBranchSelection)
        await router.branch("second").present(Second())
        #expect(engine.root.branchScopes["second"]?.path.last?.route is Second)
        #expect((removeFirst ? second : first).value == "second")
        #expect((removeFirst ? first : second).value == "first")
    }

    @Test func refreshingOneOwnerReplacesItsCallbackWithoutCreatingAConflict() async {
        let engine = fixture()
        let owner = RoutePresentationHostID()
        let original = Selection("second"), refreshed = Selection("second")
        bind(original, owner: owner, in: engine)
        bind(refreshed, owner: owner, in: engine)
        #expect(!engine.root.hasConflictingBranchSelection)
        await Router(engine: engine, scope: engine.root).branch("first").present(First())
        #expect(refreshed.value == "first")
        #expect(original.value == "second")
    }

    @Test func plainRoutingHostsDoNotCompeteForSelectionOwnership() async {
        let engine = fixture()
        let selection = Selection("first")
        bind(selection, owner: RoutePresentationHostID(), in: engine)
        engine.root.bindRoutingHost(RoutePresentationHostID(), automatic: true, environment: engine.root.sourceEnvironment)
        engine.root.bindRoutingHost(RoutePresentationHostID(), automatic: false, environment: engine.root.sourceEnvironment)
        #expect(!engine.root.hasConflictingBranchSelection)
        await Router(engine: engine, scope: engine.root).branch("second").present(Second())
        #expect(selection.value == "second")
    }

    @Test func detachingSelectionOwnerRetainsModelSelectionAndReleasesItsCallback() async {
        let engine = fixture()
        let selection = Selection("first")
        let owner = RoutePresentationHostID()
        bind(selection, owner: owner, in: engine)
        engine.root.unbindRoutingHost(owner)
        await Router(engine: engine, scope: engine.root).branch("second").present(Second())
        #expect(engine.root.activeBranch == AnyHashable("second"))
        #expect(selection.value == "first")
        #expect(engine.root.branchSelection == nil)
    }

    @Test func mismatchedBindingRejectsActivationWithoutChangingThePath() async {
        let engine = fixture()
        var selection = 0
        let owner = RoutePresentationHostID()
        engine.root.bindRoutingHost(owner, automatic: false, environment: engine.root.sourceEnvironment,
            selection: AnyRouteBranchSelection(Binding(get: { selection }, set: { selection = $0 })))
        engine.synchronizeBranchSelection(ownedBy: owner, in: engine.root)
        await Router(engine: engine, scope: engine.root).branch("second").present(Second())
        #expect(selection == 0)
        #expect(engine.root.activeBranch == AnyHashable(0))
        #expect(engine.root.branchScopes.values.allSatisfy { $0.path.isEmpty })
        #expect(engine.pendingRoute == nil)
    }

    @Test func optionalSelectionCanRepresentNonoptionalBranchValues() {
        var selection: String? = "first"
        let erased = AnyRouteBranchSelection(Binding(get: { selection }, set: { selection = $0 }))
        #expect(erased.setValue("second"))
        #expect(selection == "second")
    }

    @Test func outgoingSelectionOwnersCannotWriteBindingsAfterTheirScopeLeavesTheTree() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() }) {
                Branches { Branch("first") {}; Branch("second") {} }
            }
        })
        await engine.present(LoginRoute())
        let outgoing = try #require(engine.defaultSpace.rootPath.last)
        let selection = Selection("first"), duplicate = Selection("first")
        let owner = RoutePresentationHostID()
        bind(selection, owner: owner, in: engine, scope: outgoing)
        bind(duplicate, owner: RoutePresentationHostID(), in: engine, scope: outgoing)
        #expect(await engine.unwind(to: .root))
        selection.value = "second"
        duplicate.value = "second"
        engine.synchronizeBranchSelection(ownedBy: owner, in: outgoing)
        engine.restoreBranchSelection(in: outgoing)
        #expect(selection.value == "second")
        #expect(duplicate.value == "second")
        #expect(outgoing.activeBranch == AnyHashable("first"))
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }

    private func fixture() -> RouterEngine {
        RouterEngine(routes: RootRouteMap {
            Branches(concurrent: true) {
                Branch("first") { Push(RouteDestination(First.self) { _, _ in EmptyView() }) }
                Branch("second") { Push(RouteDestination(Second.self) { _, _ in EmptyView() }) }
            }
        })
    }

    private func bind(_ selection: Selection, owner: RoutePresentationHostID, in engine: RouterEngine, scope: RouteScope? = nil) {
        let scope = scope ?? engine.root
        scope.bindRoutingHost(owner, automatic: false, environment: scope.sourceEnvironment,
            selection: AnyRouteBranchSelection(Binding(get: { selection.value }, set: { selection.value = $0 })))
        engine.synchronizeBranchSelection(ownedBy: owner, in: scope)
    }
}

@MainActor private final class Selection {
    var value: String
    init(_ value: String) { self.value = value }
}
private struct First: Route, Equatable {}
private struct Second: Route, Equatable {}
