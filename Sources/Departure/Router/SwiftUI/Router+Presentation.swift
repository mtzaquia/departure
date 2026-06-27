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

extension Router {
    func routePresentationBinding(
        from routeScope: RouteScope?,
        matching presentationKind: RoutePresentationKind
    ) -> Binding<RoutePresentation?> {
        let routeScope = routeScope ?? root
        let routePath = routeForest.routePath(containing: routeScope) ?? normalTree.rootPath
        _ = routePath.scopes
        if routeScope !== root {
            _ = routeScope.path.scopes
        }

        return Binding(
            get: {
                self.routePresentation(
                    from: routeScope,
                    matching: presentationKind
                )
            },
            set: { presentation in
                guard presentation == nil else {
                    return
                }

                self.dismissPresentation(
                    from: routeScope,
                    matching: presentationKind
                )
            }
        )
    }

    func routePresentation(
        from routeScope: RouteScope,
        matching presentationKind: RoutePresentationKind
    ) -> RoutePresentation? {
        let routePath = routeForest.routePath(containing: routeScope) ?? normalTree.rootPath

        // Live read: return the host's structural slot directly.
        if let presentation = hostedPresentation(
            by: routeScope,
            matching: presentationKind,
            in: routePath
        ) {
            return presentation
        }

        guard presentationKind != .push else {
            return nil
        }

        guard
            routeScope !== root,
            let unwindPresentationSnapshot
        else {
            return nil
        }

        // Snapshot read: the preserved scopes have already left the live path (and released their
        // slots), so scan the snapshot by recorded host instead.
        return hostedPresentation(
            by: routeScope,
            matching: presentationKind,
            inPreservedPaths: unwindPresentationSnapshot.preservedPaths,
            snapshot: unwindPresentationSnapshot
        )
    }

    func highPriorityRoutePresentationBinding(
        matching presentationKind: RoutePresentationKind
    ) -> Binding<RoutePresentation?> {
        elevatedRoutePresentationBinding(priority: .high, matching: presentationKind)
    }

    func elevatedRoutePresentationBinding(
        priority: RoutePriority,
        matching presentationKind: RoutePresentationKind
    ) -> Binding<RoutePresentation?> {
        _ = routeForest.tree(for: priority)?.rootPath.scopes

        return Binding(
            get: {
                self.elevatedRoutePresentation(
                    priority: priority,
                    matching: presentationKind
                )
            },
            set: { presentation in
                guard presentation == nil else {
                    return
                }

                self.dismissElevatedPresentation(
                    priority: priority,
                    matching: presentationKind
                )
            }
        )
    }
}

private extension Router {
    func hostedPresentation(
        by host: RouteScope,
        matching presentationKind: RoutePresentationKind,
        in routePath: RoutePath
    ) -> RoutePresentation? {
        guard host.canDrivePresentation(matching: presentationKind) else {
            return nil
        }

        let candidate = presentationKind == .push ? host.pushChild : host.modalChild
        guard
            let presentedScope = candidate,
            let declaration = presentedScope.hostDeclaration,
            declaration.presentationKind == presentationKind,
            declaration.drivesPresentation
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
        inPreservedPaths paths: [UnwindPresentationSnapshot.PreservedRoutePath],
        snapshot: UnwindPresentationSnapshot
    ) -> RoutePresentation? {
        for path in paths {
            if let presentation = hostedPresentation(
                by: host,
                matching: presentationKind,
                inPreservedPath: path,
                snapshot: snapshot
            ) {
                return presentation
            }
        }

        return nil
    }

    func hostedPresentation(
        by host: RouteScope,
        matching presentationKind: RoutePresentationKind,
        inPreservedPath path: UnwindPresentationSnapshot.PreservedRoutePath,
        snapshot: UnwindPresentationSnapshot
    ) -> RoutePresentation? {
        guard host.canDrivePresentation(matching: presentationKind) else {
            return nil
        }

        let hostPosition = RoutePath.Position.scope(host)

        for presentedScope in path.scopes {
            guard
                presentedScope.hostScope === host,
                let declaration = presentedScope.hostDeclaration,
                declaration.presentationKind == presentationKind,
                declaration.drivesPresentation,
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
        matching presentationKind: RoutePresentationKind
    ) {
        guard let presentation = routePresentation(from: routeScope, matching: presentationKind) else {
            return
        }

        let routePath = routeForest.routePath(containing: presentation.scope) ?? normalTree.rootPath

        guard let targetPosition = routePath.positionBefore(presentation.scope) else {
            let fallbackPosition = routePath.position(of: routeScope) ?? .owner
            let removedScopes = routePath.scopesRemovedAfter(fallbackPosition)
            let targetScope = routePath.scope(at: fallbackPosition)
            performPresentationDismissalUnwind(
                for: presentation.scope,
                in: targetScope,
                removing: removedScopes
            ) {
                keepPathThrough(fallbackPosition, in: routePath)
            }
            return
        }

        let removedScopes = routePath.scopesRemovedAfter(targetPosition)
        let targetScope = routePath.scope(at: targetPosition)
        performPresentationDismissalUnwind(
            for: presentation.scope,
            in: targetScope,
            removing: removedScopes
        ) {
            keepPathThrough(targetPosition, in: routePath)
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
            let anchor = tree.anchor,
            anchor.declaration.presentationKind == presentationKind,
            anchor.declaration.drivesPresentation
        else {
            return nil
        }

        return RoutePresentation(
            scope: routeScope,
            declaration: anchor.declaration,
            sourceEnvironment: anchor.routeScope?.sourceEnvironment ?? EnvironmentValues()
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

        let removedScopes = tree.rootPath.scopesRemovedAfter(.owner)
        let targetScope = tree.anchor?.routeScope
        performPresentationDismissalUnwind(
            for: presentation.scope,
            in: targetScope,
            removing: removedScopes
        ) {
            keepPathThrough(.owner, in: tree.rootPath)
            mutateRouteGraph {
                routeForest.setElevatedTree(nil, for: priority)
            }
        }
    }

}
