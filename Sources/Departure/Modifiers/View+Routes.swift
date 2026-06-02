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

public extension View {
    /// Declares routes for the current route scope.
    ///
    /// ```swift
    /// ProfileView()
    ///     .routes {
    ///         Sheet(EditProfileRoute.self)
    ///     }
    /// ```
    ///
    /// - Important: ``id`` is the scope ID used by ``Router/UnwindTarget/id(_:)``.
    func routes<ID: Hashable>(
        id: ID? = AnyHashable?.none,
        @RouteDeclarationBuilder _ declarations: () -> [RouteScopeDeclaration]
    ) -> some View {
        modifier(
            RoutesModifier(
                explicitScopeID: id.map({ AnyHashable($0) }),
                selection: nil,
                declarations: declarations()
            )
        )
    }

    /// Declares routes for a selection-based scope.
    ///
    /// ```swift
    /// TabView(selection: $tab) { ... }
    ///     .routes(branch: $tab) {
    ///         Branch(AppTab.home) {
    ///             Push(HomeDetailRoute.self)
    ///         }
    ///     }
    /// ```
    ///
    /// - Important: Place branch content under ``View/routeBranch(_:)`` so branch-local
    ///   presentations are hosted by the selected branch view.
    func routes<ID: Hashable, Selection: Hashable>(
        id: ID? = AnyHashable?.none,
        branch selection: Binding<Selection>,
        @BranchedRouteDeclarationBuilder<Selection> _ declarations: () -> [RouteScopeDeclaration]
    ) -> some View {
        modifier(
            RoutesModifier(
                explicitScopeID: id.map({ AnyHashable($0) }),
                selection: AnyRouteBranchSelection(selection),
                declarations: declarations()
            )
        )
    }
}

extension View {
    func routes<ID: Hashable>(
        id: ID? = AnyHashable?.none,
        _ declarations: [RouteScopeDeclaration]
    ) -> some View {
        modifier(
            RoutesModifier(
                explicitScopeID: id.map({ AnyHashable($0) }),
                selection: nil,
                declarations: declarations
            )
        )
    }
}

// MARK: - Private

private struct RoutesModifier: ViewModifier {
    let explicitScopeID: AnyHashable?
    let selection: AnyRouteBranchSelection?
    let declarations: [RouteScopeDeclaration]

    @Environment(\.routeScope) private var routeScope
    @Environment(\.branchRouteDeclarations) private var branchRouteDeclarations

    func body(content: Content) -> some View {
        let activeBranch = selection?.value()

        content
            .applyIf(declarations.containsPresentationKind(.push)) {
                $0.modifier(PushPresentationStyleModifier())
            }
            .applyIf(declarations.containsPresentationKind(.sheet)) {
                $0.modifier(SheetPresentationStyleModifier())
            }
            .applyIf(declarations.containsPresentationKind(.cover(.slide))) {
                $0.modifier(CoverSlidePresentationStyleModifier())
            }
            .applyIf(declarations.containsPresentationKind(.cover(.fade))) {
                $0.modifier(CoverFadePresentationStyleModifier())
            }
            .environment(\.branchRouteDeclarations, accumulatedBranchRouteDeclarations)
            .onLifecycleEvent { event in
                guard case .installedInWindow = event else {
                    return
                }

                hydrateScope()
            }
            .onChange(of: activeBranch) { _, _ in // TODO: Review whether this is reliable enough
                hydrateScope()
            }
    }

    private func hydrateScope() {
        routeScope?.hydrateRoutes(
            id: explicitScopeID,
            branchSelection: selection,
            routeDeclarations: declarations
        )
    }

    private var accumulatedBranchRouteDeclarations: [RouteScopeDeclaration] {
        branchRouteDeclarations + declarations.filter { $0.branch != nil }
    }
}
