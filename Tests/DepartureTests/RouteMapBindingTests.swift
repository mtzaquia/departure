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

@MainActor @Suite struct RouteMapBindingTests {
    @Test(arguments: [false, true])
    func destinationCollectionsComposeWithoutBuildingViews(includeOptional: Bool) {
        var builds = 0
        let domain = RouteDestination(DomainOnlyRoute.self) { _, _ in
            builds += 1
            return EmptyView()
        }
        let numbered = RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }
        let feature = RouteDestinations { domain }
        let collection = RouteDestinations {
            feature
            if includeOptional { numbered }
            if includeOptional { domain } else { numbered }
            for _ in 0..<2 { AnyRouteDestination(domain) }
        }
        let types = collection.destinations.map { ObjectIdentifier($0.routeType) }
        #expect(types.count == (includeOptional ? 5 : 4))
        #expect(types.first == ObjectIdentifier(DomainOnlyRoute.self))
        #expect(types.last == ObjectIdentifier(DomainOnlyRoute.self))
        #expect(builds == 0)
    }

    @Test func domainModuleCanComposeAFlowWithoutFeatureViews() async throws {
        let engine = RouterEngine(
            routes: RootRouteMap {
                DomainRouteMaps.feature
            } destinations: {
                RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }
                RouteDestination(FeatureProvidedRoute.self) { route, _ in
                    route.destinationDidBuild()
                    return EmptyView()
                }
            })
        #expect(engine.root.branchScopes.keys.isEmpty)
        await engine.present(DomainOnlyRoute())
        let parent = try #require(engine.defaultSpace.rootPath.last)
        #expect(parent.id == AnyHashable("domain-sheet"))
        var builds = 0
        await engine.present(FeatureProvidedRoute { builds += 1 })
        let child = try #require(engine.defaultSpace.rootPath.last)
        #expect(child !== parent)
        #expect(builds == 0)
        try render(child, in: engine)
        #expect(builds == 1)
        #expect(child.routePresentation?.style == .push)
    }

    @Test func rootCompletesFeatureDestinationContributions() async throws {
        var rendered: [String] = []
        let feature = RouteMap {
            Push(HomeDetailRoute.self) {
                Push(NumberedRoute.self)
                Sheet(SettingsRoute.self)
            }
        } destinations: {
            RouteDestination(NumberedRoute.self) { route, _ in
                rendered.append("feature:\(route.number)")
                return EmptyView()
            }
        }
        let engine = RouterEngine(
            routes: RootRouteMap {
                feature
            } destinations: {
                RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }
                RouteDestination(SettingsRoute.self) { _, _ in
                    rendered.append("settings")
                    return EmptyView()
                }
            })
        #expect(rendered.isEmpty)
        await engine.present(HomeDetailRoute())
        await engine.present(NumberedRoute(number: 42))
        try render(#require(engine.defaultSpace.rootPath.last), in: engine)
        await engine.present(SettingsRoute())
        try render(#require(engine.defaultSpace.rootPath.last), in: engine)
        #expect(rendered == ["feature:42", "settings"])
    }

    @Test func oneFeatureCanSupplyADestinationUsedByItsSibling() async throws {
        var rendered: [Int] = []
        let builder = RouteDestination(NumberedRoute.self) { route, _ in
            rendered.append(route.number)
            return EmptyView()
        }
        let supplying = RouteMap {
            Push(NumberedRoute.self)
        } destinations: {
            builder
        }
        let consuming = RouteMap { Push(NumberedRoute.self) }
        let engine = RouterEngine(
            routes: RootRouteMap {
                Branches(concurrent: true) {
                    Branch("supplying") { supplying }
                    Branch("consuming") { consuming }
                }
            })
        let router = Router(engine: engine, scope: engine.root)
        for (name, number) in [("supplying", 1), ("consuming", 2)] {
            await router.branch(name).present(NumberedRoute(number: number))
            try render(#require(engine.root.branchScopes[name]?.path.last), in: engine)
        }
        #expect(rendered == [1, 2])
    }

    @Test func missingDestinationDoesNotActivateABranch() async throws {
        let engine = RouterEngine(
            routes: RootRouteMap {
                Branches {
                    Branch("bound") { Push(NumberedRoute.self) }
                    Branch("unbound") { Push(DomainOnlyRoute.self) }
                }
            } destinations: {
                RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }
            })
        let router = Router(engine: engine, scope: engine.root)
        await router.branch("bound").present(NumberedRoute(number: 1))
        let retained = try #require(engine.root.branchScopes["bound"]?.path.last)
        await router.branch("unbound").present(DomainOnlyRoute())
        #expect(engine.root.activeBranch == AnyHashable("bound"))
        #expect(engine.root.branchScopes["bound"]?.path.last === retained)
        #expect(engine.root.branchScopes["unbound"]?.path.isEmpty == true)
        #expect(engine.pendingRoute == nil)
        #expect(engine.navigationOperations.isEmpty)
    }

    @Test(arguments: [false, true])
    func missingBuilderDoesNotUnwindExistingDescendants(replace: Bool) async throws {
        let engine = RouterEngine(
            routes: RootRouteMap {
                Sheet(DomainOnlyRoute.self)
                Push(HomeDetailRoute.self) {
                    if replace { Replace(DomainOnlyRoute.self) } else { Sheet(DomainOnlyRoute.self) }
                    Push(NumberedRoute.self)
                }
            } destinations: {
                RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }
                RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }
            })
        await engine.present(HomeDetailRoute())
        await engine.present(NumberedRoute(number: 42))
        let retained = try #require(engine.defaultSpace.rootPath.last)
        #expect(await engine.requestRoute(DomainOnlyRoute()) == nil)
        #expect(engine.defaultSpace.rootPath.last === retained)
        #expect(engine.defaultSpace.rootPath.scopes.count == 2)
        #expect(engine.navigationOperations.isEmpty)
    }

    @Test(arguments: [false, true])
    func distinctSiblingDestinationsConflictThroughoutTheTree(reverse: Bool) async throws {
        var builds = 0
        let first = RouteDestination(NumberedRoute.self) { _, _ in
            builds += 1
            return EmptyView()
        }
        let second = RouteDestination(NumberedRoute.self) { _, _ in
            builds += 1
            return EmptyView()
        }
        let firstMap = RouteMap {
            Push(NumberedRoute.self)
        } destinations: {
            first
        }
        let secondMap = RouteMap {
            Sheet(NumberedRoute.self)
        } destinations: {
            second
        }
        let engine = RouterEngine(
            routes: RootRouteMap {
                Sheet(SettingsRoute.self)
                Branches {
                    if reverse {
                        Branch("second") { secondMap }
                        Branch("first") { firstMap }
                    } else {
                        Branch("first") { firstMap }
                        Branch("second") { secondMap }
                    }
                }
            } destinations: {
                first  // Repeating a value after a conflict must not restore the binding.
                RouteDestination(SettingsRoute.self) { _, _ in EmptyView() }
            })
        let router = Router(engine: engine, scope: engine.root)
        for name in ["first", "second"] {
            let branch = try #require(engine.root.branchScopes[name])
            guard case .conflict? = branch.definitions.routeBinding(for: NumberedRoute.self) else {
                Issue.record("Distinct destination values must disable every occurrence")
                return
            }
            await router.branch(name).present(NumberedRoute(number: 42))
            #expect(branch.path.isEmpty)
        }
        #expect(builds == 0)
        #expect(engine.pendingRoute == nil)
        await engine.present(SettingsRoute())
        #expect(engine.defaultSpace.rootPath.last?.route is SettingsRoute)
    }

    @Test func aConflictInAnUnpresentedChildDisablesAncestorBindings() async throws {
        let first = RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }
        let second = RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }
        let nested = RouteMap {
            Sheet(DomainOnlyRoute.self)
            Push(NumberedRoute.self)
        } destinations: {
            second
        }
        let engine = RouterEngine(
            routes: RootRouteMap {
                Sheet(DomainOnlyRoute.self)
                Push(HomeDetailRoute.self) { nested }
            } destinations: {
                first
                RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }
                RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }
            })
        #expect(await engine.requestRoute(DomainOnlyRoute()) == nil)
        await engine.present(HomeDetailRoute())
        await engine.present(NumberedRoute(number: 42))
        let retained = try #require(engine.defaultSpace.rootPath.last)
        #expect(await engine.requestRoute(DomainOnlyRoute()) == nil)
        #expect(engine.defaultSpace.rootPath.last === retained)
        #expect(engine.defaultSpace.rootPath.scopes.count == 2)
        #expect(engine.navigationOperations.isEmpty)
    }

    @Test func aBuilderInAnUnpresentedChildCanSupplyTheRoot() async throws {
        var builds = 0
        let child = RouteMap {
        } destinations: {
            RouteDestination(DomainOnlyRoute.self) { _, _ in
                builds += 1
                return EmptyView()
            }
        }
        let engine = RouterEngine(
            routes: RootRouteMap {
                Sheet(DomainOnlyRoute.self)
                Push(HomeDetailRoute.self) { child }
            } destinations: {
                RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }
            })
        #expect(builds == 0)
        await engine.present(DomainOnlyRoute())
        try render(#require(engine.defaultSpace.rootPath.last), in: engine)
        #expect(builds == 1)
    }

    @Test func registeringADestinationDoesNotDeclareARoute() async {
        let engine = RouterEngine(
            routes: RootRouteMap {
            } destinations: {
                RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }
            })
        #expect(engine.root.definitions.routeBinding(for: DomainOnlyRoute.self) == nil)
        #expect(await engine.requestRoute(DomainOnlyRoute()) == nil)
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }

    @Test(arguments: [false, true])
    func repeatingTheSameDestinationValueAndCollectionIsAllowed(reverse: Bool) async throws {
        var builds = 0
        let original = RouteDestination(DomainOnlyRoute.self) { _, _ in
            builds += 1
            return EmptyView()
        }
        let copy = original
        let erased = AnyRouteDestination(original)
        #expect(erased == AnyRouteDestination(copy))
        let collection = RouteDestinations {
            copy
            erased
        }
        let feature = RouteMap {
            Push(DomainOnlyRoute.self)
        } destinations: {
            collection
        }
        let engine = RouterEngine(
            routes: RootRouteMap {
                feature
            } destinations: {
                if reverse {
                    collection
                    original
                } else {
                    original
                    collection
                }
                collection
            })
        #expect(builds == 0)
        await engine.present(DomainOnlyRoute())
        try render(#require(engine.defaultSpace.rootPath.last), in: engine)
        #expect(builds == 1)
    }

    @Test(arguments: [RoutePriority.high, .critical])
    func reusedMapsShareOneDestinationAcrossBranchesAndPrioritySpaces(priority: RoutePriority) async throws {
        var rendered: [String] = []
        let number = RouteDestination(NumberedRoute.self) { route, _ in
            rendered.append("parent:\(route.number)")
            return EmptyView()
        }
        let child = RouteDestination(DomainOnlyRoute.self) { _, _ in
            rendered.append("child")
            return EmptyView()
        }
        let reusable = RouteMap {
            Push(NumberedRoute.self) { Sheet(DomainOnlyRoute.self) }
        } destinations: {
            number
            child
        }
        let branches = RouteMap {
            Branches(concurrent: true) {
                Branch("first") { reusable }
                Branch("second") { reusable }
            }
        }
        let engine = RouterEngine(
            routes: RootRouteMap {
                if priority == .high {
                    HighPriority { Sheet(HomeDetailRoute.self) { branches } }
                } else {
                    CriticalPriority { Cover(HomeDetailRoute.self) { branches } }
                }
            } destinations: {
                number
                child
                RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }
            })
        await engine.present(HomeDetailRoute())
        let entry = try #require(engine.spaces.space(for: priority)?.root)
        let router = Router(engine: engine, scope: entry)
        for (name, value) in [("first", 1), ("second", 2)] {
            await router.branch(name).present(NumberedRoute(number: value))
            try render(#require(entry.branchScopes[name]?.path.last), in: engine)
            await router.branch(name).present(DomainOnlyRoute())
            try render(#require(entry.branchScopes[name]?.path.last), in: engine)
        }
        #expect(rendered == ["parent:1", "child", "parent:2", "child"])
    }

    @Test func differentRoutingOwnersCanUseDifferentDestinationValues() async throws {
        var rendered: [String] = []
        func owner(_ name: String) -> RouterEngine {
            RouterEngine(
                routes: RootRouteMap {
                    Sheet(DomainOnlyRoute.self)
                } destinations: {
                    RouteDestination(DomainOnlyRoute.self) { _, _ in
                        rendered.append(name)
                        return EmptyView()
                    }
                })
        }
        for name in ["first", "second"] {
            let engine = owner(name)
            await engine.present(DomainOnlyRoute())
            try render(#require(engine.defaultSpace.rootPath.last), in: engine)
        }
        #expect(rendered == ["first", "second"])
    }

    @Test(arguments: [RoutePriority.high, .critical])
    func rootPriorityGroupsUseSharedBuildersAndKeepChildPriorityLocal(priority: RoutePriority) async throws {
        let engine = RouterEngine(
            routes: RootRouteMap {
                if priority == .high {
                    HighPriority { Sheet(DomainOnlyRoute.self) { Push(NumberedRoute.self) } }
                } else {
                    CriticalPriority { Cover(DomainOnlyRoute.self, transition: .fade) { Push(NumberedRoute.self) } }
                }
            } destinations: {
                RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }
                RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }
            })
        let entry = try #require(engine.root.definitions.routeBinding(for: DomainOnlyRoute.self)?.declaration)
        #expect(entry.priority == priority)
        #expect(entry.childScope?.routeBinding(for: NumberedRoute.self)?.declaration?.priority == .default)
        await engine.present(DomainOnlyRoute())
        await engine.present(NumberedRoute(number: 1))
        #expect(engine.spaces.space(for: priority)?.rootPath.last?.routePresentation?.priority == priority)
    }

    private func render(_ scope: RouteScope, in engine: RouterEngine) throws {
        let route = try #require(scope.route)
        let destination = try #require(scope.presentation?.destination)
        _ = destination.build(
            route,
            RouteContext(
                router: Router(engine: engine, scope: scope),
                unwindRoute: UnwindRouteAction(router: engine, routeScope: scope),
                presentation: try #require(scope.routePresentation),
                environment: EnvironmentValues()
            ))
    }
}
