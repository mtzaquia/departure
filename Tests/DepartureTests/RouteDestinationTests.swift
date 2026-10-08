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

import RouteDomainFixtures
import SwiftUI
import Testing
@testable import Departure

extension FeatureProvidedRoute: RouteViewProviding {
    public func destination() -> some View {
        DestinationBuildProbe(onBuild: destinationDidBuild)
    }
}

@MainActor
@Suite
struct RouteDestinationTests {
    @Test func routeWithoutDestinationUsesFallback() {
        let destination = DomainOnlyRoute().destination()

        #expect(destination is MissingRouteDestination)
    }

    @Test func legacyRouteDestinationRemainsSupported() {
        var buildCount = 0
        let route = LegacyDestinationRoute {
            buildCount += 1
        }

        _ = routeDestination(for: route)

        #expect(buildCount == 1)
    }

    @Test func separatelyProvidedDestinationTakesPrecedence() {
        var buildCount = 0
        let route = FeatureProvidedRoute {
            buildCount += 1
        }

        _ = routeDestination(for: route)

        #expect(buildCount == 1)
    }

    @Test func explicitDomainDestinationReceivesTypedRouteData() async throws {
        let recorder = DestinationRecorder()
        let destination = RouteDestination(NumberedRoute.self) { route, context in
            recorder.number = route.number
            recorder.context = context
            return EmptyView()
        }
        let engine = RouterEngine()
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil,
            routeDeclarations: [RouteScopeDeclaration(routes: Push(destination)._routeDeclarations)])
        await engine.present(NumberedRoute(number: 42))
        let scope = try #require(engine.normalTree.rootPath.last)
        let declaration = try #require(scope.presentationDeclaration)
        let builder = try #require(declaration.destination)
        let context = RouteContext(router: Router(engine: engine, scope: scope),
            unwindRoute: UnwindRouteAction(router: engine, routeScope: scope),
            presentation: .init(style: .push, priority: .normal), environment: EnvironmentValues())
        _ = builder.build(try #require(scope.route), context)
        #expect(recorder.number == 42)
        #expect(recorder.context?.router == context.router)
        #expect(await context.unwindRoute())
        #expect(engine.normalTree.rootPath.isEmpty)
    }

    @Test func destinationBindingsSurviveBranchAdoptionAndHosting() throws {
        let destination = RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }
        let branch = Branch(AppTab.home) { Push(destination) }.routeScopeDeclarations
        let discovery = try #require(branch.first?.routes.first)
        #expect(discovery.destination === destination.destination)
        #expect(!discovery.drivesPresentation)
        let hosted = discovery.drivingPresentation(true).hosted(by: RoutePresentationHostID())
        #expect(hosted.destination === destination.destination)
        #expect(hosted.drivesPresentation)
    }

    @Test func destinationInitializersPreserveExistingPresentationDefaults() {
        let destination = RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }
        #expect(Push(destination).declaration.kind == Push(DomainOnlyRoute.self).declaration.kind)
        #expect(Replace(destination).declaration.kind == Replace(DomainOnlyRoute.self).declaration.kind)
        #expect(Sheet(destination).declaration.kind == Sheet(DomainOnlyRoute.self).declaration.kind)
        #expect(Cover(destination).declaration.kind == Cover(DomainOnlyRoute.self).declaration.kind)
        #expect(Sheet(destination, priority: .high, providesNavigation: false).declaration.kind
            == Sheet(DomainOnlyRoute.self, priority: .high, providesNavigation: false).declaration.kind)
        #expect(Cover(destination, priority: .critical, transition: .fade, providesNavigation: false).declaration.kind
            == Cover(DomainOnlyRoute.self, priority: .critical, transition: .fade, providesNavigation: false).declaration.kind)
        #expect(Push(destination).declaration == Push(destination).declaration)
        #expect(Set([Push(destination).declaration, Push(destination).declaration]).count == 1)
        let other = RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }
        #expect(Push(destination).declaration != Push(other).declaration)
    }

    @Test func nearestDeclarationSelectsItsOwnBuilder() async throws {
        let recorder = DestinationRecorder()
        let outer = RouteDestination(NumberedRoute.self) { route, _ in
            recorder.number = -route.number
            return EmptyView()
        }
        let inner = RouteDestination(NumberedRoute.self) { route, _ in
            recorder.number = route.number
            return EmptyView()
        }
        let engine = RouterEngine()
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil,
            routeDeclarations: [RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations
                + Sheet(outer)._routeDeclarations)])
        await engine.present(HomeDetailRoute())
        let parent = try #require(engine.normalTree.rootPath.last)
        parent.installRouteDeclarations(id: nil, branchSelection: nil,
            routeDeclarations: [RouteScopeDeclaration(routes: Push(inner)._routeDeclarations)])
        await Router(engine: engine, scope: parent).present(NumberedRoute(number: 7))
        let selected = try #require(engine.normalTree.rootPath.last)
        #expect(selected.presentationDeclaration?.destination === inner.destination)
        #expect(selected.presentationDeclaration?.presentationKind == .push)
    }

    @Test(arguments: [RoutePriority.high, .critical])
    func childrenKeepEffectivePriorityDuringOutgoingSnapshots(priority: RoutePriority) async throws {
        let engine = RouterEngine()
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil,
            routeDeclarations: [RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: priority)._routeDeclarations)])
        await engine.present(LoginRoute())
        let tree = try #require(engine.routeForest.tree(for: priority))
        let parent = try #require(tree.rootPath.last)
        parent.installRouteDeclarations(id: nil, branchSelection: nil,
            routeDeclarations: [RouteScopeDeclaration(routes: Push(HomeDetailRoute.self)._routeDeclarations)])
        await Router(engine: engine, scope: parent).present(HomeDetailRoute())
        let child = try #require(tree.rootPath.last)
        #expect(child.presentation?.priority == priority)
        #expect(child.presentationDeclaration?.presentationKind == .push)
        #expect(await engine.unwind(to: .root))
        #expect(engine.routeForest.tree(for: priority) == nil)
        #expect(child.presentation?.priority == priority)
    }

}

private struct LegacyDestinationRoute: Route {
    let destinationDidBuild: @MainActor () -> Void

    func destination() -> some View {
        DestinationBuildProbe(onBuild: destinationDidBuild)
    }
}

private struct DestinationBuildProbe: View {
    init(onBuild: @MainActor () -> Void) {
        onBuild()
    }

    var body: some View {
        EmptyView()
    }
}

@MainActor
private final class DestinationRecorder {
    var number: Int?
    var context: RouteContext?
}
