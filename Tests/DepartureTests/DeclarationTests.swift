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

import Testing
@testable import Departure

@MainActor
@Suite
struct DeclarationTests {
    @Test func plainRouteDeclarationsDrivePresentationByDefault() {
        let declarations = RouteDeclarationBuilder.buildBlock(
            RouteDeclarationBuilder.buildExpression(Push(HomeDetailRoute.self)),
            RouteDeclarationBuilder.buildExpression(Sheet(SettingsRoute.self, providesNavigation: false)),
            RouteDeclarationBuilder.buildExpression(Cover(LoginRoute.self, priority: .high))
        )

        #expect(declarations.count == 3)
        #expect(declarations.allSatisfy { $0.branch == nil })
        #expect(declarations.flatMap(\.routes).allSatisfy { $0.drivesPresentation })
        #expect(declarations[0].routes[0].presentationKind == .push)
        #expect(declarations[1].routes[0].presentationKind == .sheet)
        #expect(declarations[1].routes[0].providesNavigation == false)
        #expect(declarations[2].routes[0].priority == .high)
    }

    @Test func branchDeclarationsAreDiscoveryOnlyOnTheParentScope() {
        let declarations = BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
            BranchedRouteDeclarationBuilder<AppTab>.buildExpression(Sheet(SettingsRoute.self)),
            BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                Branch(.home) {
                    Push(HomeDetailRoute.self)
                    Cover(LoginRoute.self, priority: .high)
                }
            )
        )

        #expect(declarations.count == 3)

        #expect(declarations[0].branch == nil)
        #expect(declarations[0].routes[0].drivesPresentation)

        #expect(declarations[1].branch == AnyHashable(AppTab.home))
        #expect(declarations[1].routes[0].routeTypeID == ObjectIdentifier(HomeDetailRoute.self))
        #expect(declarations[1].routes[0].drivesPresentation == false)

        #expect(declarations[2].branch == AnyHashable(AppTab.home))
        #expect(declarations[2].routes[0].routeTypeID == ObjectIdentifier(LoginRoute.self))
        #expect(declarations[2].routes[0].priority == .high)
        #expect(declarations[2].routes[0].drivesPresentation == false)
    }

    @Test func branchRouteDeclarationsCanBeReactivatedForLocalPresentation() {
        let declarations = Branch(AppTab.wallet) {
            Sheet(TransactionRoute.self)
        }.routeScopeDeclarations

        let adopted = declarations.map { declaration in
            RouteScopeDeclaration(
                routes: declaration.routes.map {
                    $0.drivingPresentation(true)
                }
            )
        }

        #expect(declarations[0].branch == AnyHashable(AppTab.wallet))
        #expect(declarations[0].routes[0].drivesPresentation == false)

        #expect(adopted[0].branch == nil)
        #expect(adopted[0].routes[0].routeTypeID == ObjectIdentifier(TransactionRoute.self))
        #expect(adopted[0].routes[0].drivesPresentation)
    }
}
