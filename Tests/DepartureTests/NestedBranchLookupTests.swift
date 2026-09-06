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
struct NestedBranchLookupTests {
    @Test(arguments: [false, true])
    func enclosingLocalDeclarationWinsOverLazyContainer(hasLazyDeclaration: Bool) async throws {
        let (router, outer, _) = makeNestedBranches(hasLazyDeclaration: hasLazyDeclaration)
        outer.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
        ])
        outer.setActiveBranch("inner")

        let match = try #require(router.routeForest.firstDeclaration(including: SettingsRoute.self))
        #expect(match.presentationHost === outer)
        #expect(match.lookupStrategy == .ancestorPath(treePriority: .normal))
        #if DEBUG
        #expect(DepartureLogEvent.routeMatched(route: SettingsRoute(), match: match).message.contains(
            "lookup=enclosing branch path in normal tree, nearest scope first"
        ))
        #endif
        #expect(match.declaration.presentationKind == .sheet)
        await router.present(SettingsRoute())
        #expect(outer.path.last?.route is SettingsRoute)
        #expect(router.routePresentation(from: outer, matching: .sheet) != nil)
        #expect(router.normalTree.rootPath.isEmpty)
    }

    @Test func innermostLocalDeclarationStillWins() async throws {
        let (router, outer, inner) = makeNestedBranches(hasLazyDeclaration: true)
        outer.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
        ])
        outer.setActiveBranch("inner")
        inner.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Cover(SettingsRoute.self)._routeDeclarations),
        ])

        let match = try #require(router.routeForest.firstDeclaration(including: SettingsRoute.self))
        #expect(match.presentationHost === inner)
        await router.present(SettingsRoute())
        #expect(inner.path.last?.route is SettingsRoute)
        #expect(router.routePresentation(from: inner, matching: .cover(.slide)) != nil)
        #expect(outer.path.isEmpty)
    }

    @Test func lazyDeclarationRemainsAvailableWithoutLocalOverride() async throws {
        let (router, outer, inner) = makeNestedBranches(hasLazyDeclaration: true)
        let match = try #require(router.routeForest.firstDeclaration(including: SettingsRoute.self))
        #expect(match.presentationHost === outer)
        await router.present(SettingsRoute())
        #expect(outer.path.last?.route is SettingsRoute)
        #expect(router.routePresentation(from: outer, matching: .push) != nil)
        #expect(inner.path.isEmpty)
    }

    @Test func enclosingPushedScopeParticipatesInDiscovery() async throws {
        let (router, outer, inner) = makeNestedBranches(hasLazyDeclaration: true)
        outer.unregisterBranchScope(inner, for: "inner")
        let container = RouteScope(id: "container", route: HomeDetailRoute())
        container.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
        ])
        router.mutateRouteGraph {
            outer.path.append(container)
            container.setActiveBranch("inner")
            container.registerBranchScope(inner, for: "inner")
        }

        #expect(router.currentRouteScope === inner)
        let match = try #require(router.routeForest.firstDeclaration(including: SettingsRoute.self))
        #expect(match.presentationHost === container)
        await router.present(SettingsRoute())
        #expect(outer.path.first === container)
        #expect(outer.path.last?.route is SettingsRoute)
        #expect(router.routePresentation(from: container, matching: .sheet) != nil)
    }

    private func makeNestedBranches(hasLazyDeclaration: Bool) -> (Router, RouteScope, RouteScope) {
        let router = Router()
        let outer = RouteScope(id: "outer", route: nil)
        let inner = RouteScope(id: "inner", route: nil)
        if hasLazyDeclaration {
            router.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations:
                Branch("outer") { Push(SettingsRoute.self) }.routeScopeDeclarations
            )
        }
        router.mutateRouteGraph {
            router.root.setActiveBranch("outer")
            router.root.registerBranchScope(outer, for: "outer")
            outer.setActiveBranch("inner")
            outer.registerBranchScope(inner, for: "inner")
        }
        return (router, outer, inner)
    }
}
