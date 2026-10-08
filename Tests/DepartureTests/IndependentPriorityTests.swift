import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct IndependentPriorityTests {
    @Test func entryIsTheNavigationRootAndOuterPresentationDoesNotAdvanceXY() async throws {
        let owner = fixture()
        await owner.current.present(HighEntry(value: 1))
        let space = try #require(owner.engine.spaces.highSpace)
        #expect(space.root.route is HighEntry)
        #expect(space.rootPath.isEmpty)
        #expect(space.root.pathDepth == 0)
        #expect(space.root.lane.depth == 0)
        #expect(space.root.previousScopeInSpace == nil)
        await owner.current.present(HighPush())
        await owner.current.present(HighModal())
        #expect(space.rootPath.scopes.map(\.pathDepth) == [1, 2])
        #expect(space.rootPath.last?.lane.depth == 1)
        #expect(space.root.lane.modal === space.rootPath.last)
    }

    @Test func resetKeepsTheEntryAndOtherSpacesUntouched() async throws {
        let owner = fixture()
        await owner.current.present(NormalPush())
        let normal = try #require(owner.engine.normalSpace.rootPath.last)
        await owner.current.present(HighEntry(value: 1))
        let high = try #require(owner.engine.spaces.highSpace)
        await owner.current.present(HighPush())
        #expect(await owner.current.unwind(to: .root))
        #expect(owner.engine.spaces.highSpace === high)
        #expect(high.rootPath.isEmpty)
        #expect(owner.engine.normalSpace.rootPath.last === normal)
        #expect(!((await owner.current.unwind(to: .root))))
        #expect(await owner.current.unwind(to: .topmostAncestor))
        #expect(owner.engine.spaces.highSpace == nil)
        #expect(owner.engine.normalSpace.rootPath.last === normal)
    }

    @Test func coveredRoutersCannotNavigateEvenToHigherPriorityOrThroughNativeBindings() async throws {
        let owner = fixture()
        let normal = owner.current
        await normal.present(NormalPush())
        let normalPush = owner.current
        let normalBinding = owner.engine.routePresentationBinding(from: owner.engine.root, matching: .push)
        await normalPush.present(HighEntry(value: 1))
        let high = try #require(owner.engine.spaces.highSpace)
        let highRouter = owner.current
        await highRouter.present(HighPush())
        let highBinding = owner.engine.elevatedRoutePresentationBinding(priority: .high, matching: .sheet)
        await normal.present(CriticalEntry())
        await normalPush.present(NormalPush())
        #expect(!((await normalPush.unwind(to: .root))))
        #expect(!((await normalPush.dismissSpace())))
        normalBinding.wrappedValue = nil
        #expect(owner.engine.normalSpace.rootPath.count == 1)
        #expect(owner.engine.spaces.criticalSpace == nil)
        await owner.current.present(CriticalEntry())
        let critical = try #require(owner.engine.spaces.criticalSpace)
        await highRouter.present(HighEntry(value: 2))
        await highRouter.present(HighPush())
        #expect(!((await highRouter.unwind(to: .root))))
        #expect(!((await highRouter.dismissSpace())))
        highBinding.wrappedValue = nil
        #expect(owner.engine.spaces.highSpace === high)
        #expect(high.rootPath.count == 1)
        #expect(owner.engine.spaces.criticalSpace === critical)
    }

    @Test func ownerCanRemoveCoveredSpaceAndCapturedRoutersStayInactive() async throws {
        let owner = fixture()
        await owner.current.present(HighEntry(value: 1))
        let highRouter = owner.current
        await owner.current.present(HighPush())
        let high = try #require(owner.engine.spaces.highSpace)
        await owner.current.present(CriticalEntry())
        let critical = try #require(owner.engine.spaces.criticalSpace)
        #expect(await owner.dismissSpace(.high))
        #expect(owner.engine.spaces.highSpace == nil)
        #expect(owner.engine.spaces.criticalSpace === critical)
        #expect(high.rootPath.count == 1) // Outgoing ownership, never a live path.
        await highRouter.present(HighPush())
        #expect(!((await highRouter.dismissSpace())))
        #expect(await owner.dismissSpaces())
        #expect(owner.engine.spaces.activeSpace === owner.engine.normalSpace)
        #expect(!((await owner.dismissSpace(.normal))))
        #expect(!((await owner.dismissSpaces())))
    }

    @Test func entryReuseResetsOnlyItsOwnRootAndReplacementCreatesANewInstance() async throws {
        let owner = fixture()
        await owner.current.present(HighEntry(value: 1))
        let first = try #require(owner.engine.spaces.highSpace)
        let oldBinding = owner.engine.elevatedRoutePresentationBinding(priority: .high, matching: .sheet)
        await owner.current.present(HighPush())
        await owner.current.present(HighEntry(value: 1))
        #expect(owner.engine.spaces.highSpace === first)
        #expect(first.rootPath.isEmpty)
        await owner.current.present(HighEntry(value: 2))
        let second = try #require(owner.engine.spaces.highSpace)
        #expect(second !== first)
        oldBinding.wrappedValue = nil
        owner.engine.clearElevatedSpaceIfNeeded(forRemovedViewScope: first.root)
        #expect(owner.engine.spaces.highSpace === second)
    }

    @Test func localDefinitionsAndUnwindIDsDoNotFallBackToCoveredSpaces() async throws {
        let owner = fixture()
        await owner.current.present(NormalPush())
        await owner.current.present(HighEntry(value: 1))
        let high = try #require(owner.engine.spaces.highSpace)
        await owner.current.present(NormalOnlyModal())
        #expect(high.rootPath.isEmpty)
        #expect(!((await owner.current.unwind(to: .id("normal-root")))))
        #expect(owner.engine.normalSpace.rootPath.count == 1)
    }

    @Test func removalThenNormalPresentationUsesTheSurvivingSource() async throws {
        let owner = fixture()
        let normal = owner.current
        await normal.present(HighEntry(value: 1))
        let removed = owner.current
        #expect(await owner.dismissSpace(.high))
        await normal.present(NormalPush())
        #expect(owner.engine.normalSpace.rootPath.count == 1)
        await removed.present(NormalPush())
        #expect(owner.engine.normalSpace.rootPath.count == 1)
    }

    @Test func suspendedResolutionCannotCommitAfterItsSourceBecomesCovered() async {
        let owner = fixture()
        let source = owner.current
        let gate = SpaceResolutionGate()
        let request = Task { await source.present(SuspendedNormal(gate: gate)) }
        await gate.waitForStart()
        await source.present(HighEntry(value: 1))
        gate.release()
        await request.value
        #expect(owner.engine.normalSpace.rootPath.isEmpty)
        #expect(owner.engine.spaces.highSpace?.root.route is HighEntry)
    }

    @Test func eligibleFollowUpWaitsForGlobalRemovalCompletion() async throws {
        let owner = fixture()
        let surviving = owner.current
        await surviving.present(HighEntry(value: 1))
        let high = try #require(owner.engine.spaces.highSpace)
        let removed = owner.current
        let hostID = UUID()
        owner.engine.hostDidAttach(high.root, view: nil, id: hostID)
        let removal = Task { await owner.dismissSpace(.high) }
        for _ in 0..<1000 where owner.engine.spaces.highSpace != nil { await Task.yield() }
        #expect(owner.engine.spaces.highSpace == nil)
        #expect(owner.engine.isNavigating)
        await removed.present(CriticalEntry())
        let followUp = Task { await surviving.present(NormalPush()) }
        for _ in 0..<1000 where owner.engine.pendingRoute == nil { await Task.yield() }
        #expect(owner.engine.pendingRoute != nil)
        #expect(owner.engine.normalSpace.rootPath.isEmpty)
        owner.engine.hostDidDetach(high.root, id: hostID)
        #expect(await removal.value)
        await followUp.value
        #expect(owner.engine.normalSpace.rootPath.count == 1)
        #expect(!owner.engine.isNavigating)
        #expect(owner.engine.spaces.criticalSpace == nil)
    }

    @Test func branchedEntryResetKeepsOnlyRootOwnedInactiveHistoryAndCoveredSelectionIsRejected() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {} highPriority: {
            Sheet(RouteDestination(HighEntry.self) { _, _ in EmptyView() }) {
                Branches {
                    Branch("main") { Push(RouteDestination(HighPush.self) { _, _ in EmptyView() }) }
                    Branch("other") { Push(RouteDestination(HighModal.self) { _, _ in EmptyView() }) }
                }
            }
        } criticalPriority: {
            Cover(RouteDestination(CriticalEntry.self) { _, _ in EmptyView() })
        }, router: owner) { EmptyView() }
        await owner.current.present(HighEntry(value: 1))
        let high = try #require(owner.engine.spaces.highSpace)
        let rootRouter = owner.current
        let selection = SpaceBranchSelection()
        let binding = AnyRouteBranchSelection(Binding(get: { selection.value }, set: { selection.value = $0 }))
        owner.engine.bindBranchSelection(binding, in: high.root)
        await rootRouter.branch("other").present(HighModal())
        for _ in 0..<1000 where owner.engine.pendingRoute != nil { await Task.yield() }
        let other = try #require(high.root.branchScopes["other"])
        let inactivePush = try #require(other.path.last)
        await rootRouter.branch("main").present(HighPush())
        for _ in 0..<1000 where owner.engine.pendingRoute != nil { await Task.yield() }
        #expect(await owner.current.unwind(to: .root))
        #expect(high.root.branchScopes["main"]?.path.isEmpty == true)
        #expect(other.path.last === inactivePush)
        await owner.current.present(CriticalEntry())
        selection.value = "other"
        owner.engine.bindBranchSelection(binding, in: high.root)
        #expect(selection.value == "main")
        #expect(high.root.activeBranch == AnyHashable("main"))
        await rootRouter.branch("other").present(HighModal())
        #expect(high.root.activeBranch == AnyHashable("main"))
        #expect(other.path.last === inactivePush)
        #expect(await owner.dismissSpace(.critical))
        #expect(await rootRouter.dismissSpace())
        #expect(owner.engine.spaces.routePath(containing: other) == nil)
    }

    private func fixture() -> RootRouter {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap(id: "normal-root") {
            Push(RouteDestination(SuspendedNormal.self) { _, _ in EmptyView() })
            Push(RouteDestination(NormalPush.self) { _, _ in EmptyView() }) {
                Sheet(RouteDestination(NormalOnlyModal.self) { _, _ in EmptyView() })
            }
        } highPriority: {
            Sheet(RouteDestination(HighEntry.self) { _, _ in EmptyView() }) {
                Push(RouteDestination(HighPush.self) { _, _ in EmptyView() })
                Sheet(RouteDestination(HighModal.self) { _, _ in EmptyView() })
            }
        } criticalPriority: {
            Cover(RouteDestination(CriticalEntry.self) { _, _ in EmptyView() })
        }, router: owner) { EmptyView() }
        return owner
    }
}

private struct NormalPush: Route, Equatable {}
private struct NormalOnlyModal: Route, Equatable {}
private struct HighEntry: Route, Equatable { let value: Int }
private struct HighPush: Route, Equatable {}
private struct HighModal: Route, Equatable {}
private struct CriticalEntry: Route, Equatable {}

@MainActor
private final class SpaceResolutionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation {
            continuation = $0
            startWaiter?.resume()
            startWaiter = nil
        }
    }
    func waitForStart() async {
        if continuation != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
private struct SuspendedNormal: Route {
    let gate: SpaceResolutionGate
    func resolveRoute() async -> RouteResolution { await gate.wait(); return .allow }
}
@MainActor
private final class SpaceBranchSelection { var value = "main" }
