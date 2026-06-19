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

        let resolvedRouteType = type(of: resolvedRoute)
        guard let matchedDeclaration = firstDeclaration(including: resolvedRouteType) else {
            log.departureDebug(.routeDroppedNoDeclaration(routeType: resolvedRouteType))
            return // Cannot find matching route, dropped.
        }

        let requestedPriority = matchedDeclaration.declaration.priority
        let hasHighPrioritySegment = highPrioritySegment != nil
        let declarationIsInHighPrioritySegment = matchedDeclaration.pathIndex.map { pathIndex in
            guard let highPrioritySegment else { return false }

            return matchedDeclaration.path === highPrioritySegment.path
            && pathIndex >= highPrioritySegment.startIndex
        } ?? false

        log.departureDebug(.routeMatched(
            route: resolvedRoute,
            match: matchedDeclaration,
            highPriorityStart: highPrioritySegment?.startIndex
        ))

        switch (requestedPriority, hasHighPrioritySegment, declarationIsInHighPrioritySegment) {
        case (.normal, true, false):
            log.departureDebug(.routeBlockedByHighPrioritySegment(route: resolvedRoute))
            return // Normal priority route attached before an existing high-priority segment is dropped.

        case (.normal, _, _), (.high, _, true):
            log.departureDebug(.routeAcceptedAppend(route: resolvedRoute))
            await appendRoute(resolvedRoute, after: matchedDeclaration)
            return

        case (.high, _, false):
            log.departureDebug(.routeAcceptedReplaceHighPriority(route: resolvedRoute))
            replaceHighPrioritySegment(with: resolvedRoute, after: matchedDeclaration)
            return
        }
    }
}

extension Router {
    struct DeclarationMatch {
        var path: RoutePath
        var pathIndex: [RouteScope].Index?
        var declaringPath: RoutePath
        var declaringPathIndex: [RouteScope].Index?
        var branchID: AnyHashable
        var declaration: AnyRouteDeclaration
    }

    func firstDeclaration(including routeType: any Route.Type) -> DeclarationMatch? {
        if let match = firstDeclaration(in: currentRoutePath, including: routeType) {
            return match
        }

        if currentRoutePath !== rootPath,
           let match = firstDeclaration(in: rootPath, including: routeType) {
            return match
        }

        if let match = root.firstMountedBranchRouteAttachment(
            for: routeType,
            in: root.activeBranch
        ) {
            let branchPath = routePath(forBranch: match.branchID, under: root, declaration: match.declaration)
            return DeclarationMatch(
                path: branchPath.path,
                pathIndex: branchPath.pathIndex,
                declaringPath: rootPath,
                declaringPathIndex: nil,
                branchID: match.branchID,
                declaration: match.declaration
            )
        }

        if let match = root.firstRouteAttachment(for: routeType) {
            guard match.declaration.drivesPresentation == false else {
                return DeclarationMatch(
                    path: rootPath,
                    pathIndex: nil,
                    declaringPath: rootPath,
                    declaringPathIndex: nil,
                    branchID: match.branchID,
                    declaration: match.declaration
                )
            }

            let branchPath = routePath(forBranch: match.branchID, under: root, declaration: match.declaration)
            return DeclarationMatch(
                path: branchPath.path,
                pathIndex: branchPath.pathIndex,
                declaringPath: rootPath,
                declaringPathIndex: nil,
                branchID: match.branchID,
                declaration: match.declaration
            )
        }

        return nil
    }

    func firstDeclaration(in searchPath: RoutePath, including routeType: any Route.Type) -> DeclarationMatch? {
        for index in searchPath.scopes.indices.reversed() {
            if let match = searchPath.scopes[index].firstMountedBranchRouteAttachment(
                for: routeType,
                in: searchPath.scopes[index].activeBranch
            ) {
                let branchPath = routePath(
                    forBranch: match.branchID,
                    under: searchPath.scopes[index],
                    declaration: match.declaration
                )
                return DeclarationMatch(
                    path: branchPath.path,
                    pathIndex: branchPath.pathIndex,
                    declaringPath: searchPath,
                    declaringPathIndex: index,
                    branchID: match.branchID,
                    declaration: match.declaration
                )
            }

            if let match = searchPath.scopes[index].firstRouteAttachment(for: routeType) {
                return DeclarationMatch(
                    path: searchPath,
                    pathIndex: index,
                    declaringPath: searchPath,
                    declaringPathIndex: index,
                    branchID: match.branchID,
                    declaration: match.declaration
                )
            }
        }

        guard let owner = searchPath.owner, owner !== root else {
            return nil
        }

        if let match = owner.firstRouteAttachment(for: routeType) {
            return DeclarationMatch(
                path: searchPath,
                pathIndex: nil,
                declaringPath: searchPath,
                declaringPathIndex: nil,
                branchID: match.branchID,
                declaration: match.declaration
            )
        }

        return nil
    }

    var currentRoutePath: RoutePath {
        if let highPrioritySegment {
            return highPrioritySegment.path
        }

        if let activeTopLevelPath = rootPath.last?.activeLocalScope.owningPath {
            return activeTopLevelPath
        }

        if let activeRootPath = root.activeLocalScope.owningPath {
            return activeRootPath
        }

        return rootPath
    }

    /// The path owned by the branch nearest to the current position, or `nil` when the current
    /// position is not inside any branch. `.nearestBranch` unwinds clear this path back to its root.
    var nearestBranchPath: RoutePath? {
        var scope: RouteScope? = currentRouteScope
        while let current = scope {
            if current.mountedBranchID != nil {
                return current.path
            }

            scope = current.owningPath?.owner
        }

        return nil
    }

    func routePath(
        forBranch branchID: AnyHashable,
        under routeScope: RouteScope,
        declaration: AnyRouteDeclaration
    ) -> (path: RoutePath, pathIndex: [RouteScope].Index?) {
        guard let branchScope = routeScope.mountedBranchScopes[branchID] else {
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
