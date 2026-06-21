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
        let highPrioritySegmentStartIndex = highPrioritySegment.flatMap {
            $0.path === routePath ? $0.startIndex : nil
        }

        // Live read: return the host's structural slot directly.
        if let presentation = hostedPresentation(
            by: routeScope,
            matching: presentationKind,
            highPrioritySegmentStartIndex: highPrioritySegmentStartIndex
        ) {
            return presentation
        }

        guard
            routeScope !== root,
            let unwindPresentationSnapshot,
            routeScope !== unwindPresentationSnapshot.routePath.owner
        else {
            return nil
        }

        // Snapshot read: the preserved scopes have already left the live path (and released their
        // slots), so scan the snapshot by recorded host instead.
        return hostedPresentation(
            by: routeScope,
            matching: presentationKind,
            inPreservedPath: unwindPresentationSnapshot.preservedPath,
            highPrioritySegmentStartIndex: unwindPresentationSnapshot.highPrioritySegment?.startIndex
        )
    }

    func highPriorityRoutePresentationBinding(
        matching presentationKind: RoutePresentationKind
    ) -> Binding<RoutePresentation?> {
        _ = highPrioritySegment?.path.scopes

        return Binding(
            get: {
                self.highPriorityRoutePresentation(
                    matching: presentationKind
                )
            },
            set: { presentation in
                guard presentation == nil else {
                    return
                }

                self.dismissHighPriorityPresentation(
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
        highPrioritySegmentStartIndex: [RouteScope].Index?
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

        // The high-priority gate keys off the *host's* position relative to the segment (the path
        // owner maps to `nil`, i.e. before the segment).
        let hostIndex = (routePath(containing: host) ?? rootPath).scopes.firstIndex { $0 === host }
        guard
            shouldHostLocally(
                declaration,
                from: hostIndex,
                highPrioritySegmentStartIndex: highPrioritySegmentStartIndex
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
        inPreservedPath path: [RouteScope],
        highPrioritySegmentStartIndex: [RouteScope].Index?
    ) -> RoutePresentation? {
        guard host.canDrivePresentation(matching: presentationKind) else {
            return nil
        }

        let hostIndex = path.firstIndex { $0 === host }

        for presentedScope in path {
            guard
                presentedScope.hostScope === host,
                let declaration = presentedScope.hostDeclaration,
                declaration.presentationKind == presentationKind,
                declaration.drivesPresentation,
                shouldHostLocally(
                    declaration,
                    from: hostIndex,
                    highPrioritySegmentStartIndex: highPrioritySegmentStartIndex
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
            keepPathThrough(targetPathIndex, in: routePath)
            scheduleUnwindHandlersAfterDismissalCompletes(
                for: presentation.scope.route,
                in: targetScope,
                removing: removedScopes
            )
            return
        }

        let targetPathIndex = presentedPathIndex == routePath.scopes.startIndex
            ? nil
            : routePath.scopes.index(before: presentedPathIndex)
        let removedScopes = routePath.scopesRemovedByKeepingThrough(targetPathIndex)
        let targetScope = routePath.scope(at: targetPathIndex)
        keepPathThrough(targetPathIndex, in: routePath)
        scheduleUnwindHandlersAfterDismissalCompletes(
            for: presentation.scope.route,
            in: targetScope,
            removing: removedScopes
        )
    }

    func shouldHostLocally(
        _ declaration: AnyRouteDeclaration,
        from pathIndex: [RouteScope].Index?,
        highPrioritySegmentStartIndex: [RouteScope].Index?
    ) -> Bool {
        guard declaration.priority == .high else {
            return true
        }

        guard
            let pathIndex,
            let highPrioritySegmentStartIndex
        else {
            return false
        }

        return pathIndex >= highPrioritySegmentStartIndex
    }

    func highPriorityRoutePresentation(
        matching presentationKind: RoutePresentationKind
    ) -> RoutePresentation? {
        guard
            let highPrioritySegment,
            highPrioritySegment.path.scopes.indices.contains(highPrioritySegment.startIndex),
            let route = highPrioritySegment.path.scopes[highPrioritySegment.startIndex].route,
            let declaringScope = highPrioritySegment.path.scope(at: declaringPathIndexForHighPrioritySegment()),
            let attachment = declaringScope.highPriorityRouteAttachment(
                for: type(of: route),
                matching: presentationKind
            )
        else {
            return nil
        }

        return RoutePresentation(
            scope: highPrioritySegment.path.scopes[highPrioritySegment.startIndex],
            declaration: attachment.declaration,
            sourceEnvironment: attachment.routeScope.sourceEnvironment
        )
    }

    func dismissHighPriorityPresentation(
        matching presentationKind: RoutePresentationKind
    ) {
        guard let presentation = highPriorityRoutePresentation(matching: presentationKind) else {
            return
        }

        guard let highPrioritySegment else {
            return
        }

        let targetPathIndex = declaringPathIndexForHighPrioritySegment()
        let removedScopes = highPrioritySegment.path.scopesRemovedByKeepingThrough(targetPathIndex)
        let targetScope = highPrioritySegment.path.scope(at: targetPathIndex)
        keepPathThrough(targetPathIndex, in: highPrioritySegment.path)
        scheduleUnwindHandlersAfterDismissalCompletes(
            for: presentation.scope.route,
            in: targetScope,
            removing: removedScopes
        )
    }

    func declaringPathIndexForHighPrioritySegment() -> [RouteScope].Index? {
        guard
            let highPrioritySegment,
            highPrioritySegment.startIndex > highPrioritySegment.path.scopes.startIndex
        else {
            return nil
        }

        return highPrioritySegment.path.scopes.index(before: highPrioritySegment.startIndex)
    }

}

private extension RouteScope {
    func highPriorityRouteAttachment(
        for routeType: any Route.Type,
        matching presentationKind: RoutePresentationKind
    ) -> (routeScope: RouteScope, declaration: AnyRouteDeclaration)? {
        let activeLocalScope = activeLocalScope

        if let declaration = activeLocalScope.routeAttachments.first(where: {
            $0.routeType == routeType
            && $0.presentationKind == presentationKind
            && $0.priority == .high
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
            && $0.priority == .high
            && $0.drivesPresentation
        }).map { (self, $0) }
    }
}
