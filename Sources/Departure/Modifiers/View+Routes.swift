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

import Foundation
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
    /// - Important: `id` is the scope ID used by ``Router/UnwindTarget/id(_:)``.
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
    /// Set `concurrent` for containers whose branches participate together, such as
    /// split views. The selection binding identifies the branch to reveal during
    /// programmatic navigation; changing it does not clear other branch paths.
    /// In a split view, connect it to the preferred compact column, or adapt an
    /// app-defined branch value to the container's visibility state.
    /// Keep this enabled when a split view collapses; it describes the container,
    /// rather than the size class or number of currently visible columns.
    ///
    /// - Parameter concurrent: Whether all registered branches participate together.
    /// - Important: Place branch content under ``SwiftUICore/View/routeBranch(_:)`` so branch-local
    ///   presentations are hosted by the selected branch view.
    func routes<ID: Hashable, Selection: Hashable>(
        id: ID? = AnyHashable?.none,
        branch selection: Binding<Selection>,
        concurrent: Bool = false,
        @BranchedRouteDeclarationBuilder<Selection> _ declarations: () -> [RouteScopeDeclaration]
    ) -> some View {
        modifier(
            RoutesModifier(
                explicitScopeID: id.map({ AnyHashable($0) }),
                selection: AnyRouteBranchSelection(selection, concurrent: concurrent),
                declarations: declarations()
            )
        )
    }
}

// MARK: - Private

private struct RoutesModifier: ViewModifier {
    let explicitScopeID: AnyHashable?
    let selection: AnyRouteBranchSelection?
    let declarations: [RouteScopeDeclaration]

    @State private var presentationHostID = RoutePresentationHostID()
    @State private var attachment = RouteScopeAttachment(kind: .routes)

    @Environment(RouterEngine.self) private var router
    @Environment(\.routeScope) private var routeScope
    @Environment(\.branchRouteDeclarations) private var branchRouteDeclarations
    @Environment(\.self) private var sourceEnvironment

    func body(content: Content) -> some View {
        let activeBranch = selection?.value()

        content
            // Replace changes this content slot; keep declaration injection and registration outside it.
            .modifier(ReplacePresentationStyleModifier(presentationHostID: presentationHostID,
                isEnabled: hostedDeclarations.containsPresentationKind(.replace)))
            .environment(\.branchRouteDeclarations, accumulatedBranchRouteDeclarations)
            .onLifecycleEvent { lifecycleView, _, event in
                switch event {
                case .installedInWindow, .updated(isInstalledInWindow: true):
                    guard let lifecycleView else { return }
                    configureAttachment(view: lifecycleView)

                case .updated(isInstalledInWindow: false):
                    break

                case .dismantled, .deinitialized:
                    attachment.detach()
                }
            }
            .onChange(of: activeBranch) { _, _ in
                configureAttachment()
            }
            .onChange(of: selection?.concurrent) { _, _ in
                configureAttachment()
            }
            .onChange(of: declarations) { _, _ in
                configureAttachment()
            }
            // Presentation hosts live in a detached background layer. They are installed only for
            // the declared styles (so e.g. `navigationDestination` is never attached without a
            // push declaration), which means the host set changes as declarations change. Keeping
            // that conditional structure off the primary content prevents its `_ConditionalContent`
            // churn from tearing down the lifecycle bridge above, which would otherwise uninstall
            // the scope's freshly installed route declarations.
            .background {
                Color.black.frame(width: .zero, height: .zero)
                    .routePresentationStyleModifiers(
                        for: hostedDeclarations,
                        hostedBy: presentationHostID
                    )
            }
    }

    private func configureAttachment(view: PlatformView? = nil) {
        let router = router
        let sourceID = attachment.id
        let explicitScopeID = explicitScopeID
        let selection = selection
        let declarations = hostedDeclarations
        let sourceEnvironment = sourceEnvironment
        let apply: (RouteScope) -> Void = { scope in
            let requiresCommit = scope.prepareRouteDeclarationInstallation(
                sourceID: sourceID,
                id: explicitScopeID,
                branchSelection: selection,
                routeDeclarations: declarations,
                sourceEnvironment: sourceEnvironment
            )
            guard requiresCommit else { return }
            router.mutateRouteGraph { scope.commitRouteDeclarationInstallation() }
            if let parent = scope.parent {
                router.resumePendingRoute(for: scope.id, in: parent)
            }
        }
        let remove: (RouteScope) -> Void = { scope in
            router.mutateRouteGraph { scope.uninstallRouteDeclarations(sourceID: sourceID) }
        }

        attachment.update(target: routeScope, view: view, apply: apply, remove: remove)
    }

    private var accumulatedBranchRouteDeclarations: [RouteScopeDeclaration] {
        branchRouteDeclarations + declarations.filter { $0.branch != nil }
    }

    private var hostedDeclarations: [RouteScopeDeclaration] {
        declarations.map { declaration in
            guard declaration.branch == nil else {
                return declaration
            }

            return RouteScopeDeclaration(
                branch: nil,
                routes: declaration.routes.hosted(by: presentationHostID)
            )
        }
    }
}
