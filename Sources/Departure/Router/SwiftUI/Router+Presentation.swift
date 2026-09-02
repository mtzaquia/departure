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

struct RoutePresentation: Identifiable, Hashable {
    let scope: RouteScope
    let declaration: AnyRouteDeclaration
    let sourceEnvironment: EnvironmentValues

    init(
        scope: RouteScope,
        declaration: AnyRouteDeclaration,
        sourceEnvironment: EnvironmentValues = EnvironmentValues()
    ) {
        self.scope = scope
        self.declaration = declaration
        self.sourceEnvironment = sourceEnvironment
    }

    var id: AnyHashable {
        ObjectIdentifier(scope)
    }

    var providesNavigation: Bool {
        declaration.providesNavigation
    }

    static func == (lhs: RoutePresentation, rhs: RoutePresentation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct ResolvedRoutePresentation {
    let presentation: RoutePresentation
    let routePath: RoutePath
    let isLive: Bool
}

extension Router {
    private subscript(presentation projection: RoutePresentationProjection) -> RoutePresentation? {
        get {
            routePresentation(
                from: projection.routeScope ?? root,
                matching: projection.presentationKind,
                hostedBy: projection.presentationHostID
            )
        }
        set {
            guard newValue == nil else {
                return
            }

            dismissPresentation(
                from: projection.routeScope ?? root,
                matching: projection.presentationKind,
                hostedBy: projection.presentationHostID
            )
        }
    }

    private subscript(elevatedPresentation projection: ElevatedRoutePresentationProjection) -> RoutePresentation? {
        get {
            elevatedRoutePresentation(
                priority: projection.priority,
                matching: projection.presentationKind
            )
        }
        set {
            guard newValue == nil else {
                return
            }

            dismissElevatedPresentation(
                priority: projection.priority,
                matching: projection.presentationKind
            )
        }
    }

    func pushPresentationDismissalDisablesAnimations(
        from routeScope: RouteScope?,
        hostedBy presentationHostID: RoutePresentationHostID? = nil
    ) -> Bool {
        let routeScope = routeScope ?? root
        guard let unwindPresentationSnapshot else {
            return false
        }

        return unwindPresentationSnapshot.preservedPaths.contains { path in
            path.scopes.contains { presentedScope in
                guard
                    unwindPresentationSnapshot.unanimatedPushPresentationScopeIDs
                        .contains(ObjectIdentifier(presentedScope)),
                    presentedScope.attachedPresentationDeclaration(
                        presentedBy: routeScope,
                        matching: .push,
                        hostedBy: presentationHostID
                    ) != nil
                else {
                    return false
                }

                return true
            }
        }
    }

    func routePresentationBinding(
        from routeScope: RouteScope?,
        matching presentationKind: RoutePresentationKind,
        hostedBy presentationHostID: RoutePresentationHostID? = nil
    ) -> Binding<RoutePresentation?> {
        let routeScope = routeScope ?? root
        if let routePath = routeForest.routePath(containing: routeScope) {
            _ = routePath.scopes
        }
        if routeScope !== root {
            _ = routeScope.path.scopes
        }

        @Bindable var router = self
        return $router[presentation: RoutePresentationProjection(
            routeScope: routeScope,
            presentationKind: presentationKind,
            presentationHostID: presentationHostID
        )]
    }

    func routePresentation(
        from routeScope: RouteScope,
        matching presentationKind: RoutePresentationKind,
        hostedBy presentationHostID: RoutePresentationHostID? = nil
    ) -> RoutePresentation? {
        resolvedRoutePresentation(
            from: routeScope,
            matching: presentationKind,
            hostedBy: presentationHostID
        )?.presentation
    }

    private func resolvedRoutePresentation(
        from routeScope: RouteScope,
        matching presentationKind: RoutePresentationKind,
        hostedBy presentationHostID: RoutePresentationHostID?
    ) -> ResolvedRoutePresentation? {
        let routePath = routeForest.routePath(containing: routeScope)

        // Live read: return the host's structural slot directly.
        if let routePath,
           let presentation = hostedPresentation(
            by: routeScope,
            matching: presentationKind,
            hostedBy: presentationHostID,
            in: routePath
        ) {
            return ResolvedRoutePresentation(
                presentation: presentation,
                routePath: routePath,
                isLive: true
            )
        }

        guard
            routeScope !== root,
            let unwindPresentationSnapshot,
            unwindPresentationSnapshot.departingPresentationHostScopeIDs
                .contains(ObjectIdentifier(routeScope))
        else {
            return nil
        }

        switch presentationKind {
        case .push:
            guard unwindPresentationSnapshot.preservesPushPresentationBindings else {
                return nil
            }

        case .sheet, .cover:
            guard unwindPresentationSnapshot.preservesModalPresentationBindings else {
                return nil
            }
        }

        // Snapshot read: the preserved scopes have already left the live path (and released their
        // slots), so scan the snapshot by recorded host instead.
        return hostedPresentation(
            by: routeScope,
            matching: presentationKind,
            hostedBy: presentationHostID,
            inPreservedPaths: unwindPresentationSnapshot.preservedPaths,
            snapshot: unwindPresentationSnapshot
        )
    }

    func elevatedRoutePresentationBinding(
        priority: RoutePriority,
        matching presentationKind: RoutePresentationKind
    ) -> Binding<RoutePresentation?> {
        _ = routeForest.tree(for: priority)?.rootPath.scopes

        @Bindable var router = self
        return $router[elevatedPresentation: ElevatedRoutePresentationProjection(
            priority: priority,
            presentationKind: presentationKind
        )]
    }
}

private struct RoutePresentationProjection: Hashable {
    let routeScope: RouteScope?
    let presentationKind: RoutePresentationKind
    let presentationHostID: RoutePresentationHostID?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.routeScope === rhs.routeScope
            && lhs.presentationKind == rhs.presentationKind
            && lhs.presentationHostID == rhs.presentationHostID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(routeScope.map(ObjectIdentifier.init))
        hasher.combine(presentationKind)
        hasher.combine(presentationHostID)
    }
}

private struct ElevatedRoutePresentationProjection: Hashable {
    let priority: RoutePriority
    let presentationKind: RoutePresentationKind
}

private extension Router {
    func hostedPresentation(
        by host: RouteScope,
        matching presentationKind: RoutePresentationKind,
        hostedBy presentationHostID: RoutePresentationHostID?,
        in routePath: RoutePath
    ) -> RoutePresentation? {
        guard host.canDrivePresentation(matching: presentationKind) else {
            return nil
        }

        guard
            let presentedScope = routePath.scopes.first(where: {
                $0.attachedPresentationDeclaration(
                    presentedBy: host,
                    matching: presentationKind,
                    hostedBy: presentationHostID
                ) != nil
            }),
            let declaration = presentedScope.attachedPresentationDeclaration(
                presentedBy: host,
                matching: presentationKind,
                hostedBy: presentationHostID
            )
        else {
            return nil
        }

        // The elevated-priority gate keys off the host's position relative to an equal-or-higher
        // tree. The path owner is before the elevated tree begins.
        let hostPosition = routePath.position(of: host) ?? .owner
        guard
            shouldHostLocally(
                declaration,
                from: hostPosition,
                in: routePath
            )
        else {
            return nil
        }

        return RoutePresentation(
            scope: presentedScope,
            declaration: declaration,
            sourceEnvironment: host.sourceEnvironment
        )
    }

