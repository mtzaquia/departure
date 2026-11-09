import SwiftUI
import Testing
@testable import Departure

@MainActor @Suite
struct LegacyPriorityCompatibilityTests {
    @Test(arguments: [false, true])
    func priorityAliasesPresentGlobalsInEitherOrder(highFirst: Bool) async throws {
        let owner = RootRouter()
        let feature = ModalRouteMap {
            Sheet(Challenge.self) { Push(Detail.self) }
        } destinations: {
            RouteDestination(Challenge.self) { _, _ in EmptyView() }
            RouteDestination(Detail.self) { _, _ in EmptyView() }
        }
        _ = WithRouter(routes: RootRouteMap {
            Sheet(Checkout.self)
            HighPriority { feature }
            CriticalPriority { Cover(Passcode.self, transition: .fade) }
        } destinations: {
            RouteDestination(Checkout.self) { _, _ in EmptyView() }
            RouteDestination(Passcode.self) { _, _ in EmptyView() }
        }, router: owner) { EmptyView() }

        await owner.root.present(Checkout())
        let checkout = owner.engine.currentRouteScope
        if highFirst { await owner.root.present(Challenge()) }
        else { await owner.root.present(Passcode()) }
        let first = owner.engine.currentRouteScope
        #expect(first.presentationOrigin === checkout)
        #expect(first.routePresentation?.isGlobal == true)
        if highFirst { await owner.root.present(Passcode()) }
        else { await owner.root.present(Challenge()) }
        let second = owner.engine.currentRouteScope
        #expect(second.presentationOrigin === first)
        #expect(second.routePresentation?.isGlobal == true)
        #expect(checkout.belongs(to: owner.engine.tree))
        #expect(await owner.current.unwind(.current))
        #expect(owner.engine.currentRouteScope === first)
        if !highFirst { await owner.current.present(Challenge()) }
        await owner.current.present(Detail())
        let detail = owner.engine.currentRouteScope
        #expect(detail.route is Detail)
        #expect(detail.routePresentation?.isGlobal == false)
    }

    @Test(arguments: [RoutePriority.default, .high, .critical])
    func obsoleteDismissalsPreserveTheEntireTree(priority: RoutePriority) async {
        let owner = configuredOwner()
        await owner.root.present(Checkout())
        await owner.root.present(Challenge())
        let foreground = owner.engine.currentRouteScope
        let path = owner.engine.root.path.scopes.map(ObjectIdentifier.init)
        #expect(await owner.current.dismissSpace() == false)
        #expect(await owner.dismissSpace(priority) == false)
        #expect(await owner.dismissSpaces() == false)
        #expect(owner.engine.currentRouteScope === foreground)
        #expect(owner.engine.root.path.scopes.map(ObjectIdentifier.init) == path)
        #expect(owner.engine.navigationOperations.isEmpty)
        #expect(owner.default == owner.current)
        #expect(foreground.routePresentation?.priority == .default)
    }

    @Test func legacyWindowCustomizerIsIgnoredAndHostStillConfiguresRouting() async {
        let owner = RootRouter()
        var customizations = 0
        let host = WithRouter(routes: routes, router: owner) {
            EmptyView()
        } windowDestination: { view, _ in
            customizations += 1
            return view
        }
        _ = host.body
        await owner.default.present(Challenge())
        #expect(owner.engine.currentRouteScope.route is Challenge)
        #expect(customizations == 0)
    }

    @Test(arguments: LegacyPriorityDismissalWarning.allCases)
    func obsoleteDismissalWarningsExplainTheNoOp(event: LegacyPriorityDismissalWarning) {
        let message = DepartureLogTrace.$id.withValue("u:12345678") { event.renderedMessage }
        #expect(message == "[compatibility][u:12345678] ⊘ \(event.rawValue) has no effect because priority spaces no longer exist. "
            + "Use a scoped router's unwind(_:) or resetToRoot(); navigation is unchanged and false is returned.")
    }

    private var routes: RootRouteMap {
        RootRouteMap {
            Sheet(Checkout.self)
            GlobalMap { Sheet(Challenge.self) }
        } destinations: {
            RouteDestination(Checkout.self) { _, _ in EmptyView() }
            RouteDestination(Challenge.self) { _, _ in EmptyView() }
        }
    }

    private func configuredOwner() -> RootRouter {
        let owner = RootRouter()
        _ = WithRouter(routes: routes, router: owner) { EmptyView() }
        return owner
    }
}

private struct Checkout: Route, Equatable {}
private struct Challenge: Route, Equatable {}
private struct Passcode: Route, Equatable {}
private struct Detail: Route, Equatable {}
