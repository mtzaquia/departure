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
    /// Marks a branch view as the host for matching branched route declarations.
    ///
    /// ```swift
    /// HomeView()
    ///     .routeBranch(AppTab.home)
    /// ```
    ///
    /// - Important: The value must match a ``Branch`` value declared by
    ///   ``SwiftUICore/View/routes(id:branch:_:)``.
    func routeBranch<Branch: Hashable>(_ branch: Branch) -> some View {
        modifier(RouteBranchModifier(branch: AnyHashable(branch)))
    }
}

private struct RouteBranchModifier: ViewModifier {
    let branch: AnyHashable

    @State private var branchScope: RouteScope

    @Environment(Router.self) private var router
    @Environment(\.routeScope) private var parentScope
    @Environment(\.branchRouteDeclarations) private var branchRouteDeclarations

    init(branch: AnyHashable) {
        self.branch = branch
        self._branchScope = State(
            wrappedValue: RouteScope(
                id: branch,
                route: nil
            )
        )
    }

    func body(content: Content) -> some View {
        content
            .routes(id: branch, adoptedDeclarations)
            .environment(\.routeScope, branchScope)
            .onLifecycleEvent { event in
                switch event {
                case .installedInWindow, .updated(isInstalledInWindow: true):
                    registerBranchScope()

                case .updated(isInstalledInWindow: false):
                    break

                case .dismantled, .deinitialized:
                    parentScope?.unregisterBranchScope(branchScope, for: branch)
                }
            }
    }

    private func registerBranchScope() {
        guard let parentScope else {
            return
        }

        parentScope.registerBranchScope(branchScope, for: branch)
        router.resumePendingRoute(for: branch, in: parentScope)
    }

    private var adoptedDeclarations: [RouteScopeDeclaration] {
        branchRouteDeclarations
            .filter { $0.branch == branch }
            .map { declaration in
                RouteScopeDeclaration(
                    routes: declaration.routes.map {
                        $0.drivingPresentation(true)
                    }
                )
            }
    }
}
