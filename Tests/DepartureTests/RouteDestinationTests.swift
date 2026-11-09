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
import RouteDomainFixtures
@testable import Departure

@MainActor @Suite struct RouteDestinationTests {

    @Test(arguments: [false, true])
    func nearestDeclarationBuildsTypedDataInItsOwnContext(nested: Bool) async throws {
        let recorder = BuildRecorder()
        let destination = RouteDestination(NumberedRoute.self) { route, context in
            recorder.number = context.presentation.style == .push ? route.number : -route.number
            recorder.context = context
            return EmptyView()
        }
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(NumberedRoute.self)
            Push(HomeDetailRoute.self) { Push(NumberedRoute.self) }
        } destinations: {
            destination
            testDestination(HomeDetailRoute.self)
        })
        if nested { await engine.present(HomeDetailRoute()) }
        await engine.present(NumberedRoute(number: 42))
        let scope = try #require(engine.tree.rootPath.last)
        let context = RouteContext(
            router: Router(engine: engine, scope: scope),
            unwindRoute: UnwindRouteAction(router: engine, routeScope: scope),
            presentation: try #require(scope.routePresentation), environment: EnvironmentValues()
        )
        _ = try #require(scope.presentation?.destination).build(try #require(scope.route), context)
        #expect(recorder.number == (nested ? 42 : -42))
        #expect(recorder.context?.router == context.router)
        #expect(recorder.context?.presentation.style == (nested ? .push : .sheet))
        #expect(await context.unwindRoute())
        #expect(engine.tree.rootPath.scopes.count == (nested ? 1 : 0))
    }
    @Test func destinationDefinitionsAreAvailableImmediatelyAfterAppend() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            testPush(testDestination(DomainOnlyRoute.self)) {
                testSheet(testDestination(SettingsRoute.self))
            }
        })
        await engine.present(DomainOnlyRoute())
        let scope = try #require(engine.tree.rootPath.last)
        #expect(!scope.isInstalledInView)
        #expect(scope.definitions.routeBinding(for: SettingsRoute.self) != nil)
    }


    @Test func reusedDestinationHasDistinctPlacementIdentity() {
        let destination = testDestination(DomainOnlyRoute.self)
        let map = RootRouteMap { testPush(destination) { testSheet(destination) } }
        let parent = map.declarations.flatMap(\.routes)[0]
        #expect(parent.identity != parent.children.flatMap(\.routes)[0].identity)
    }
}
@MainActor private final class BuildRecorder {
    var presentation: RoutePresentation?
    var context: RouteContext?
    var number: Int?

    func view(_ route: FeatureProvidedRoute, _ context: RouteContext) -> some View {
        route.destinationDidBuild()
        self.context = context
        return EmptyView()
    }
}
