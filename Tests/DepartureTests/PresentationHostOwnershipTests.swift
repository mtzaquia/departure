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

import SwiftUI
import Testing
@testable import Departure

@MainActor
@Suite
struct PresentationHostOwnershipTests {
    @Test func localPushOwnsPresentationAndWriteBackAheadOfDistinctInheritedPush() async throws {
        let setup = makeBranchSetup(
            inherited: Push(TransactionRoute.self)._routeDeclarations,
            local: Push(SettingsRoute.self)._routeDeclarations
        )

        await setup.router.requestRoute(SettingsRoute())
        let presentedScope = try #require(setup.branchScope.path.last)
        let inheritedBinding = setup.binding(matching: .push, hostedBy: setup.inheritedHostID)
        let localBinding = setup.binding(matching: .push, hostedBy: setup.localHostID)

        #expect(inheritedBinding.wrappedValue == nil)
        #expect(localBinding.wrappedValue?.scope === presentedScope)

        inheritedBinding.wrappedValue = nil

        #expect(setup.branchScope.path.last === presentedScope)
        #expect(localBinding.wrappedValue?.scope === presentedScope)

        localBinding.wrappedValue = nil

        #expect(setup.branchScope.path.isEmpty)
        #expect(localBinding.wrappedValue == nil)
    }

