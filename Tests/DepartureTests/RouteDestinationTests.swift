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
    func destinationBindingsPreserveTypedDataContextAndChildren(nested: Bool) async throws {
        let recorder = BuildRecorder()
        let children = RouteMap {
            testSheet(testDestination(SettingsRoute.self))
        }
        let declarations: [AnyRouteDeclaration]
        if nested {
            declarations = [
                testPush(RouteDestination(FeatureProvidedRoute.self) { route, context in
                    recorder.view(route, context)
                }, id: "push") { children }.declaration,
                testReplace(RouteDestination(FeatureProvidedRoute.self) { route, context in
                    recorder.view(route, context)
                }, id: "replace") { children }.declaration,
                testSheet(RouteDestination(FeatureProvidedRoute.self) { route, context in
                    recorder.view(route, context)
                }, id: "sheet") { children }.declaration,
                testCover(RouteDestination(FeatureProvidedRoute.self) { route, context in
                    recorder.view(route, context)
                }, id: "slide") { children }.declaration,
                testCover(RouteDestination(FeatureProvidedRoute.self) { route, context in
                    recorder.view(route, context)
                }, transition: .fade, id: "fade") { children }.declaration,
            ]
        } else {
            declarations = [
                testPush(RouteDestination(FeatureProvidedRoute.self) { route, context in
                    recorder.view(route, context)
                    if context.presentation.style == .push { Text("Push") }
                }, id: "push").declaration,
                testReplace(RouteDestination(FeatureProvidedRoute.self) { route, context in
                    recorder.view(route, context)
                }, id: "replace").declaration,
                testSheet(RouteDestination(FeatureProvidedRoute.self) { route, context in
                    recorder.view(route, context)
                }, id: "sheet").declaration,
                testCover(RouteDestination(FeatureProvidedRoute.self) { route, context in
                    recorder.view(route, context)
                }, id: "slide").declaration,
                testCover(RouteDestination(FeatureProvidedRoute.self) { route, context in
                    recorder.view(route, context)
                }, transition: .fade, id: "fade").declaration,
            ]
        }
        #expect(recorder.context == nil)
        let styles: [RoutePresentation.Style] = [.push, .replace, .sheet, .cover(.slide), .cover(.fade)]
        let ids = ["push", "replace", "sheet", "slide", "fade"]
        for (index, declaration) in declarations.enumerated() {
            let engine = RouterEngine(routes: RootRouteMap { declaration })
            var builds = 0
            let route = FeatureProvidedRoute { builds += 1 }
            await engine.present(route)
            let scope = try #require(engine.defaultSpace.rootPath.last)
            #expect(scope.id == AnyHashable(ids[index]))
            #expect((scope.definitions.routeBinding(for: SettingsRoute.self) != nil) == nested)
            #expect(builds == 0)
            var environment = EnvironmentValues()
            environment.locale = Locale(identifier: "fr_FR")
            let context = RouteContext(
                router: Router(engine: engine, scope: scope),
                unwindRoute: UnwindRouteAction(router: engine, routeScope: scope),
                presentation: try #require(scope.routePresentation),
                environment: environment
            )
            _ = try #require(scope.presentation?.destination).build(route, context)
            #expect(builds == 1)
            #expect(recorder.context?.router == context.router)
            #expect(recorder.context?.presentation.style == styles[index])
            #expect(recorder.context?.presentation.priority == .default)
            #expect(recorder.context?.environment.locale.identifier == "fr_FR")
            #expect(await recorder.context?.unwindRoute() == true)
            #expect(engine.defaultSpace.rootPath.isEmpty)
        }
    }

    @Test func domainRouteUsesFeatureDestinationWithoutConformance() async throws {
        let recorder = BuildRecorder()
        let destination = RouteDestination(DomainOnlyRoute.self) { _, context in
            recorder.presentation = context.presentation
            return EmptyView()
        }
        let engine = RouterEngine(routes: RootRouteMap { testSheet(destination) })
        await engine.present(DomainOnlyRoute())
        let scope = try #require(engine.defaultSpace.rootPath.last)
        let destinationBuilder = try #require(scope.presentation?.destination)
        let context = RouteContext(router: Router(engine: engine, scope: scope), unwindRoute: UnwindRouteAction(router: engine, routeScope: scope), presentation: .init(style: .sheet, priority: .default), environment: EnvironmentValues())
        _ = destinationBuilder.build(DomainOnlyRoute(), context)
        #expect(recorder.presentation?.style == .sheet)
        #expect(recorder.presentation?.priority == .default)
        #expect(await context.unwindRoute())
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }

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
        let scope = try #require(engine.defaultSpace.rootPath.last)
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
        #expect(engine.defaultSpace.rootPath.scopes.count == (nested ? 1 : 0))
    }
    @Test func destinationDefinitionsAreAvailableImmediatelyAfterAppend() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            testPush(testDestination(DomainOnlyRoute.self)) {
                testSheet(testDestination(SettingsRoute.self))
            }
        })
        await engine.present(DomainOnlyRoute())
        let scope = try #require(engine.defaultSpace.rootPath.last)
        #expect(!scope.isInstalledInView)
        #expect(scope.definitions.routeBinding(for: SettingsRoute.self) != nil)
    }
    @Test(arguments: [RoutePriority.high, .critical])
    func effectivePrioritySurvivesRemovalFromLiveGraph(priority: RoutePriority) async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            HighPriority {
                if priority == .high {
                    testCover(testDestination(DomainOnlyRoute.self)) {
                        testPush(testDestination(SettingsRoute.self))
                    }
                }
            }
            CriticalPriority {
                if priority == .critical {
                    testSheet(testDestination(DomainOnlyRoute.self)) {
                        testPush(testDestination(SettingsRoute.self))
                    }
                }
            }
        })
        await engine.present(DomainOnlyRoute())
        await engine.present(SettingsRoute())
        let child = try #require(engine.spaces.space(for: priority)?.rootPath.last)
        #expect(child.routePresentation?.style == .push)
        #expect(child.routePresentation?.priority == priority)
        #expect(await engine.unwind(to: .root))
        #expect(child.routePresentation?.priority == priority)
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
