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
struct ElevatedLifetimeTests {
    @Test func removingNormalOriginClearsHighAndDependentCritical() async throws {
        let (router, normal, _, _) = try await makeChain()
        #expect(await router.unwindPrevious(from: normal))
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.routeForest.highTree == nil)
        #expect(router.routeForest.criticalTree == nil)
    }

    @Test func removingHighOriginClearsCriticalButPreservesNormal() async throws {
        let (router, normal, high, _) = try await makeChain()
        #expect(await router.unwindPrevious(from: high))
        #expect(router.normalTree.rootPath.last === normal)
        #expect(router.routeForest.highTree == nil)
        #expect(router.routeForest.criticalTree == nil)
    }

    @Test func elevatedHostTeardownAlsoClearsDependentCritical() async throws {
        let (router, normal, high, _) = try await makeChain()
        router.routeScopeDidInstallInView(high)
        router.routeScopeDidLeaveView(high)
        #expect(router.normalTree.rootPath.last === normal)
        #expect(router.routeForest.highTree == nil)
        #expect(router.routeForest.criticalTree == nil)
    }

    @Test func rootDeclaredCriticalSurvivesRemovalOfUnrelatedOrigins() async throws {
        let (router, normal, _, _) = try await makeChain(criticalAtRoot: true)
        #expect(await router.unwindPrevious(from: normal))
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.routeForest.highTree == nil)
        #expect(router.routeForest.criticalTree != nil)
        #expect(router.elevatedRoutePresentationBinding(priority: .critical, matching: .sheet).wrappedValue != nil)
    }

    @Test func removingBranchContainerClearsBranchDeclaredElevatedChain() async throws {
        let (router, normal, _, _) = try await makeChain(highInBranch: true)
        #expect(await router.unwindPrevious(from: normal))
        #expect(router.normalTree.rootPath.isEmpty)
        #expect(router.routeForest.highTree == nil)
        #expect(router.routeForest.criticalTree == nil)
    }

    private func makeChain(
        criticalAtRoot: Bool = false,
        highInBranch: Bool = false
    ) async throws -> (Router, RouteScope, RouteScope, RouteScope) {
        let router = Router()
        var rootRoutes = Push(HomeDetailRoute.self)._routeDeclarations
        if criticalAtRoot {
            rootRoutes += Sheet(AlertRoute.self, priority: .critical)._routeDeclarations
        }
        router.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: rootRoutes),
        ])
        await router.present(HomeDetailRoute())
        let normal = try #require(router.normalTree.rootPath.last)
        let highOrigin: RouteScope
        if highInBranch {
            let branch = RouteScope(id: "branch", route: nil)
            router.mutateRouteGraph {
                normal.setActiveBranch("branch")
                normal.registerBranchScope(branch, for: "branch")
            }
            highOrigin = branch
        } else {
            highOrigin = normal
        }
        highOrigin.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(LoginRoute.self, priority: .high)._routeDeclarations),
        ])
        await router.present(LoginRoute())
        let high = try #require(router.routeForest.highTree?.rootPath.last)
        if !criticalAtRoot {
            high.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(AlertRoute.self, priority: .critical)._routeDeclarations),
            ])
        }
        await router.present(AlertRoute())
        let critical = try #require(router.routeForest.criticalTree?.rootPath.last)
        return (router, normal, high, critical)
    }
}
