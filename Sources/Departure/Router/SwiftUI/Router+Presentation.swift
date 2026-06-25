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
        let routePath = routePath(containing: routeScope) ?? rootPath
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
        let routePath = routePath(containing: routeScope) ?? rootPath

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
        _ = elevatedContext(for: priority)?.path.scopes

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
        // context. The path owner maps to `nil`, i.e. before the elevated context begins.
        let hostIndex = routePath.scopes.firstIndex { $0 === host }
        guard
            shouldHostLocally(
                declaration,
                from: hostIndex,
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

        let hostIndex = path.scopes.firstIndex { $0 === host }
        let originalHostIndex = path.originalPathIndex(forPreservedPathIndex: hostIndex)

        for presentedScope in path.scopes {
            guard
                presentedScope.hostScope === host,
                let declaration = presentedScope.hostDeclaration,
                declaration.presentationKind == presentationKind,
                declaration.drivesPresentation,
                shouldHostLocally(
                    declaration,
                    from: originalHostIndex,
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

        let routePath = routePath(containing: presentation.scope) ?? rootPath

        guard let presentedPathIndex = routePath.scopes.firstIndex(where: { $0 === presentation.scope }) else {
            let targetPathIndex = routePath.index(of: routeScope)
            let removedScopes = routePath.scopesRemovedByKeepingThrough(targetPathIndex)
            let targetScope = routePath.scope(at: targetPathIndex)
            performPresentationDismissalUnwind(
                for: presentation.scope,
                in: targetScope,
                removing: removedScopes
            ) {
                keepPathThrough(targetPathIndex, in: routePath)
            }
            return
        }

        let targetPathIndex = presentedPathIndex == routePath.scopes.startIndex
            ? nil
            : routePath.scopes.index(before: presentedPathIndex)
        let removedScopes = routePath.scopesRemovedByKeepingThrough(targetPathIndex)
        let targetScope = routePath.scope(at: targetPathIndex)
        performPresentationDismissalUnwind(
            for: presentation.scope,
            in: targetScope,
            removing: removedScopes
        ) {
            keepPathThrough(targetPathIndex, in: routePath)
        }
    }

    func shouldHostLocally(
        _ declaration: AnyRouteDeclaration,
        from pathIndex: [RouteScope].Index?,
        in routePath: RoutePath
    ) -> Bool {
        guard declaration.priority != .normal else {
            return true
        }

        return elevatedContext(
            containingPath: routePath,
            pathIndex: pathIndex,
            minimumPriority: declaration.priority
        ) != nil
    }

    func shouldHostLocally(
        _ declaration: AnyRouteDeclaration,
        from pathIndex: [RouteScope].Index?,
        in routePath: RoutePath,
        snapshot: UnwindPresentationSnapshot
    ) -> Bool {
        guard declaration.priority != .normal else {
            return true
        }

        return snapshot.elevatedContext(
            containingPath: routePath,
            pathIndex: pathIndex,
            minimumPriority: declaration.priority
        ) != nil
    }

    func elevatedRoutePresentation(
        priority: RoutePriority,
        matching presentationKind: RoutePresentationKind
    ) -> RoutePresentation? {
        guard
            let context = elevatedContext(for: priority),
            let routeScope = context.elevatedRouteScope,
            let route = routeScope.route,
            let presentationScope = context.elevatedPresentationScope,
            let attachment = presentationScope.elevatedRouteAttachment(
                priority: priority,
                for: type(of: route),
                matching: presentationKind
            )
        else {
            return nil
        }

        return RoutePresentation(
            scope: routeScope,
            declaration: attachment.declaration,
            sourceEnvironment: attachment.routeScope.sourceEnvironment
        )
    }

    func dismissElevatedPresentation(
        priority: RoutePriority,
        matching presentationKind: RoutePresentationKind
    ) {
        guard let presentation = elevatedRoutePresentation(priority: priority, matching: presentationKind) else {
            return
        }

        guard let context = elevatedContext(for: priority) else {
            return
        }

        let targetPathIndex = context.elevatedBasePathIndex
        let removedScopes = context.path.scopesRemovedByKeepingThrough(targetPathIndex)
        let targetScope = context.path.scope(at: targetPathIndex)
        performPresentationDismissalUnwind(
            for: presentation.scope,
            in: targetScope,
            removing: removedScopes
        ) {
            keepPathThrough(targetPathIndex, in: context.path)
        }
    }

}

private extension RouteScope {
    func elevatedRouteAttachment(
        priority: RoutePriority,
        for routeType: any Route.Type,
        matching presentationKind: RoutePresentationKind
    ) -> (routeScope: RouteScope, declaration: AnyRouteDeclaration)? {
        let activeLocalScope = activeLocalScope

        if let declaration = activeLocalScope.routeAttachments.first(where: {
            $0.routeType == routeType
            && $0.presentationKind == presentationKind
            && $0.priority == priority
            && $0.drivesPresentation
        }) {
            return (activeLocalScope, declaration)
        }

        guard activeLocalScope !== self else {
            return nil
        }

        return routeAttachments.first(where: {
            $0.routeType == routeType
            && $0.presentationKind == presentationKind
            && $0.priority == priority
            && $0.drivesPresentation
        }).map { (self, $0) }
    }
}
