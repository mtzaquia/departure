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

@MainActor @Suite struct PresentationHostOwnershipTests {
    @Test(arguments: [false, true])
    func duplicateExplicitHostsDisablePresentationUntilOneRemains(removeFirst: Bool) async {
        let engine = RouterEngine(routes: RootRouteMap { Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() }) })
        let first = RoutePresentationHostID(), second = RoutePresentationHostID(), automatic = RoutePresentationHostID()
        let scope = engine.root
        scope.bindRoutingHost(automatic, automatic: true, environment: scope.sourceEnvironment)
        scope.bindRoutingHost(first, automatic: false, environment: scope.sourceEnvironment)
        scope.bindRoutingHost(second, automatic: false, environment: scope.sourceEnvironment)
        #expect(scope.hasConflictingPresentationHosts)
        #expect(scope.presentationHostID == nil)
        await engine.present(SettingsRoute())
        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(engine.routePresentationBinding(from: scope, matching: .sheet).wrappedValue == nil)
        scope.unbindRoutingHost(removeFirst ? first : second)
        #expect(!scope.hasConflictingPresentationHosts)
        #expect(scope.presentationHostID == (removeFirst ? second : first))
        await engine.present(SettingsRoute())
        #expect(engine.routePresentationBinding(from: scope, matching: .sheet, hostedBy: scope.presentationHostID).wrappedValue?.scope === engine.defaultSpace.rootPath.last)
    }

    @Test func ambiguousAutomaticHostsRequireAnExplicitOwner() {
        let scope = RouteScope(id: "root", route: nil)
        let first = RoutePresentationHostID(), second = RoutePresentationHostID(), explicit = RoutePresentationHostID()
        scope.bindRoutingHost(first, automatic: true, environment: scope.sourceEnvironment)
        scope.bindRoutingHost(second, automatic: true, environment: scope.sourceEnvironment)
        #expect(scope.hasConflictingPresentationHosts)
        #expect(scope.presentationHostID == nil)
        scope.bindRoutingHost(explicit, automatic: false, environment: scope.sourceEnvironment)
        #expect(!scope.hasConflictingPresentationHosts)
        #expect(scope.presentationHostID == explicit)
        scope.unbindRoutingHost(explicit)
        #expect(scope.hasConflictingPresentationHosts)
    }
    @Test func explicitPhysicalHostWinsAndRestoresAutomaticHost() {
        let scope = RouteScope(id: "root", route: nil)
        let automatic = RoutePresentationHostID(), explicit = RoutePresentationHostID()
        var original = EnvironmentValues(), nested = EnvironmentValues()
        original.routeScope = scope
        let nestedScope = RouteScope(id: "nested", route: nil)
        nested.routeScope = nestedScope
        scope.bindRoutingHost(explicit, automatic: false, environment: nested)
        scope.bindRoutingHost(automatic, automatic: true, environment: original)
        #expect(scope.presentationHostID == explicit)
        #expect(scope.sourceEnvironment.routeScope === nested.routeScope)
        scope.unbindRoutingHost(explicit)
        #expect(scope.presentationHostID == automatic)
        #expect(scope.sourceEnvironment.routeScope === scope)
        scope.unbindRoutingHost(automatic)
        #expect(scope.presentationHostID == nil)
    }

    @Test(arguments: [RoutePresentation.Style.push, .sheet, .cover(.slide), .cover(.fade), .replace])
    func bindingWriteBackIsAcceptedOnlyFromOwningHost(style: RoutePresentation.Style) async throws {
        let destination = RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }
        let engine = RouterEngine(routes: RootRouteMap {
            AnyRouteDeclaration(destination, presentation: .init(style: style, priority: .default))
        })
        let owner = RoutePresentationHostID(), stranger = RoutePresentationHostID()
        engine.root.bindRoutingHost(owner, automatic: false, environment: engine.root.sourceEnvironment)
        await engine.present(NumberedRoute(number: 1))
        let scope = try #require(engine.defaultSpace.rootPath.last)
        // An unseen iOS 17 push rejects nil intentionally. Model an actual
        // destination that has appeared and is now leaving its native host.
        engine.routeScopeDidInstallInView(scope)
        engine.routeScopeDidLeaveView(scope)
        let foreign = engine.routePresentationBinding(from: engine.root, matching: style, hostedBy: stranger)
        #expect(foreign.wrappedValue == nil)
        foreign.wrappedValue = nil
        #expect(engine.defaultSpace.rootPath.last === scope)
        let binding = engine.routePresentationBinding(from: engine.root, matching: style, hostedBy: owner)
        #expect(binding.wrappedValue?.scope === scope)
        binding.wrappedValue = nil
        #expect(engine.defaultSpace.rootPath.isEmpty)
    }
    @Test func staleDefaultDismissalCannotClearReplacement() async throws {
        let engine = RouterEngine(routes: RootRouteMap { Sheet(RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }) })
        await engine.present(NumberedRoute(number: 1))
        let oldBinding = engine.routePresentationBinding(from: engine.root, matching: .sheet)
        await engine.present(NumberedRoute(number: 2))
        let replacement = try #require(engine.defaultSpace.rootPath.last)
        oldBinding.wrappedValue = nil
        #expect(engine.defaultSpace.rootPath.last === replacement)
    }
    @Test(arguments: [RoutePriority.high, .critical])
    func staleElevatedDismissalCannotClearReplacement(priority: RoutePriority) async throws {
        let destination = RouteDestination(NumberedRoute.self) { _, _ in EmptyView() }
        let engine = RouterEngine(routes: RootRouteMap {} highPriority: {
            if priority == .high { Sheet(destination) }
        } criticalPriority: {
            if priority == .critical { Sheet(destination) }
        })
        await engine.present(NumberedRoute(number: 1))
        let old = engine.elevatedRoutePresentationBinding(priority: priority, matching: .sheet)
        await engine.present(NumberedRoute(number: 2))
        let replacement = try #require(engine.spaces.space(for: priority)?.root)
        old.wrappedValue = nil
        #expect(engine.spaces.space(for: priority)?.root === replacement)
    }
    @Test func branchDeclarationsUseTheBranchBindingHost() async throws {
        let engine = RouterEngine(routes: RootRouteMap { Branches { Branch(AppTab.home) {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
        } } })
        let branch = try #require(engine.root.branchScopes[AppTab.home])
        let host = RoutePresentationHostID()
        branch.bindRoutingHost(host, automatic: false, environment: branch.sourceEnvironment)
        await Router(engine: engine, scope: branch).present(SettingsRoute())
        let scope = try #require(branch.path.last)
        #expect(engine.routePresentationBinding(from: branch, matching: .sheet, hostedBy: host).wrappedValue?.scope === scope)
        #expect(engine.routePresentationBinding(from: engine.root, matching: .sheet).wrappedValue == nil)
    }
}
