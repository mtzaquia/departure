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
        if let currentRoute = currentRouteScope.route, currentRoute.isEqual(to: resolvedRoute) {
            log.departureDebug(.routeNoOpEquivalent(route: resolvedRoute, currentRoute: currentRoute))
            return
        }

        let resolvedRouteType = type(of: resolvedRoute)
        guard let matchedDeclaration = firstDeclaration(including: resolvedRouteType) else {
            log.departureDebug(.routeDroppedNoDeclaration(routeType: resolvedRouteType))
            return // Cannot find matching route, dropped.
        }

        log.departureDebug(.routeMatched(
            route: resolvedRoute,
            match: matchedDeclaration,
            highContextStart: highContext?.highStartIndex
        ))

        switch routeRequestDecision(for: matchedDeclaration) {
        case .drop:
            log.departureDebug(.routeBlockedByHighContext(route: resolvedRoute))
            return // Lower-priority route attached before an existing elevated context is dropped.

        case .append:
            log.departureDebug(.routeAcceptedAppend(route: resolvedRoute))
            await appendRoute(resolvedRoute, after: matchedDeclaration)
            return

        case .replaceElevatedContext(let priority):
            if await unwindToExistingEquivalentRouteIfNeeded(resolvedRoute, after: matchedDeclaration) {
                return
            }

            log.departureDebug(.routeAcceptedReplaceHighPriority(route: resolvedRoute))
            replaceElevatedContext(priority, with: resolvedRoute, after: matchedDeclaration)
            return
        }
    }
}

extension Router {
    enum RouteRequestDecision {
        case append
        case replaceElevatedContext(RoutePriority)
        case drop
    }

    struct DeclarationMatch {
        var path: RoutePath
        var pathIndex: [RouteScope].Index?
        var declaringPath: RoutePath
        var declaringPathIndex: [RouteScope].Index?
        var branchID: AnyHashable?
        var declaration: AnyRouteDeclaration
    }

    func routeRequestDecision(for match: DeclarationMatch) -> RouteRequestDecision {
        if let containingContext = elevatedContext(containing: match),
           containingContext.priority >= match.declaration.priority {
            return .append
        }

        guard match.declaration.priority != .normal else {
            return highestElevatedContext == nil ? .append : .drop
        }

        if let highestElevatedContext,
           highestElevatedContext.priority > match.declaration.priority {
            return .drop
        }

        return .replaceElevatedContext(match.declaration.priority)
    }

    func firstDeclaration(including routeType: any Route.Type) -> DeclarationMatch? {
        if let match = firstDeclaration(in: currentRoutePath, including: routeType) {
            return match
        }

        if currentRoutePath !== rootPath,
           let match = firstDeclaration(in: rootPath, including: routeType) {
            return match
        }

        if let match = root.firstBranchScopeRouteAttachment(
            for: routeType,
            in: root.activeBranch
        ) {
            let routePath = routePath(for: match, under: root, fallbackPath: rootPath, fallbackPathIndex: nil)
            return DeclarationMatch(
                routePath: routePath,
                declaringPath: rootPath,
                declaringPathIndex: nil,
                attachment: match
            )
        }

        if let match = root.firstRouteAttachment(for: routeType) {
            let routePath = routePath(for: match, under: root, fallbackPath: rootPath, fallbackPathIndex: nil)
            return DeclarationMatch(
                routePath: routePath,
                declaringPath: rootPath,
                declaringPathIndex: nil,
                attachment: match
            )
        }

        return nil
    }

    func firstDeclaration(in searchPath: RoutePath, including routeType: any Route.Type) -> DeclarationMatch? {
        for index in searchPath.scopes.indices.reversed() {
            if let match = searchPath.scopes[index].firstBranchScopeRouteAttachment(
                for: routeType,
                in: searchPath.scopes[index].activeBranch
            ) {
                let routePath = routePath(
                    for: match,
                    under: searchPath.scopes[index],
                    fallbackPath: searchPath,
                    fallbackPathIndex: index
                )
                return DeclarationMatch(
                    routePath: routePath,
                    declaringPath: searchPath,
                    declaringPathIndex: index,
                    attachment: match
                )
            }

            if let match = searchPath.scopes[index].firstRouteAttachment(for: routeType) {
                return DeclarationMatch(
                    routePath: (path: searchPath, pathIndex: index),
                    declaringPath: searchPath,
                    declaringPathIndex: index,
                    attachment: match
                )
            }
        }

        guard let owner = searchPath.owner, owner !== root else {
            return nil
        }

        if let match = owner.firstRouteAttachment(for: routeType) {
            return DeclarationMatch(
                routePath: (path: searchPath, pathIndex: nil),
                declaringPath: searchPath,
                declaringPathIndex: nil,
                attachment: match
            )
        }

        return nil
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

    func routePath(
        for match: RouteScope.RouteAttachmentMatch,
        under routeScope: RouteScope,
        fallbackPath: RoutePath,
        fallbackPathIndex: [RouteScope].Index?
    ) -> (path: RoutePath, pathIndex: [RouteScope].Index?) {
        guard let branchID = match.branchID else {
            return (path: fallbackPath, pathIndex: fallbackPathIndex)
        }

        return routePath(forBranch: branchID, under: routeScope, declaration: match.declaration)
    }

    func routePath(
        forBranch branchID: AnyHashable,
        under routeScope: RouteScope,
        declaration: AnyRouteDeclaration
    ) -> (path: RoutePath, pathIndex: [RouteScope].Index?) {
        guard let branchScope = routeScope.branchScopes[branchID] else {
            return (path: routePath(containing: routeScope) ?? rootPath, pathIndex: nil)
        }

        guard declaration.presentationKind != .push else {
            return (path: branchScope.path, pathIndex: nil)
        }

        return (
            path: branchScope.path,
            pathIndex: branchScope.path.scopes.indices.last
        )
    }
}

extension Router.DeclarationMatch {
    init(
        routePath: (path: RoutePath, pathIndex: [RouteScope].Index?),
        declaringPath: RoutePath,
        declaringPathIndex: [RouteScope].Index?,
        attachment: RouteScope.RouteAttachmentMatch
    ) {
        self.init(
            path: routePath.path,
            pathIndex: routePath.pathIndex,
            declaringPath: declaringPath,
            declaringPathIndex: declaringPathIndex,
            branchID: attachment.branchID,
            declaration: attachment.declaration
        )
    }

    func updatingPresentationPath(
        _ routePath: (path: RoutePath, pathIndex: [RouteScope].Index?)
    ) -> Self {
        .init(
            path: routePath.path,
            pathIndex: routePath.pathIndex,
            declaringPath: declaringPath,
            declaringPathIndex: declaringPathIndex,
            branchID: branchID,
            declaration: declaration
        )
    }
}
