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
    func inlineBuildersPreserveTypedDataContextAndChildren(nested: Bool) async throws {
        let recorder = BuildRecorder()
        let children = RouteMap {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
        }
        let declarations: [AnyRouteDeclaration]
        if nested {
            declarations = [
                Push(FeatureProvidedRoute.self, id: "push") { route, context in
                    recorder.view(route, context)
                } routes: { children }.declaration,
                Replace(FeatureProvidedRoute.self, id: "replace") { route, context in
                    recorder.view(route, context)
                } routes: { children }.declaration,
                Sheet(FeatureProvidedRoute.self, id: "sheet") { route, context in
                    recorder.view(route, context)
                } routes: { children }.declaration,
                Cover(FeatureProvidedRoute.self, id: "slide") { route, context in
                    recorder.view(route, context)
                } routes: { children }.declaration,
                Cover(FeatureProvidedRoute.self, transition: .fade, id: "fade") { route, context in
                    recorder.view(route, context)
                } routes: { children }.declaration,
            ]
        } else {
            declarations = [
                Push(FeatureProvidedRoute.self, id: "push") { route, context in
                    recorder.view(route, context)
                    if context.presentation.style == .push { Text("Push") }
                }.declaration,
                Replace(FeatureProvidedRoute.self, id: "replace") { route, context in
                    recorder.view(route, context)
                }.declaration,
                Sheet(FeatureProvidedRoute.self, id: "sheet") { route, context in
                    recorder.view(route, context)
                }.declaration,
                Cover(FeatureProvidedRoute.self, id: "slide") { route, context in
                    recorder.view(route, context)
                }.declaration,
                Cover(FeatureProvidedRoute.self, transition: .fade, id: "fade") { route, context in
                    recorder.view(route, context)
                }.declaration,
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
            _ = try #require(scope.presentationDeclaration).build(route, context)
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
        let engine = RouterEngine(routes: RootRouteMap { Sheet(destination) })
        await engine.present(DomainOnlyRoute())
        let scope = try #require(engine.defaultSpace.rootPath.last)
        let declaration = try #require(scope.presentationDeclaration)
        let context = RouteContext(router: Router(engine: engine, scope: scope), unwindRoute: UnwindRouteAction(router: engine, routeScope: scope), presentation: .init(style: .sheet, priority: .default), environment: EnvironmentValues())
        _ = declaration.build(DomainOnlyRoute(), context)
        #expect(recorder.presentation?.style == .sheet)
        #expect(recorder.presentation?.priority == .default)
        #expect(await context.unwindRoute())
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }
    @Test func destinationDefinitionsAreAvailableImmediatelyAfterAppend() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }) {
                Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
            }
        })
        await engine.present(DomainOnlyRoute())
        let scope = try #require(engine.defaultSpace.rootPath.last)
        #expect(!scope.isInstalledInView)
        #expect(scope.definitions.routeBinding(for: SettingsRoute.self) != nil)
    }
    @Test(arguments: [RoutePriority.high, .critical])
    func effectivePrioritySurvivesRemovalFromLiveGraph(priority: RoutePriority) async throws {
        let engine = RouterEngine(routes: RootRouteMap {} highPriority: {
            if priority == .high {
                Cover(DomainOnlyRoute.self) { _, _ in EmptyView() } routes: {
                    Push(SettingsRoute.self) { _, _ in EmptyView() }
                }
            }
        } criticalPriority: {
            if priority == .critical {
                Sheet(DomainOnlyRoute.self) { _, _ in EmptyView() } routes: {
                    Push(SettingsRoute.self) { _, _ in EmptyView() }
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
        let destination = RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }
        let map = RootRouteMap { Push(destination) { Sheet(destination) } }
        let parent = map.declarations[0].routes[0]
        #expect(parent.identity != parent.children[0].routes[0].identity)
    }
}
@MainActor private final class BuildRecorder {
    var presentation: RoutePresentation?
    var context: RouteContext?

    func view(_ route: FeatureProvidedRoute, _ context: RouteContext) -> some View {
        route.destinationDidBuild()
        self.context = context
        return EmptyView()
    }
}
