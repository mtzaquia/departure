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

/// A sheet presented from the same origin replaces the previous one even when that
/// previous sheet has not been installed in a view yet.
@MainActor @Suite
struct SheetReplacementTests {
    @Test func rootSheetReplacementBeforeInstallationKeepsOnlyTheSuccessor() async throws {
        let engine = RouterEngine()
        let router = Router(engine: engine, scope: engine.root)
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(NumberedRoute.self)._routeDeclarations),
        ])

        await router.present(NumberedRoute(number: 1))
        await router.present(NumberedRoute(number: 2))

        #expect(numbers(in: engine.normalTree.rootPath) == [2])
    }

    @Test func branchSheetReplacementBeforeInstallationKeepsOnlyTheSuccessor() async throws {
        let engine = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        engine.root.installRouteDeclarations(
            id: nil,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) { Sheet(NumberedRoute.self) }
                )
            )
        )
        engine.root.registerBranchScope(homeScope, for: AppTab.home)
        let router = Router(engine: engine, scope: homeScope)

        await router.present(NumberedRoute(number: 1))
        await router.present(NumberedRoute(number: 2))

        #expect(numbers(in: homeScope.path) == [2])
    }

    @Test func pushedHostSheetReplacementBeforeInstallationKeepsOnlyTheSuccessor() async throws {
        let engine = RouterEngine()
        engine.root.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
        ])
        await Router(engine: engine, scope: engine.root).present(SettingsRoute())
        let host = try #require(engine.normalTree.rootPath.last)
        engine.routeScopeDidInstallInView(host)
        host.installRouteDeclarations(id: nil, branchSelection: nil, routeDeclarations: [
            RouteScopeDeclaration(routes: Sheet(NumberedRoute.self)._routeDeclarations),
        ])
        let router = Router(engine: engine, scope: host)

        await router.present(NumberedRoute(number: 1))
        await router.present(NumberedRoute(number: 2))

        #expect(numbers(in: engine.normalTree.rootPath) == [2])
        #expect(engine.normalTree.rootPath.scopes.first === host)
    }

    private func numbers(in path: RoutePath) -> [Int] {
        path.scopes.compactMap { ($0.route as? NumberedRoute)?.number }
    }
}
