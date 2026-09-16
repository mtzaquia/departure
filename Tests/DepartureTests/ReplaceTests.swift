//
//  Copyright (c) 2026 @mtzaquia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Observation
import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ReplaceTests {
    @Test func declarationIsInlineAndNormalPriority() {
        let declaration = Replace(SelectedRoute.self)._routeDeclarations[0]
        #expect(declaration.presentationKind == .replace)
        #expect(!declaration.presentationKind.isModal)
        #expect(declaration.priority == .normal)
        #expect(!declaration.providesNavigation)
        #expect(Branch("wallet") { Replace(SelectedRoute.self) }
            .routeScopeDeclarations[0].routes[0].drivesPresentation == false)
    }

    @Test(arguments: [true, false], [true, false])
    func selectionActivatesAndResumesOnLazyHost(concurrent: Bool, explicit: Bool) async {
        let fixture = ReplaceFixture(concurrent: concurrent, mounted: false)
        let source = explicit ? fixture.router.branch("wallet") : fixture.local(fixture.sidebar)
        await source.present(SelectedRoute(number: 1))
        #expect(fixture.selection.value == "wallet")
        #expect(fixture.engine.pendingRoute != nil)
        #expect(fixture.engine.normalTree.rootPath.isEmpty)
        fixture.mountWallet()
        fixture.engine.resumePendingRoute(for: "wallet", in: fixture.engine.root)
        #expect(fixture.wallet.path.first?.route as? SelectedRoute == SelectedRoute(number: 1))
        #expect(fixture.engine.pendingRoute == nil)
        #expect(fixture.engine.routePresentation(from: fixture.wallet, matching: .replace) != nil)
        #expect(fixture.engine.routePresentation(from: fixture.wallet, matching: .push) == nil)
    }

    @Test func replacementClearsDescendantsAndPreservesAnotherColumn() async throws {
        let fixture = ReplaceFixture()
        await fixture.local(fixture.sidebar).present(SiblingRoute())
        let sibling = try #require(fixture.sidebar.path.first)
        await fixture.router.branch("wallet").present(SelectedRoute(number: 1))
        let previous = try #require(fixture.wallet.path.first)
        fixture.installChildren(on: previous)
        await fixture.local(previous).present(ChildRoute())
        await fixture.local(previous).present(OverlayRoute())
        #expect(fixture.wallet.path.count == 3)
        await fixture.router.branch("wallet").present(SelectedRoute(number: 2))
        #expect(fixture.wallet.path.count == 1)
        #expect(fixture.wallet.path.first?.route as? SelectedRoute == SelectedRoute(number: 2))
        #expect(fixture.sidebar.path.first === sibling)
        #expect(fixture.engine.normalTree.modalScopes().isEmpty)
        #expect(fixture.engine.routePhase(for: sibling) == .active)
        #expect(await fixture.local(previous).unwind(to: .root) == false)
    }

    @Test func equivalentSelectionKeepsIdentityAndClearsItsChildPath() async throws {
        let fixture = ReplaceFixture()
        await fixture.router.branch("wallet").present(SelectedRoute(number: 1))
        let selected = try #require(fixture.wallet.path.first)
        fixture.installChildren(on: selected)
        await fixture.local(selected).present(ChildRoute())
        await fixture.router.branch("wallet").present(SelectedRoute(number: 1))
        #expect(fixture.wallet.path.count == 1)
        #expect(fixture.wallet.path.first === selected)
    }

    @Test func equalPushedRouteDoesNotSubstituteForTheSelectedSlot() async throws {
        let fixture = ReplaceFixture()
        let pushed = RouteScope(id: "pushed-equal", route: SelectedRoute(number: 1))
        pushed.attachPresentation(to: fixture.wallet,
            declaration: Push(SelectedRoute.self)._routeDeclarations[0])
        fixture.engine.mutateRouteGraph { fixture.wallet.path.append(pushed) }
        await fixture.router.branch("wallet").present(SelectedRoute(number: 1))
        let selected = try #require(fixture.wallet.path.first)
        #expect(selected !== pushed)
        #expect(selected.presentationDeclaration?.presentationKind == .replace)
        #expect(fixture.engine.routePresentation(from: fixture.wallet, matching: .push) == nil)
        #expect(fixture.engine.routePresentation(from: fixture.wallet, matching: .replace)?.scope === selected)
    }

    @Test func equalSelectionDoesNotReuseADepartedDeclarationHost() async throws {
        let fixture = ReplaceFixture()
        await fixture.router.branch("wallet").present(SelectedRoute(number: 1))
        let old = try #require(fixture.wallet.path.first)
        let newHostID = RoutePresentationHostID()
        fixture.engine.mutateRouteGraph {
            fixture.engine.root.registerBranchScope(fixture.wallet, for: "wallet",
                presentationHostID: newHostID)
        }
        await fixture.router.branch("wallet").present(SelectedRoute(number: 1))
        let selected = try #require(fixture.wallet.path.first)
        #expect(selected !== old)
        #expect(fixture.wallet.path.count == 1)
        #expect(fixture.engine.routePresentation(from: fixture.wallet, matching: .replace,
            hostedBy: newHostID)?.scope === selected)
    }

    @Test func childUnwindRetainsSelectionAndSelectionUnwindRestoresPlaceholder() async throws {
        let fixture = ReplaceFixture()
        await fixture.router.branch("wallet").present(SelectedRoute(number: 1))
        let selected = try #require(fixture.wallet.path.first)
        fixture.installChildren(on: selected)
        await fixture.local(selected).present(ChildRoute())
        let child = try #require(fixture.wallet.path.last)
        #expect(await fixture.local(child).unwind(to: .topmostAncestor))
        #expect(fixture.wallet.path.first === selected)
        #expect(await fixture.local(selected).unwind(to: .topmostAncestor))
        #expect(fixture.wallet.path.isEmpty)
        #expect(fixture.engine.routePresentation(from: fixture.wallet, matching: .replace) == nil)
    }

    @Test func replacementWaitsForInstalledSelectionAndLatestRequestWins() async throws {
        let fixture = ReplaceFixture()
        await fixture.router.branch("wallet").present(SelectedRoute(number: 1))
        let old = try #require(fixture.wallet.path.first)
        old.viewLifecycle.install()
        let first = Task { await fixture.router.branch("wallet").present(SelectedRoute(number: 2)) }
        while fixture.engine.pendingRoute == nil { await Task.yield() }
        #expect(fixture.wallet.path.isEmpty)
        let latest = Task { await fixture.router.branch("wallet").present(SelectedRoute(number: 3)) }
        while fixture.engine.pendingRoute?.route as? SelectedRoute != SelectedRoute(number: 3) {
            await Task.yield()
        }
        fixture.engine.routeScopeDidLeaveView(old)
        await first.value
        await latest.value
        #expect(fixture.wallet.path.count == 1)
        #expect(fixture.wallet.path.first?.route as? SelectedRoute == SelectedRoute(number: 3))
        #expect(fixture.engine.pendingRoute == nil)
    }

    @Test func selectionDoesNotOccupyTheSharedModalLane() async throws {
        let fixture = ReplaceFixture()
        await fixture.router.branch("wallet").present(SelectedRoute(number: 1))
        let selected = try #require(fixture.wallet.path.first)
        fixture.installChildren(on: selected)
        await fixture.local(selected).present(OverlayRoute())
        #expect(fixture.engine.normalTree.modalDepth(of: selected) == 0)
        #expect(fixture.engine.normalTree.modalScopes(atDepth: 1).count == 1)
        #expect(fixture.engine.normalTree.currentModalScope?.route is OverlayRoute)
        #expect(fixture.engine.routePresentation(from: fixture.wallet, matching: .replace)?.scope === selected)
    }

    @Test func normalReplacementIsBlockedByElevatedContextButWorksInsideIt() async throws {
        let fixture = ReplaceFixture()
        fixture.engine.root.installRouteDeclarations(sourceID: "elevated", id: nil,
            branchSelection: nil, routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(ElevatedRoute.self, priority: .high)._routeDeclarations),
            ])
        await fixture.local(fixture.sidebar).present(ElevatedRoute())
        let elevated = try #require(fixture.engine.routeForest.tree(for: .high)?.rootPath.first)
        await fixture.router.branch("wallet").present(SelectedRoute(number: 1))
        #expect(fixture.wallet.path.isEmpty)
        #expect(fixture.selection.value == "sidebar")
        elevated.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Replace(SelectedRoute.self)._routeDeclarations),
        ])
        await fixture.local(elevated).present(SelectedRoute(number: 1))
        #expect(fixture.engine.routeForest.tree(for: .high)?.rootPath.count == 2)
        #expect(fixture.engine.routeForest.tree(for: .high)?.modalScopes().count == 1)
        #expect(fixture.engine.routePresentation(from: elevated, matching: .replace) != nil)
    }

    @Test func localReplacementUsesItsDeclaringSlotAndHostProvenance() async throws {
        let fixture = ReplaceFixture()
        await fixture.local(fixture.sidebar).present(SiblingRoute())
        let container = try #require(fixture.sidebar.path.first)
        let hostID = RoutePresentationHostID()
        container.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Replace(SelectedRoute.self)._routeDeclarations.hosted(by: hostID)),
        ])
        await fixture.local(container).present(SelectedRoute(number: 1))
        await fixture.local(container).present(SelectedRoute(number: 2))
        #expect(fixture.sidebar.path.count == 2)
        #expect(fixture.sidebar.path.first === container)
        #expect(fixture.wallet.path.isEmpty)
        #expect(fixture.engine.routePresentation(from: container, matching: .replace,
            hostedBy: hostID)?.scope.route as? SelectedRoute == SelectedRoute(number: 2))
        #expect(fixture.engine.routePresentation(from: container, matching: .replace,
            hostedBy: RoutePresentationHostID()) == nil)
    }

    @Test func replacementClearsNestedBranchPathsAndDependentElevatedContexts() async throws {
        let fixture = ReplaceFixture()
        await fixture.router.branch("wallet").present(SelectedRoute(number: 1))
        let selected = try #require(fixture.wallet.path.first)
        selected.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations:
            Branch("nested") { Push(ChildRoute.self) }.routeScopeDeclarations
            + [RouteScopeDeclaration(routes: Cover(ElevatedRoute.self, priority: .high)._routeDeclarations)])
        let nested = RouteScope(id: "nested", route: nil)
        fixture.engine.mutateRouteGraph { selected.registerBranchScope(nested, for: "nested") }
        await fixture.local(nested).present(ChildRoute())
        let match = try #require(fixture.engine.routeForest.firstDeclaration(
            including: ElevatedRoute.self, origin: fixture.local(selected).origin))
        // Construct the context through the canonical elevated transition. A normal
        // replacement would be blocked while the high-priority context is active.
        await fixture.engine.replaceElevatedTree(.high, with: ElevatedRoute(), after: match)
        let plan = fixture.engine.routeForest.firstDeclaration(including: SelectedRoute.self,
            origin: fixture.router.branch("wallet").origin).map(fixture.engine.routeAppendUnwindPlan)
        fixture.engine.applyUnwindPlan(try #require(plan))
        #expect(nested.path.isEmpty)
        #expect(fixture.wallet.path.isEmpty)
        #expect(fixture.engine.routeForest.tree(for: .high) == nil)
    }
}

