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

extension Router {
    func requestRoute(_ route: some Route) async {
        log.departureDebug(.routeRequested(route: route))

        let resolvedRoute: (any Route)?

        let resolutionResult: RouteResolution = await route.resolveRoute()
        switch resolutionResult {
        case .allow:
            resolvedRoute = route

        case .reroute(let newRoute):
            log.departureDebug(.routeRerouted(from: route, to: newRoute))
            resolvedRoute = newRoute

        case .drop:
            log.departureDebug(.routeDroppedResolution)
            resolvedRoute = nil
        }

        guard let resolvedRoute else { return }
        if let currentRoute = currentRouteScope.route, currentRoute._isEqual(to: resolvedRoute) {
            log.departureDebug(.routeNoOpEquivalent(route: resolvedRoute, currentRoute: currentRoute))
            return
        }

        let resolvedRouteType = type(of: resolvedRoute)
        guard let matchedDeclaration = routeForest.firstDeclaration(including: resolvedRouteType) else {
            log.departureDebug(.routeDroppedNoDeclaration(routeType: resolvedRouteType))
            return // Cannot find matching route, dropped.
        }

        log.departureDebug(.routeMatched(
            route: resolvedRoute,
            match: matchedDeclaration
        ))

        switch routeRequestDecision(for: matchedDeclaration) {
        case .drop:
            log.departureDebug(.routeBlockedByElevatedTree(route: resolvedRoute))
            return // Lower-priority route attached before an existing elevated tree is dropped.

        case .append:
            log.departureDebug(.routeAcceptedAppend(route: resolvedRoute))
            await appendRoute(resolvedRoute, after: matchedDeclaration)
            return

        case .replaceElevatedTree(let priority):
            if await unwindToExistingEquivalentRouteInPriorityTreeIfNeeded(resolvedRoute, priority: priority) {
                return
            }

            if await unwindToExistingEquivalentRouteIfNeeded(resolvedRoute, after: matchedDeclaration) {
                return
            }

            log.departureDebug(.routeAcceptedReplaceHighPriority(route: resolvedRoute))
            replaceElevatedTree(priority, with: resolvedRoute, after: matchedDeclaration)
            return
        }
    }
}

extension Router {
    enum RouteRequestDecision {
        case append
        case replaceElevatedTree(RoutePriority)
        case drop
    }

    struct DeclarationMatch {
        var path: RoutePath
        var position: RoutePath.Position
        var tree: RouteTree
        var declaringPath: RoutePath
        var declaringPosition: RoutePath.Position
        var branchID: AnyHashable?
        var declaration: AnyRouteDeclaration
    }

    func routeRequestDecision(for match: DeclarationMatch) -> RouteRequestDecision {
        if match.tree === routeForest.activeTree, match.tree.priority >= match.declaration.priority {
            return .append
        }

        guard match.declaration.priority != .normal else {
            return routeForest.activeTree.priority == .normal ? .append : .drop
        }

        if routeForest.activeTree.priority > match.declaration.priority {
            return .drop
        }

        return .replaceElevatedTree(match.declaration.priority)
    }

    /// The path owned by the branch nearest to the current position, or `nil` when the current
    /// position is not inside any branch. `.nearestBranch` unwinds clear this path back to its root.
    var nearestBranchPath: RoutePath? {
        var scope: RouteScope? = currentRouteScope
        while let current = scope {
            if current.branchID != nil {
                return current.path
            }

            scope = current.owningPath?.owner
        }

        return nil
    }

}

extension Router.DeclarationMatch {
    init(
        routePath: (path: RoutePath, position: RoutePath.Position),
        tree: RouteTree,
        declaringPath: RoutePath,
        declaringPosition: RoutePath.Position,
        attachment: RouteScope.RouteAttachmentMatch
    ) {
        self.init(
            path: routePath.path,
            position: routePath.position,
            tree: tree,
            declaringPath: declaringPath,
            declaringPosition: declaringPosition,
            branchID: attachment.branchID,
            declaration: attachment.declaration
        )
    }

    func updatingPresentationPath(
        _ routePath: (path: RoutePath, position: RoutePath.Position)
    ) -> Self {
        .init(
            path: routePath.path,
            position: routePath.position,
            tree: tree,
            declaringPath: declaringPath,
            declaringPosition: declaringPosition,
            branchID: branchID,
            declaration: declaration
        )
    }
}
