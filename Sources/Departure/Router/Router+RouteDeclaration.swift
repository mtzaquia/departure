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
        #if DEBUG
        guard DepartureLogTrace.id != nil else {
            await DepartureLogTrace.$id.withValue(DepartureLogTrace.nextID(prefix: "r")) {
                await requestRoute(route)
            }
            return
        }
        #endif

        log.departureDebug(.routeRequested(route: route))

        let resolvedRoute = await resolveRouteChain(startingWith: route)
        guard let resolvedRoute else { return }

        switch transitionPlan(for: resolvedRoute) {
        case .noOp(let currentRoute):
            log.departureDebug(.routeNoOpEquivalent(route: resolvedRoute, currentRoute: currentRoute))
            return

        case .dropNoDeclaration(let routeType):
            log.departureDebug(.routeDroppedNoDeclaration(routeType: routeType))
            return

        case .dropBlockedByElevatedPriority(let match):
            logMatchedRoute(resolvedRoute, to: match)
            log.departureDebug(.routeBlockedByElevatedPriority(route: resolvedRoute))
            return

        case .append(let match):
            logMatchedRoute(resolvedRoute, to: match)
            log.departureDebug(.routeAcceptedAppend(route: resolvedRoute))
            await appendRoute(resolvedRoute, after: match)
            return

        case .replaceElevatedTree(let priority, let match):
            logMatchedRoute(resolvedRoute, to: match)
            if await unwindToExistingEquivalentRouteInPriorityTreeIfNeeded(resolvedRoute, priority: priority) {
                return
            }

            if await unwindToExistingEquivalentRouteIfNeeded(resolvedRoute, after: match) {
                return
            }

            log.departureDebug(.routeAcceptedReplaceElevatedPriority(route: resolvedRoute))
            replaceElevatedTree(priority, with: resolvedRoute, after: match)
            return
        }
    }

    private func resolveRouteChain(startingWith route: any Route) async -> (any Route)? {
        var candidate = route

        while true {
            let resolution: RouteResolution = await candidate.resolveRoute()
            switch resolution {
            case .allow:
                return candidate

            case .reroute(let rerouted):
                log.departureDebug(.routeRerouted(from: candidate, to: rerouted))
                candidate = rerouted

            case .drop:
                log.departureDebug(.routeDroppedResolution)
                return nil
            }
        }
    }

    private func transitionPlan(for route: any Route) -> RouteTransitionPlan {
        if let currentRoute = currentRouteScope.route,
           currentRoute._isEqual(to: route) {
            return .noOp(currentRoute: currentRoute)
        }

        let routeType = type(of: route)
        guard let match = routeForest.firstDeclaration(including: routeType) else {
            return .dropNoDeclaration(routeType: routeType)
        }

        return switch priorityDecision(for: match) {
        case .drop:
            .dropBlockedByElevatedPriority(match: match)

        case .append:
            .append(match: match)

        case .replaceElevatedTree(let priority):
            .replaceElevatedTree(priority: priority, match: match)
        }
    }

    private func logMatchedRoute(_ route: any Route, to match: DeclarationMatch) {
        log.departureDebug(.routeMatched(route: route, match: match))
    }
}

extension Router {
    enum RouteTransitionPlan {
        case noOp(currentRoute: any Route)
        case dropNoDeclaration(routeType: any Route.Type)
        case dropBlockedByElevatedPriority(match: DeclarationMatch)
        case append(match: DeclarationMatch)
        case replaceElevatedTree(priority: RoutePriority, match: DeclarationMatch)
    }

    enum PriorityDecision {
        case append
        case replaceElevatedTree(RoutePriority)
        case drop
    }

    struct DeclarationMatch {
        struct Location {
            let path: RoutePath
            let position: RoutePath.Position

            var scope: RouteScope? {
                path.scope(at: position)
            }
        }

        let presentationLocation: Location
        let tree: RouteTree
        let declarationLocation: Location
        let branchID: AnyHashable?
        let declaration: AnyRouteDeclaration
    }

    func priorityDecision(for match: DeclarationMatch) -> PriorityDecision {
        if let pendingPriority = pendingElevatedPriority,
           match.declaration.priority < pendingPriority {
            return .drop
        }

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

    private var pendingElevatedPriority: RoutePriority? {
        pendingRoute?.append?.behavior.elevatedPriority
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
            presentationLocation: .init(path: routePath.path, position: routePath.position),
            tree: tree,
            declarationLocation: .init(path: declaringPath, position: declaringPosition),
            branchID: attachment.branchID,
            declaration: attachment.declaration
        )
    }

    func updatingPresentationPath(
        _ routePath: (path: RoutePath, position: RoutePath.Position)
    ) -> Self {
        .init(
            presentationLocation: .init(path: routePath.path, position: routePath.position),
            tree: tree,
            declarationLocation: declarationLocation,
            branchID: branchID,
            declaration: declaration
        )
    }
}