@MainActor
private struct ReplaceFixture {
    let router = Router()
    var engine: RouterEngine { router.engine! }
    let selection = ReplaceBranchSelection()
    let sidebar = RouteScope(id: "sidebar", route: nil)
    let wallet = RouteScope(id: "wallet", route: nil)

    init(concurrent: Bool = true, mounted: Bool = true) {
        @Bindable var selection = selection
        engine.root.installRouteDeclarations(id: nil,
            branchSelection: AnyRouteBranchSelection($selection.value, concurrent: concurrent),
            routeDeclarations: Branch("sidebar") { Push(SiblingRoute.self) }.routeScopeDeclarations
                + Branch("wallet") { Replace(SelectedRoute.self) }.routeScopeDeclarations)
        engine.mutateRouteGraph {
            engine.root.registerBranchScope(sidebar, for: "sidebar")
            if mounted { engine.root.registerBranchScope(wallet, for: "wallet") }
        }
    }

    func local(_ scope: RouteScope) -> Router { Router(engine: engine, scope: scope) }
    func mountWallet() { engine.mutateRouteGraph { engine.root.registerBranchScope(wallet, for: "wallet") } }
    func installChildren(on selected: RouteScope) {
        selected.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(ChildRoute.self)._routeDeclarations
                + Cover(OverlayRoute.self)._routeDeclarations),
        ])
    }
}

@MainActor
@Observable
private final class ReplaceBranchSelection { var value = "sidebar" }

private struct SelectedRoute: Route, Equatable {
    let number: Int
    func destination() -> some View { Text("Selected \(number)") }
}
private struct ChildRoute: Route { func destination() -> some View { Text("Child") } }
private struct SiblingRoute: Route { func destination() -> some View { Text("Sibling") } }
private struct OverlayRoute: Route { func destination() -> some View { Text("Overlay") } }
private struct ElevatedRoute: Route { func destination() -> some View { Text("Elevated") } }