    @Test func inheritedBranchPushStillPresentsFromItsAdoptingHost() async throws {
        let setup = makeBranchSetup(
            inherited: Push(TransactionRoute.self)._routeDeclarations,
            local: Push(SettingsRoute.self)._routeDeclarations
        )

        await setup.router.requestRoute(TransactionRoute())
        let presentedScope = try #require(setup.branchScope.path.last)

        #expect(
            setup.binding(matching: .push, hostedBy: setup.inheritedHostID)
                .wrappedValue?.scope === presentedScope
        )
        #expect(setup.binding(matching: .push, hostedBy: setup.localHostID).wrappedValue == nil)
    }

    @Test func inactiveBranchDeclarationUsesHostThatAdoptsItAfterSelectionChanges() async throws {
        let router = Router()
        router.ios17NavigationStackPushWorkaround = nil
        let (selection, selectedTab) = tabSelection(.home)
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        let walletScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let homeHostID = RoutePresentationHostID()
        let walletHostID = RoutePresentationHostID()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: [
                RouteScopeDeclaration(
                    branch: AppTab.home,
                    routes: Push(HomeDetailRoute.self)._routeDeclarations.drivingPresentation(false)
                ),
                RouteScopeDeclaration(
                    branch: AppTab.wallet,
                    routes: Push(TransactionRoute.self)._routeDeclarations.drivingPresentation(false)
                ),
            ]
        )
        router.root.registerBranchScope(
            homeScope,
            for: AppTab.home,
            presentationHostID: homeHostID
        )
        router.root.registerBranchScope(
            walletScope,
            for: AppTab.wallet,
            presentationHostID: walletHostID
        )

        await router.requestRoute(TransactionRoute())
        router.resumePendingRoute(for: AppTab.wallet, in: router.root)
        let presentedScope = try #require(walletScope.path.last)

        #expect(selectedTab() == .wallet)
        #expect(
            router.routePresentationBinding(
                from: walletScope,
                matching: .push,
                hostedBy: walletHostID
            ).wrappedValue?.scope === presentedScope
        )
        #expect(
            router.routePresentationBinding(
                from: walletScope,
                matching: .push,
                hostedBy: homeHostID
            ).wrappedValue == nil
        )
    }

    @Test func equalLocalAndInheritedPushDeclarationsStillPreferLocalHost() async throws {
        let declaration = Push(SettingsRoute.self)._routeDeclarations
        let setup = makeBranchSetup(inherited: declaration, local: declaration)

        #expect(
            declaration.hosted(by: setup.inheritedHostID)
                == declaration.hosted(by: setup.localHostID)
        )

        await setup.router.requestRoute(SettingsRoute())
        let presentedScope = try #require(setup.branchScope.path.last)
        let inheritedBinding = setup.binding(matching: .push, hostedBy: setup.inheritedHostID)
        let localBinding = setup.binding(matching: .push, hostedBy: setup.localHostID)

        #expect(inheritedBinding.wrappedValue == nil)
        #expect(localBinding.wrappedValue?.scope === presentedScope)

        inheritedBinding.wrappedValue = nil
        #expect(setup.branchScope.path.last === presentedScope)
    }

    @Test func sheetWriteBackIsAcceptedOnlyFromOwningHost() async throws {
        let setup = makeBranchSetup(
            inherited: Sheet(MessageRoute.self)._routeDeclarations,
            local: Sheet(LoginRoute.self)._routeDeclarations
        )

        await assertLocalOwnership(
            in: setup,
            localRoute: LoginRoute(),
            inheritedRoute: MessageRoute(),
            matching: .sheet
        )
    }

    @Test func slideCoverWriteBackIsAcceptedOnlyFromOwningHost() async throws {
        let setup = makeBranchSetup(
            inherited: Cover(MessageRoute.self)._routeDeclarations,
            local: Cover(AlertRoute.self)._routeDeclarations
        )

        await assertLocalOwnership(
            in: setup,
            localRoute: AlertRoute(),
            inheritedRoute: MessageRoute(),
            matching: .cover(.slide)
        )
    }

    @Test func fadeCoverWriteBackIsAcceptedOnlyFromOwningHost() async throws {
        let setup = makeBranchSetup(
            inherited: Cover(ChallengeRoute.self, transition: .fade)._routeDeclarations,
            local: Cover(LockRoute.self, transition: .fade)._routeDeclarations
        )

        await assertLocalOwnership(
            in: setup,
            localRoute: LockRoute(),
            inheritedRoute: ChallengeRoute(),
            matching: .cover(.fade)
        )
    }

    private func assertLocalOwnership(
        in setup: BranchSetup,
        localRoute: some Route,
        inheritedRoute: some Route,
        matching presentationKind: RoutePresentationKind
    ) async {
        await setup.router.requestRoute(localRoute)
        let presentedScope = setup.branchScope.path.last
        let inheritedBinding = setup.binding(
            matching: presentationKind,
            hostedBy: setup.inheritedHostID
        )
        let localBinding = setup.binding(
            matching: presentationKind,
            hostedBy: setup.localHostID
        )

        #expect(presentedScope != nil)
        #expect(inheritedBinding.wrappedValue == nil)
        #expect(localBinding.wrappedValue?.scope === presentedScope)

        inheritedBinding.wrappedValue = nil
        #expect(setup.branchScope.path.last === presentedScope)

        localBinding.wrappedValue = nil
        #expect(setup.branchScope.path.isEmpty)

        await setup.router.requestRoute(inheritedRoute)
        let inheritedScope = setup.branchScope.path.last

        #expect(inheritedScope != nil)
        #expect(inheritedBinding.wrappedValue?.scope === inheritedScope)
        #expect(localBinding.wrappedValue == nil)

        inheritedBinding.wrappedValue = nil
        #expect(setup.branchScope.path.isEmpty)
    }

    private func makeBranchSetup(
        inherited: [AnyRouteDeclaration],
        local: [AnyRouteDeclaration]
    ) -> BranchSetup {
        let router = Router()
        router.ios17NavigationStackPushWorkaround = nil
        let (selection, _) = tabSelection(.wallet)
        let branchScope = RouteScope(id: AnyHashable(AppTab.wallet), route: nil)
        let inheritedHostID = RoutePresentationHostID()
        let localHostID = RoutePresentationHostID()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: [
                RouteScopeDeclaration(
                    branch: AppTab.wallet,
                    routes: inherited.drivingPresentation(false)
                ),
            ]
        )
        branchScope.installRouteDeclarations(
            id: AnyHashable(AppTab.wallet),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: local.hosted(by: localHostID)),
            ]
        )
        router.root.registerBranchScope(
            branchScope,
            for: AppTab.wallet,
            presentationHostID: inheritedHostID
        )

        return BranchSetup(
            router: router,
            branchScope: branchScope,
            inheritedHostID: inheritedHostID,
            localHostID: localHostID
        )
    }
}

@MainActor
private struct BranchSetup {
    let router: Router
    let branchScope: RouteScope
    let inheritedHostID: RoutePresentationHostID
    let localHostID: RoutePresentationHostID

    func binding(
        matching presentationKind: RoutePresentationKind,
        hostedBy presentationHostID: RoutePresentationHostID
    ) -> Binding<RoutePresentation?> {
        router.routePresentationBinding(
            from: branchScope,
            matching: presentationKind,
            hostedBy: presentationHostID
        )
    }
}
