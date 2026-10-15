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

@MainActor @Suite struct DeclarationTests {
    let detail = testDestination(HomeDetailRoute.self)
    let settings = testDestination(SettingsRoute.self)
    let login = testDestination(LoginRoute.self)
    let alert = testDestination(AlertRoute.self)

    @Test func rootPrioritiesApplyOnlyToTopLevelModals() {
        let map = RootRouteMap {
 testPush(detail)
            HighPriority {
                testCover(login) { testPush(detail); testSheet(settings) }
            }
            CriticalPriority { testSheet(alert) }
        }
        let definitions = map.declarations.flatMap(\.routes)
        #expect(definitions.map(\.priority) == [.default, .high, .critical])
        #expect(definitions[1].children.flatMap(\.routes).allSatisfy { $0.priority == .default })
    }
    @Test func rootPriorityGroupsCanBeDeclaredIndependently() {
        let map = RootRouteMap {
            CriticalPriority { testCover(alert) }
        }
        #expect(map.declarations.flatMap(\.routes).map(\.priority) == [.critical])
    }
    @Test func composedMapsDoNotIntroduceScopes() {
        let feature = RouteMap { testPush(detail); testSheet(settings) }
        let engine = RouterEngine(routes: RootRouteMap { feature })
        #expect(engine.root.routeAttachments.count == 2)
        #expect(engine.root.branchScopes.keys.isEmpty)
        #expect(engine.root.path.isEmpty)
    }
    @Test func modalMapsComposeAndKeepChildrenLocal() {
        let nested = ModalRouteMap { testCover(login) { testPush(detail) } }
        let entries = ModalRouteMap { nested; testSheet(settings) }
        let engine = RouterEngine(routes: RootRouteMap {
            HighPriority { entries }
            CriticalPriority { ModalRouteMap { testSheet(alert) } }
        })
        #expect(engine.root.routeAttachments.map(\.priority) == [.high, .high, .critical])
        #expect(engine.root.definitions.presentationStyles == [.cover(.slide), .sheet])
        let children = engine.root.definitions.routeBinding(for: LoginRoute.self)?.declaration?.childScope
        #expect(children?.routeBinding(for: HomeDetailRoute.self)?.declaration?.priority == .default)
        #expect(children?.presentationStyles == [.push])
        #expect(engine.root.branchScopes.keys.isEmpty)
    }

    @Test func mapIDsDistinguishRepeatedRouteTypesInOnePath() async throws {
        let numbered = testDestination(NumberedRoute.self)
        let engine = RouterEngine(routes: RootRouteMap(id: "app") {
            testPush(numbered) {
                RouteMap(id: "outer-detail") {
                    testPush(numbered) {
                        RouteMap(id: "inner-detail") { testPush(settings) }
                    }
                }
            }
        })
        await engine.present(NumberedRoute(number: 1))
        await engine.present(NumberedRoute(number: 2))
        let outer = try #require(engine.defaultSpace.rootPath.first)
        let inner = try #require(engine.defaultSpace.rootPath.last)
        #expect(outer !== inner)
        #expect(outer.id == AnyHashable("outer-detail"))
        #expect(inner.id == AnyHashable("inner-detail"))
        await engine.present(SettingsRoute())
        #expect(await Router(engine: engine).unwind(from: SettingsRoute.self))
        #expect(engine.defaultSpace.rootPath.last === inner)
        #expect(await Router(engine: engine).unwind(from: NumberedRoute.self))
        #expect(engine.defaultSpace.rootPath.scopes.count == 1)
        #expect(engine.defaultSpace.rootPath.last === outer)
    }