    func hostedPresentation(
        by host: RouteScope,
        matching presentationKind: RoutePresentationKind,
        hostedBy presentationHostID: RoutePresentationHostID?,
        inPreservedPaths paths: [RouteForest.PreservedRoutePath],
        snapshot: UnwindPresentationSnapshot
    ) -> ResolvedRoutePresentation? {
        for path in paths {
            if let presentation = hostedPresentation(
                by: host,
                matching: presentationKind,
                hostedBy: presentationHostID,
                inPreservedPath: path,
                snapshot: snapshot
            ) {
                return ResolvedRoutePresentation(
                    presentation: presentation,
                    routePath: path.routePath,
                    isLive: false
                )
            }
        }

        return nil
    }

    func hostedPresentation(
        by host: RouteScope,
        matching presentationKind: RoutePresentationKind,
        hostedBy presentationHostID: RoutePresentationHostID?,
        inPreservedPath path: RouteForest.PreservedRoutePath,
        snapshot: UnwindPresentationSnapshot
    ) -> RoutePresentation? {
        guard host.canDrivePresentation(matching: presentationKind) else {
            return nil
        }

        let hostPosition = RoutePath.Position.scope(host)

        for presentedScope in path.scopes {
            guard
                let declaration = presentedScope.attachedPresentationDeclaration(
                    presentedBy: host,
                    matching: presentationKind,
                    hostedBy: presentationHostID
                ),
                shouldHostLocally(
                    declaration,
                    from: hostPosition,
                    in: path.routePath,
                    snapshot: snapshot
                )
            else {
                continue
            }

            return RoutePresentation(
                scope: presentedScope,
                declaration: declaration,
                sourceEnvironment: host.sourceEnvironment
            )
        }

        return nil
    }

