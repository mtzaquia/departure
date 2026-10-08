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
    let detail = RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }
    let settings = RouteDestination(SettingsRoute.self) { _, _ in EmptyView() }
    let login = RouteDestination(LoginRoute.self) { _, _ in EmptyView() }
    let alert = RouteDestination(AlertRoute.self) { _, _ in EmptyView() }

    @Test func rootPrioritiesApplyOnlyToTopLevelModals() {
        let map = RootRouteMap { Push(detail) } highPriority: {
            Cover(login) { Push(detail); Sheet(settings) }
        } criticalPriority: { Sheet(alert) }
        let definitions = map.declarations.flatMap(\.routes)
        #expect(definitions.map(\.priority) == [.normal, .high, .critical])
        #expect(definitions[1].children.flatMap(\.routes).allSatisfy { $0.priority == .normal })
    }
    @Test func independentlyOptionalPriorityBuilders() {
        let map = RootRouteMap {} criticalPriority: { Cover(alert) }
        #expect(map.declarations.flatMap(\.routes).map(\.priority) == [.critical])
    }
    @Test func composedMapsDoNotIntroduceScopes() {
        let feature = RouteMap { Push(detail); Sheet(settings) }
        let engine = RouterEngine(routes: RootRouteMap { feature })
        #expect(engine.root.routeAttachments.count == 2)
        #expect(engine.root.branchScopes.keys.isEmpty)
        #expect(engine.root.path.isEmpty)
    }
    @Test func branchDefinitionsExistBeforeAnyHostIsMounted() throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches { Branch(AppTab.home) { Push(detail) }; Branch(AppTab.wallet) { Sheet(settings) } }
        })
        let wallet = try #require(engine.root.branchScopes[AppTab.wallet])
        #expect(wallet.routeAttachments.count == 1)
        #expect(!wallet.isInstalledInView)
        #expect(wallet.firstRouteAttachment(for: SettingsRoute.self) != nil)
    }
    @Test func concurrentBranchesShareContainerParticipation() {
        let engine = RouterEngine(routes: RootRouteMap { Branches(concurrent: true) {
            Branch(AppTab.home) { Push(detail) }; Branch(AppTab.wallet) { Sheet(settings) }
        } })
        #expect(engine.root.participates(inBranch: AppTab.home))
        #expect(engine.root.participates(inBranch: AppTab.wallet))
    }
    @Test(arguments: [false, true])
    func duplicateTypeDisablesOnlyConflictingKey(reverse: Bool) async {
        let conflicting = RouteMap { Sheet(settings); Push(settings) }
        let reversed = RouteMap { Push(settings); Sheet(settings) }
        let engine = RouterEngine(routes: RootRouteMap {
            if reverse { reversed } else { conflicting }
            Push(detail)
        })
        let router = Router(engine: engine, scope: engine.root)
        #expect(engine.root.routeAttachments.count == 1)
        guard case .conflict? = engine.root.firstRouteAttachment(for: SettingsRoute.self) else {
            Issue.record("A conflicting route key must remain a lookup barrier")
            return
        }
        await router.present(SettingsRoute())
        #expect(engine.normalSpace.rootPath.isEmpty)
        await router.present(HomeDetailRoute())
        #expect(engine.normalSpace.rootPath.last?.route is HomeDetailRoute)
    }

    @Test func conflictingRouteDoesNotFallBackToAncestorOrSibling() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(settings)
            Push(detail) {
                Branches {
                    Branch("conflicting") { Push(settings); Sheet(settings) }
                    Branch("valid") { Sheet(settings) }
                }
            }
        })
        let root = Router(engine: engine, scope: engine.root)
        await root.present(HomeDetailRoute())
        let scope = try #require(engine.normalSpace.rootPath.last)
        await Router(engine: engine, scope: scope).present(SettingsRoute())
        #expect(engine.normalSpace.rootPath.last === scope)
        #expect(scope.branchScopes.values.allSatisfy { $0.path.isEmpty })
        #expect(scope.activeBranch == AnyHashable("conflicting"))
    }

    @Test func conflictingBranchHasNoRuntimeScopeOrMountOrderWinner() async {
        let engine = RouterEngine(routes: RootRouteMap {
            Branches {
                Branch("duplicate") { Sheet(settings) }
                Branch("duplicate") { Push(detail) }
                Branch("valid") { Push(detail) }
            }
        })
        #expect(engine.root.branchScopes["duplicate"] == nil)
        #expect(engine.root.branchScopes.keys == [AnyHashable("valid")])
        await Router(engine: engine, scope: engine.root).branch("duplicate").present(HomeDetailRoute())
        #expect(engine.root.branchScopes["valid"]?.path.isEmpty == true)
    }

    @Test func duplicateTypeAcrossPriorityCatalogsIsAlsoAConflict() async {
        let engine = RouterEngine(routes: RootRouteMap { Sheet(settings) } highPriority: { Sheet(settings) })
        await Router(engine: engine, scope: engine.root).present(SettingsRoute())
        #expect(engine.root.routeAttachments.isEmpty)
        #expect(engine.normalSpace.rootPath.isEmpty)
        #expect(engine.spaces.highSpace == nil)
    }

    @Test func duplicateTypeIsRecordedAsConflictWithinScope() {
        let engine = RouterEngine(routes: RootRouteMap { Sheet(settings); Push(settings) })
        #expect(engine.root.routeAttachments.isEmpty)
        guard case .conflict? = engine.root.firstRouteAttachment(for: SettingsRoute.self) else {
            Issue.record("Expected a conflicting declaration")
            return
        }
    }
    @Test func routeInstancesShareDefinitionsAndKeepIndependentBranchState() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Sheet(RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }) {
                Branches { Branch("content") { Push(detail) } }
            }
        })
        await engine.present(NumberedRoute(number: 1))
        let first = try #require(engine.normalSpace.rootPath.last)
        await engine.present(NumberedRoute(number: 2))
        let second = try #require(engine.normalSpace.rootPath.last)
        #expect(first !== second)
        #expect(first.definitions === second.definitions)
        #expect(first.branchScopes["content"] !== second.branchScopes["content"])
        #expect(first.branchScopes["content"]?.definitions === second.branchScopes["content"]?.definitions)
    }

    @Test func repeatedFeatureMapHasDistinctDeclarationOccurrences() throws {
        let feature = RouteMap { Push(detail) { Sheet(settings) } }
        let engine = RouterEngine(routes: RootRouteMap {
            Branches { Branch("first") { feature }; Branch("second") { feature } }
        })
        let first = try #require(engine.root.branchScopes["first"]?.routeAttachments.first)
        let second = try #require(engine.root.branchScopes["second"]?.routeAttachments.first)
        #expect(first.identity != second.identity)
        #expect(first.childScope?.routeAttachments.first?.identity != second.childScope?.routeAttachments.first?.identity)
    }

}
