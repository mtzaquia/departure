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

    func highPriorityRoutePresentationBinding(
        matching presentationKind: RoutePresentationKind
    ) -> Binding<RoutePresentation?> {
        Binding(
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
    func routePresentation(
        from routeScope: RouteScope,
        matching presentationKind: RoutePresentationKind
    ) -> RoutePresentation? {
        if let presentation = routePresentation(
            from: routeScope,
            matching: presentationKind,
            in: path,
            highPrioritySegmentStartIndex: highPrioritySegmentStartIndex
        ) {
            return presentation
        }

        guard
            routeScope !== root,
            let unwindPresentationSnapshot
        else {
            return nil
        }

        return routePresentation(
            from: routeScope,
            matching: presentationKind,
            in: unwindPresentationSnapshot.preservedPath,
            highPrioritySegmentStartIndex: unwindPresentationSnapshot.highPrioritySegmentStartIndex
        )
    }

    func routePresentation(
        from routeScope: RouteScope,
        matching presentationKind: RoutePresentationKind,
        in path: [RouteScope],
        highPrioritySegmentStartIndex: [RouteScope].Index?
    ) -> RoutePresentation? {
        guard contains(routeScope, in: path) else {
            return nil
        }

        guard routeScope.canDrivePresentation else {
            return nil
        }

        let routeScopePathIndex = pathIndex(of: routeScope, in: path)

        guard
            let presentedScope = scope(after: routeScopePathIndex, in: path),
            let route = presentedScope.route,
            let declaration = routeScope.routeAttachments.first(where: { declaration in
                declaration.routeType == type(of: route)
                && declaration.presentationKind == presentationKind
                && declaration.drivesPresentation
            }),
            shouldHostLocally(
                declaration,
                from: routeScopePathIndex,
                highPrioritySegmentStartIndex: highPrioritySegmentStartIndex
            )
        else {
            return nil
        }

        return RoutePresentation(
            scope: presentedScope,
            declaration: declaration
        )
    }

    func dismissPresentation(
        from routeScope: RouteScope,
        matching presentationKind: RoutePresentationKind
    ) {
        guard routePresentation(from: routeScope, matching: presentationKind) != nil else {
            return
        }

        keepPathThrough(pathIndex(of: routeScope))
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
            let segmentStartIndex = highPrioritySegmentStartIndex,
            path.indices.contains(segmentStartIndex),
            let route = path[segmentStartIndex].route,
            let declaringScope = scope(at: declaringPathIndexForHighPrioritySegment()),
            let declaration = declaringScope.highPriorityRouteAttachments.first(where: { declaration in
                declaration.routeType == type(of: route)
                && declaration.presentationKind == presentationKind
                && declaration.priority == .high
                && declaration.drivesPresentation
            })
        else {
            return nil
        }

        return RoutePresentation(
            scope: path[segmentStartIndex],
            declaration: declaration
        )
    }

    func dismissHighPriorityPresentation(
        matching presentationKind: RoutePresentationKind
    ) {
        guard highPriorityRoutePresentation(matching: presentationKind) != nil else {
            return
        }

        keepPathThrough(declaringPathIndexForHighPrioritySegment())
    }

    func declaringPathIndexForHighPrioritySegment() -> [RouteScope].Index? {
        guard
            let segmentStartIndex = highPrioritySegmentStartIndex,
            segmentStartIndex > path.startIndex
        else {
            return nil
        }

        return path.index(before: segmentStartIndex)
    }

    func scope(
        after pathIndex: [RouteScope].Index?,
        in path: [RouteScope]
    ) -> RouteScope? {
        let nextIndex: [RouteScope].Index

        if let pathIndex {
            nextIndex = path.index(after: pathIndex)
        } else {
            nextIndex = path.startIndex
        }

        guard path.indices.contains(nextIndex) else {
            return nil
        }

        return path[nextIndex]
    }

}

private extension RouteScope {
    var highPriorityRouteAttachments: [AnyRouteDeclaration] {
        let activeLocalScope = activeLocalScope

        guard activeLocalScope !== self else {
            return routeAttachments
        }

        return activeLocalScope.routeAttachments + routeAttachments
    }
}