    func dismissPresentation(
        from routeScope: RouteScope,
        matching presentationKind: RoutePresentationKind,
        hostedBy presentationHostID: RoutePresentationHostID?
    ) {
        guard let resolution = resolvedRoutePresentation(
            from: routeScope,
            matching: presentationKind,
            hostedBy: presentationHostID
        ), resolution.isLive else {
            return
        }
        let presentation = resolution.presentation

        if ios17NavigationStackPushWorkaround?.interceptDismissal(
            of: presentation,
            matching: presentationKind,
            in: self
        ) == true {
            return
        }

        let routePath = resolution.routePath
        guard let targetPosition = routePath.positionBefore(presentation.scope) else {
            return
        }

        let unwindPlan = routeForest.unwindPlan(for: .scoped(
            routePath: routePath,
            after: targetPosition
        ))
        let removedScopes = unwindPlan.removedScopes
        let targetScope = routePath.scope(at: targetPosition)
        performPresentationDismissalUnwind(
            for: presentation.scope,
            in: targetScope,
            removing: removedScopes
        ) {
            applyUnwindPlan(unwindPlan)
        }
    }

    func shouldHostLocally(
        _ declaration: AnyRouteDeclaration,
        from position: RoutePath.Position,
        in routePath: RoutePath
    ) -> Bool {
        guard declaration.priority != .normal else {
            return true
        }

        return routeForest.elevatedTree(
            containingPath: routePath,
            position: position,
            minimumPriority: declaration.priority
        ) != nil
    }

    func shouldHostLocally(
        _ declaration: AnyRouteDeclaration,
        from position: RoutePath.Position,
        in routePath: RoutePath,
        snapshot: UnwindPresentationSnapshot
    ) -> Bool {
        guard declaration.priority != .normal else {
            return true
        }

        return snapshot.routeForest.elevatedTree(
            containingPath: routePath,
            position: position,
            minimumPriority: declaration.priority
        ) != nil
    }

    func elevatedRoutePresentation(
        priority: RoutePriority,
        matching presentationKind: RoutePresentationKind
    ) -> RoutePresentation? {
        guard
            let tree = routeForest.tree(for: priority),
            let routeScope = tree.elevatedRouteScope,
            let origin = tree.elevatedOrigin,
            origin.declaration.presentationKind == presentationKind,
            origin.declaration.drivesPresentation
        else {
            return nil
        }

        return RoutePresentation(
            scope: routeScope,
            declaration: origin.declaration,
            sourceEnvironment: origin.sourceEnvironment.values
        )
    }

    func dismissElevatedPresentation(
        priority: RoutePriority,
        matching presentationKind: RoutePresentationKind
    ) {
        guard let presentation = elevatedRoutePresentation(priority: priority, matching: presentationKind) else {
            return
        }

        guard let tree = routeForest.tree(for: priority) else {
            return
        }

        let unwindPlan = routeForest.unwindPlan(for: .tree(tree))
        let removedScopes = unwindPlan.removedScopes
        let targetScope = tree.elevatedOrigin?.scope
        performPresentationDismissalUnwind(
            for: presentation.scope,
            in: targetScope,
            removing: removedScopes
        ) {
            applyUnwindPlan(unwindPlan)
        }
    }
}