    @Test func mapIDsNameRootsAndBranchesWithoutCreatingScopes() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            RouteMap(id: "app") {
                Branches {
                    Branch(AppTab.home) {
                        RouteMap(id: "home-flow") { testPush(detail) }
                    }
                }
                testSheet(settings)
            }
        })
        #expect(engine.root.id == AnyHashable("app"))
        let home = try #require(engine.root.branchScopes[AppTab.home])
        #expect(home.id == AnyHashable("home-flow"))
        #expect(home.branchID == AnyHashable(AppTab.home))
        #expect(engine.root.routeAttachments.count == 1)
        await Router(engine: engine, scope: engine.root).branch(AppTab.home).present(HomeDetailRoute())
        let child = try #require(home.path.last)
        #expect(await Router(engine: engine, scope: child).unwind(.current))
        #expect(home.path.isEmpty)
        #expect(engine.root.branchScopes[AppTab.home] === home)
    }

    @Test func mapIDsNameElevatedRoots() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            HighPriority {
                ModalRouteMap { testSheet(login) { RouteMap(id: "authentication") { testPush(detail) } } }
            }
        })
        await engine.present(LoginRoute())
        let space = try #require(engine.spaces.highSpace)
        #expect(space.root.id == AnyHashable("authentication"))
        await engine.present(HomeDetailRoute())
        #expect(await engine.resetToRoot())
        #expect(engine.spaces.highSpace === space)
        #expect(space.rootPath.isEmpty)
    }

    @Test(arguments: [false, true])
    func conflictingMapIDsRemoveTheExplicitIDButKeepDefinitions(sameID: Bool) async {
        let engine = RouterEngine(routes: RootRouteMap {
            testPush(detail) {
                RouteMap(id: "first") { testPush(settings) }
                RouteMap(id: sameID ? "first" : "second") {}
            }
        })
        await engine.present(HomeDetailRoute())
        let scope = engine.defaultSpace.rootPath.last!
        #expect(scope.id != AnyHashable("first"))
        #expect(scope.id != AnyHashable("second"))
        #expect(scope.id != AnyHashable(HomeDetailRoute().id))
        await engine.present(SettingsRoute())
        #expect(engine.defaultSpace.rootPath.scopes.count == 2)
    }

    @Test func mapIDConflictsWithASecondExplicitRootOrDestinationID() {
        let root = RouterEngine(routes: RootRouteMap(id: "root") { RouteMap(id: "other") {} })
        guard case .conflict? = root.root.definitions.scopeID else {
            Issue.record("A root and an inlined map cannot both name one scope")
            return
        }
        let destination = RouteDefinitions([.init(routes: testPush(detail, id: "route") {
            RouteMap(id: "map") {}
        }._routeDeclarations)]).routeBinding(for: HomeDetailRoute.self)?.declaration?.childScope
        guard case .conflict? = destination?.scopeID else {
            Issue.record("A destination and its map cannot both name one scope")
            return
        }
    }

    @Test func branchBuilderSupportsControlFlowAndSiblingRoutes() {
        let branches = [AppTab.home, .wallet]
        let engine = RouterEngine(routes: RootRouteMap {
            testSheet(settings)
            Branches(concurrent: true) {
                for branch in branches { Branch(branch) { testPush(detail) } }
                if false { Branch("unused") {} }
            }
        })
        #expect(engine.root.routeAttachments.count == 1)
        #expect(engine.root.branchScopes.keys == branches.map(AnyHashable.init))
        #expect(engine.root.isConcurrent)
    }
    @Test func branchDefinitionsExistBeforeAnyHostIsMounted() throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches { Branch(AppTab.home) { testPush(detail) }; Branch(AppTab.wallet) { testSheet(settings) } }
        })
        let wallet = try #require(engine.root.branchScopes[AppTab.wallet])
        #expect(engine.root.definitions.presentationStyles.isEmpty)
        #expect(wallet.definitions.presentationStyles == [.sheet])
        #expect(wallet.routeAttachments.count == 1)
        #expect(!wallet.isInstalledInView)
        #expect(wallet.definitions.routeBinding(for: SettingsRoute.self) != nil)
    }
    @Test func concurrentBranchesShareContainerParticipation() {
        let engine = RouterEngine(routes: RootRouteMap { Branches(concurrent: true) {
            Branch(AppTab.home) { testPush(detail) }; Branch(AppTab.wallet) { testSheet(settings) }
        } })
        #expect(engine.root.participates(inBranch: AppTab.home))
        #expect(engine.root.participates(inBranch: AppTab.wallet))
    }

    @Test(arguments: [false, true], [false, true])
    func aScopeRejectsMultipleBranchGroupsEvenWhenTheirConcurrencyAgrees(concurrent: Bool, composed: Bool) async {
        let feature = RouteMap {
            Branches(concurrent: concurrent) { Branch("second") { testSheet(settings) } }
        }
        let engine = RouterEngine(routes: RootRouteMap {
            Branches(concurrent: concurrent) { Branch("first") { testPush(detail) } }
            if composed { feature }
            else { Branches(concurrent: !concurrent) { Branch("second") { testSheet(settings) } } }
            testSheet(login)
        })
        guard case .conflict? = engine.root.definitions.branchContainer else {
            Issue.record("A receiving scope must accept exactly one Branches group")
            return
        }
        #expect(engine.root.branchScopes.keys.isEmpty)
        await engine.present(HomeDetailRoute())
        #expect(engine.defaultSpace.rootPath.isEmpty)
        await engine.present(LoginRoute())
        #expect(engine.defaultSpace.rootPath.last?.route is LoginRoute)
    }

    @Test func composedMapContributesOneContainerWithItsOwnConcurrency() async throws {
        let feature = RouteMap {
            Branches(concurrent: true) {
                Branch("first") { testPush(detail) }
                Branch("second") { testPush(settings) }
            }
        }
        let engine = RouterEngine(routes: RootRouteMap { feature })
        #expect(engine.root.isConcurrent)
        let router = Router(engine: engine, scope: engine.root)
        await router.branch("first").present(HomeDetailRoute())
        await router.branch("second").present(SettingsRoute())
        #expect(engine.root.branchScopes["first"]?.path.last?.route is HomeDetailRoute)
        #expect(engine.root.branchScopes["second"]?.path.last?.route is SettingsRoute)
        #expect(engine.pendingRoute == nil)
    }
    @Test(arguments: [false, true])
    func duplicateTypeDisablesOnlyConflictingKey(reverse: Bool) async {
        let conflicting = RouteMap { testSheet(settings); testPush(settings) }
        let reversed = RouteMap { testPush(settings); testSheet(settings) }
        let engine = RouterEngine(routes: RootRouteMap {
            if reverse { reversed } else { conflicting }
            testPush(detail)
        })
        let router = Router(engine: engine, scope: engine.root)
        #expect(engine.root.routeAttachments.count == 1)
        #expect(engine.root.definitions.presentationStyles == [.push])
        guard case .conflict? = engine.spaces.firstDeclaration(including: SettingsRoute.self) else {
            Issue.record("A conflicting route key must remain a lookup barrier")
            return
        }
        await router.present(SettingsRoute())
        #expect(engine.defaultSpace.rootPath.isEmpty)
        await router.present(HomeDetailRoute())
        #expect(engine.defaultSpace.rootPath.last?.route is HomeDetailRoute)
    }

    @Test func conflictingRouteDoesNotFallBackToAncestorOrSibling() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            testSheet(settings)
            testPush(detail) {
                Branches {
                    Branch("conflicting") { testPush(settings); testSheet(settings) }
                    Branch("valid") { testSheet(settings) }
                }
            }
        })
        let root = Router(engine: engine, scope: engine.root)
        await root.present(HomeDetailRoute())
        let scope = try #require(engine.defaultSpace.rootPath.last)
        await Router(engine: engine, scope: scope).present(SettingsRoute())
        #expect(engine.defaultSpace.rootPath.last === scope)
        #expect(scope.branchScopes.values.allSatisfy { $0.path.isEmpty })
        #expect(scope.activeBranch == AnyHashable("conflicting"))
    }

    @Test func conflictingBranchHasNoRuntimeScopeOrMountOrderWinner() async {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches {
                Branch("duplicate") { testSheet(settings) }
                Branch("duplicate") { testPush(detail) }
                Branch("valid") { testPush(detail) }
            }
        })
        #expect(engine.root.branchScopes["duplicate"] == nil)
        #expect(engine.root.branchScopes.keys == [AnyHashable("valid")])
        await Router(engine: engine, scope: engine.root).branch("duplicate").present(HomeDetailRoute())
        #expect(engine.root.branchScopes["valid"]?.path.isEmpty == true)
    }

    @Test func duplicateTypeAcrossPriorityCatalogsIsAlsoAConflict() async {
        let engine = RouterEngine(routes: RootRouteMap {
 testSheet(settings)
            HighPriority { testSheet(settings) }
        })
        await Router(engine: engine, scope: engine.root).present(SettingsRoute())
        #expect(engine.root.routeAttachments.isEmpty)
        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(engine.spaces.highSpace == nil)
    }

    @Test func duplicateTypeIsRecordedAsConflictWithinScope() {
        let engine = RouterEngine(routes: RootRouteMap { testSheet(settings); testPush(settings) })
        #expect(engine.root.routeAttachments.isEmpty)
        guard case .conflict? = engine.spaces.firstDeclaration(including: SettingsRoute.self) else {
            Issue.record("Expected a conflicting declaration")
            return
        }
    }
    @Test func routeInstancesShareDefinitionsAndKeepIndependentBranchState() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            testSheet(testDestination(NumberedRoute.self)) {
                Branches { Branch("content") { testPush(detail) } }
            }
        })
        await engine.present(NumberedRoute(number: 1))
        let first = try #require(engine.defaultSpace.rootPath.last)
        await engine.present(NumberedRoute(number: 2))
        let second = try #require(engine.defaultSpace.rootPath.last)
        #expect(first !== second)
        #expect(first.definitions === second.definitions)
        #expect(first.branchScopes["content"] !== second.branchScopes["content"])
        #expect(first.branchScopes["content"]?.definitions === second.branchScopes["content"]?.definitions)
    }

    @Test func repeatedFeatureMapHasDistinctDeclarationOccurrences() throws {
        let feature = RouteMap { testPush(detail) { testSheet(settings) } }
        let engine = RouterEngine(routes: RootRouteMap {
            Branches { Branch("first") { feature }; Branch("second") { feature } }
        })
        let first = try #require(engine.root.branchScopes["first"]?.routeAttachments.first)
        let second = try #require(engine.root.branchScopes["second"]?.routeAttachments.first)
        #expect(first.identity != second.identity)
        #expect(first.childScope?.routeAttachments.first?.identity != second.childScope?.routeAttachments.first?.identity)
    }

}
