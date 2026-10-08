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
    func publicBranchPushBehindModalKeepsItsExactAnchor(declaredAtBranchRoot: Bool) async throws {
        let owner = RootRouter()
        let settings = RouteDestination(SettingsRoute.self) { _, _ in EmptyView() }
        _ = WithRouter(routes: RootRouteMap {
            Sheet(RouteDestination(MessageRoute.self) { _, _ in EmptyView() })
            Branches {
                Branch("wallet") {
                    if declaredAtBranchRoot { Push(settings) }
                    Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }) {
                        if !declaredAtBranchRoot { Push(settings) }
                    }
                }
            }
        }, router: owner) { EmptyView() }
        let engine = owner.engine
        let branch = try #require(engine.root.branchScopes["wallet"])
        await owner.default.present(HomeDetailRoute())
        let detail = try #require(branch.path.last)
        await owner.default.present(MessageRoute())
        let modal = try #require(engine.defaultSpace.rootPath.last)
        let match = try #require(engine.spaces.firstDeclaration(including: SettingsRoute.self)?.declaration)
        #expect(match.presentingScope === (declaredAtBranchRoot ? branch : detail))
        #expect(match.declaringScope === engine.root)
        #expect(match.branchID == AnyHashable("wallet"))

        await owner.default.present(SettingsRoute())
        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(engine.spaces.routePath(containing: modal) == nil)
        #expect(branch.path.count == (declaredAtBranchRoot ? 1 : 2))
        #expect(branch.path.last?.route is SettingsRoute)
        #expect(branch.path.last?.presentationOrigin === match.presentingScope)
        #expect((engine.spaces.routePath(containing: detail) != nil) == !declaredAtBranchRoot)
    }

    @Test func publicSelectedNestedDestinationKeepsItsOuterContainerAnchor() async throws {
        let owner = RootRouter()
        _ = WithRouter(routes: RootRouteMap {
            Sheet(RouteDestination(MessageRoute.self) { _, _ in EmptyView() })
            Branches {
                Branch("outer") {
                    Branches {
                        Branch("inner") {
                            Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }) {
                                Push(RouteDestination(SettingsRoute.self) { _, _ in EmptyView() })
                            }
                        }
                    }
                }
            }
        }, router: owner) { EmptyView() }
        let engine = owner.engine
        let outer = try #require(engine.root.branchScopes["outer"])
        let inner = try #require(outer.branchScopes["inner"])
        await owner.default.present(HomeDetailRoute())
        let detail = try #require(inner.path.last)
        await owner.default.present(MessageRoute())
        let match = try #require(engine.spaces.firstDeclaration(including: SettingsRoute.self)?.declaration)
        #expect(match.presentingScope === detail)
        #expect(match.declaringScope === engine.root)
        #expect(match.branchID == AnyHashable("outer"))
        await owner.default.present(SettingsRoute())
        #expect(engine.defaultSpace.rootPath.isEmpty)
        #expect(inner.path.first === detail)
        #expect(inner.path.count == 2)
        #expect(inner.path.last?.presentationOrigin === detail)
    }

    @Test(arguments: [false, true])
    func enclosingLocalDeclarationWinsOverLazyContainer(hasLazyDeclaration: Bool) async throws {
        let (router, outer, _) = makeNestedBranches(hasLazyDeclaration: hasLazyDeclaration)
        outer.defineTestMap(id: nil, selection: nil, definitions: [
            RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
        ])
        outer.setActiveBranch("inner")

        let match = try #require(router.spaces.firstDeclaration(including: SettingsRoute.self)?.declaration)
        #expect(match.presentingScope === outer)
        #expect(match.lookupStrategy == .currentPath(spacePriority: .default))
        #if DEBUG
        #expect(DepartureLogEvent.routeMatched(route: SettingsRoute(), match: match).message.contains(
            "lookup=current route path in default space, nearest scope first"
        ))
        #endif
        #expect(match.declaration.presentationKind == .sheet)
        await router.present(SettingsRoute())
        #expect(outer.path.last?.route is SettingsRoute)
        #expect(router.routePresentation(from: outer, matching: .sheet) != nil)
        #expect(router.defaultSpace.rootPath.isEmpty)
    }

    @Test func innermostLocalDeclarationStillWins() async throws {
        let (router, outer, inner) = makeNestedBranches(hasLazyDeclaration: true)
        outer.defineTestMap(id: nil, selection: nil, definitions: [
            RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
        ])
        outer.setActiveBranch("inner")
        inner.defineTestMap(id: nil, selection: nil, definitions: [
            RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .cover(.slide), priority: .default))._routeDeclarations),
        ])

        let match = try #require(router.spaces.firstDeclaration(including: SettingsRoute.self)?.declaration)
        #expect(match.presentingScope === inner)
        await router.present(SettingsRoute())
        #expect(inner.path.last?.route is SettingsRoute)
        #expect(router.routePresentation(from: inner, matching: .cover(.slide)) != nil)
        #expect(outer.path.isEmpty)
    }

    @Test func lazyDeclarationRemainsAvailableWithoutLocalOverride() async throws {
        let (router, outer, inner) = makeNestedBranches(hasLazyDeclaration: true)
        let match = try #require(router.spaces.firstDeclaration(including: SettingsRoute.self)?.declaration)
        #expect(match.presentingScope === outer)
        await router.present(SettingsRoute())
        #expect(outer.path.last?.route is SettingsRoute)
        #expect(router.routePresentation(from: outer, matching: .push) != nil)
        #expect(inner.path.isEmpty)
    }

    @Test func enclosingPushedScopeParticipatesInDiscovery() async throws {
        let (router, outer, inner) = makeNestedBranches(hasLazyDeclaration: true)
        outer.detachTestBranch(inner, for: "inner")
        let container = RouteScope(id: "container", route: HomeDetailRoute())
        container.defineTestMap(id: nil, selection: nil, definitions: [
            RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .sheet, priority: .default))._routeDeclarations),
        ])
        router.mutateRouteGraph {
            outer.path.append(container)
            container.setActiveBranch("inner")
            container.attachTestBranch(inner, for: "inner")
        }

        #expect(router.currentRouteScope === inner)
        let match = try #require(router.spaces.firstDeclaration(including: SettingsRoute.self)?.declaration)
        #expect(match.presentingScope === container)
        await router.present(SettingsRoute())
        #expect(outer.path.first === container)
        #expect(outer.path.last?.route is SettingsRoute)
        #expect(router.routePresentation(from: container, matching: .sheet) != nil)
    }

    private func makeNestedBranches(hasLazyDeclaration: Bool) -> (RouterEngine, RouteScope, RouteScope) {
        let router = RouterEngine()
        let outer = RouteScope(id: "outer", route: nil)
        let inner = RouteScope(id: "inner", route: nil)
        if hasLazyDeclaration {
            router.root.defineTestMap(id: nil, selection: nil, definitions:
                Branch("outer") { AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, presentation: .init(style: .push, priority: .default)) }.routeScopeDeclarations
            )
        }
        router.mutateRouteGraph {
            router.root.setActiveBranch("outer")
            router.root.attachTestBranch(outer, for: "outer")
            outer.setActiveBranch("inner")
            outer.attachTestBranch(inner, for: "inner")
        }
        return (router, outer, inner)
    }
}
