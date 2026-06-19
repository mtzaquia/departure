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

extension Router {
    @discardableResult
    func unwindAndWait(to target: UnwindTarget?) async -> Bool {
        log.departureDebug(.unwindRequested(target: target))

        // The target only differs by which path it clears; resolution is the same. `.root` unwinds
        // the entire app via the root path, regardless of the originating branch or depth.
        // `.nearestBranch` resolves against the enclosing branch path (no-op when there isn't one).
        // Everything else resolves against the current path.
        let routePath: RoutePath
        switch target {
        case .root:
            routePath = rootPath

        case .nearestBranch:
            guard let branchPath = nearestBranchPath else {
                // Not inside a branch — there is nothing nearer to unwind to.
                log.departureDebug(.unwindSkippedNotInsideBranch)
                return true
            }
            routePath = branchPath

        case nil, .id:
            routePath = currentRoutePath
        }

        switch routePath.unwindResolution(to: target) {
        case .noRouteToUnwind:
            log.departureDebug(.unwindSkippedNoRoute)
            return true

        case .targetNotFound:
            guard let ancestorResolution = ancestorUnwindResolution(from: routePath, to: target) else {
                log.departureDebug(.unwindDroppedTargetNotFound(target: target))
                return false
            }

            let removedScopes = routePath.scopesRemovedByKeepingThrough(nil)
            + ancestorResolution.path.scopesRemovedByKeepingThrough(ancestorResolution.pathIndex)
            log.departureDebug(.unwindAcceptedAncestorTarget(
                keepThrough: ancestorResolution.pathIndex,
                removing: removedScopes.count
            ))

            keepPathThrough(nil, in: routePath)
            keepPathThrough(ancestorResolution.pathIndex, in: ancestorResolution.path)
            await waitForRouteScopesToLeaveView(removedScopes)
            log.departureDebug(.unwindCompleted)

            return true

        case let .keepPathThrough(targetPathIndex):
            let removedScopes = routePath.scopesRemovedByKeepingThrough(targetPathIndex)
            log.departureDebug(.unwindAccepted(
                keepThrough: targetPathIndex,
                removing: removedScopes.count
            ))

            if target != nil {
                unwindPresentationSnapshot = UnwindPresentationSnapshot(
                    routePath: routePath,
                    preservedPath: removedScopes,
                    highPrioritySegment: highPrioritySegment
                )
            }
            keepPathThrough(targetPathIndex, in: routePath)
            if case .root = target {
                // A high-priority segment may live on a branch path that clearing the root path
                // doesn't touch; `.root` tears the whole app down, so drop it explicitly.
                highPrioritySegment = nil
            }
            await waitForRouteScopesToLeaveView(removedScopes)
            unwindPresentationSnapshot = nil
            log.departureDebug(.unwindCompleted)

            return true
        }
    }

    func appendRoute(_ route: any Route, after match: DeclarationMatch) async {
        log.departureDebug(.routeAppendPreparing(route: route, match: match))
        let preservesCurrentPath = preservesCurrentPath(for: match)
        let removedScopes = preservesCurrentPath ? [] : match.path.scopesRemovedByKeepingThrough(match.pathIndex)

        if preservesCurrentPath == false {
            keepPathThrough(match.pathIndex, in: match.path)
        }

        if match.declaration.presentationKind == .push {
            log.departureDebug(.routeAppendWaitingReplacingPushedScope(removedScopes: removedScopes.count))
            await waitForRouteScopesToLeaveView(removedScopes)
        }

        let waitsForBranchActivation = waitsForBranchActivation(for: match)

        guard activateBranch(for: match) else {
            log.departureDebug(.routeDroppedBranchActivationFailed(branch: match.branchID))
            return
        }

        appendOrPendRoute(
            route,
            after: match,
            startsHighPrioritySegment: false,
            waitsForBranchActivation: waitsForBranchActivation
        )
    }

    func waitsForBranchActivation(for match: DeclarationMatch) -> Bool {
        guard match.declaration.drivesPresentation == false else {
            return false
        }

        return match.declaringPath.scope(at: match.declaringPathIndex)?.activeBranch != match.branchID
    }

    func activateBranch(for match: DeclarationMatch) -> Bool {
        guard let scope = match.declaringPath.scope(at: match.declaringPathIndex) else {
            log.departureDebug(.branchActivationFailed(pathIndex: match.declaringPathIndex))
            return false
        }

        guard scope.activeBranch != match.branchID else {
            log.departureDebug(.branchActivationSkipped(branch: match.branchID, scope: scope))
            return true
        }

        let previousBranch = scope.activeBranch
        let didActivate = scope.setActiveBranch(match.branchID)

        if didActivate {
            log.departureDebug(.branchActivated(from: previousBranch, to: match.branchID, scope: scope))
        } else {
            log.departureDebug(.branchActivationRejected(from: previousBranch, to: match.branchID, scope: scope))
        }

        return didActivate
    }

    func replaceHighPrioritySegment(
        with route: any Route,
        after match: DeclarationMatch
    ) {
        log.departureDebug(.highPriorityReplacePreparing(route: route, match: match))
        keepPathThrough(match.pathIndex, in: match.path)

        let waitsForBranchActivation = waitsForBranchActivation(for: match)

        guard activateBranch(for: match) else {
            log.departureDebug(.routeDroppedBranchActivationFailed(branch: match.branchID))
            return
        }

        appendOrPendRoute(
            route,
            after: match,
            startsHighPrioritySegment: true,
            waitsForBranchActivation: waitsForBranchActivation
        )
    }

    func appendOrPendRoute(
        _ route: any Route,
        after match: DeclarationMatch,
        startsHighPrioritySegment: Bool,
        waitsForBranchActivation: Bool = false
    ) {
        guard waitsForBranchActivation == false else {
            log.departureDebug(.routePendingWaitingForActivatedBranchHost(route: route, branch: match.branchID))
            pendingRoute = PendingRoute(
                route: route,
                match: match,
                startsHighPrioritySegment: startsHighPrioritySegment
            )
            return
        }

        guard canPresentRoute(after: match) else {
            log.departureDebug(.routePendingWaitingForLocalPresentationScope(route: route, branch: match.branchID))
            pendingRoute = PendingRoute(
                route: route,
                match: match,
                startsHighPrioritySegment: startsHighPrioritySegment
            )
            return
        }

        pendingRoute = nil

        if startsHighPrioritySegment {
            highPrioritySegment = HighPrioritySegment(path: match.path, startIndex: match.path.endIndex)
            log.departureDebug(.highPrioritySegmentStarted(pathIndex: match.path.endIndex))
        }

        let appendedScope = RouteScope(id: route.id, route: route)
        // Resolve the host once, at write time, so the SwiftUI bindings read it directly instead of
        // re-deriving the closest declaring scope on every read. The presenter is not always the
        // declarer: when the route is placed into a different path than the one it was discovered
        // in (a branch adopting a top-level/branch declaration), the branch scope that owns the
        // target path is the presenter. Otherwise the declaring scope within the path hosts it.
        let hostScope = match.path === match.declaringPath
            ? match.path.scope(at: match.pathIndex)
            : match.path.owner
        appendedScope.hostScope = hostScope
        // `match.declaration` may be the discovery copy (drivesPresentation == false). The host
        // presents using its own adopted/local copy that actually drives presentation, so resolve
        // that from the host's attachments.
        appendedScope.hostDeclaration = hostScope?.routeAttachments.first(where: {
            $0.routeType == match.declaration.routeType
            && $0.presentationKind == match.declaration.presentationKind
            && $0.drivesPresentation
        }) ?? match.declaration
        // Place the route in its host's structural slot. Assigning `modalChild` replaces any prior
        // modal (the old one is trimmed from the path before we get here), so a host can never hold
        // two modals at once.
        if match.declaration.presentationKind == .push {
            hostScope?.pushChild = appendedScope
        } else {
            hostScope?.modalChild = appendedScope
        }
        match.path.append(appendedScope)
        log.departureDebug(.routeAppended(route: route, pathCount: match.path.count))
    }

    func resumePendingRoute(for branch: AnyHashable, in declaringScope: RouteScope) {
        log.departureDebug(.pendingResumeCheck(branch: branch, declaringScope: declaringScope))

        guard
            let pendingRoute,
            pendingRoute.match.branchID == branch,
            pendingRoute.match.declaringPath.scope(at: pendingRoute.match.declaringPathIndex) === declaringScope
        else {
            log.departureDebug(.pendingResumeSkipped)
            return
        }

        log.departureDebug(.pendingRouteResuming(route: pendingRoute.route))
        let match = pendingRoute.match.updatingPresentationPath(
            routePath(
                forBranch: pendingRoute.match.branchID,
                under: declaringScope,
                declaration: pendingRoute.match.declaration
            )
        )
        keepPathThrough(match.pathIndex, in: match.path)

        appendOrPendRoute(
            pendingRoute.route,
            after: match,
            startsHighPrioritySegment: pendingRoute.startsHighPrioritySegment
        )
    }

    func canPresentRoute(after match: DeclarationMatch) -> Bool {
        guard match.declaration.drivesPresentation == false else {
            log.departureDebug(.routeCanPresentDeclarationDrivesPresentation)
            return true
        }

        guard
            let declaringScope = match.declaringPath.scope(at: match.declaringPathIndex),
            declaringScope.activeBranch == match.branchID
        else {
            log.departureDebug(.routeCannotPresentDiscoveryBranchInactive(branch: match.branchID))
            return false
        }

        let activeLocalScope = declaringScope.activeLocalScope(for: match.branchID)
        let canPresent = activeLocalScope?.canDrivePresentation(for: match.declaration) == true
        if canPresent {
            log.departureDebug(.routeCanPresentActiveLocalScope(branch: match.branchID))
        } else {
            log.departureDebug(.routeCannotPresentNoActiveLocalScope(branch: match.branchID))
        }

        return canPresent
    }

    func keepPathThrough(_ pathIndex: [RouteScope].Index?, in routePath: RoutePath) {
        // Scopes leaving the path must release their host's structural slots, otherwise a dismissed
        // modal/push would still be reachable through `modalChild`/`pushChild`.
        for removed in routePath.scopesRemovedByKeepingThrough(pathIndex) {
            if removed.hostScope?.pushChild === removed {
                removed.hostScope?.pushChild = nil
            }
            if removed.hostScope?.modalChild === removed {
                removed.hostScope?.modalChild = nil
            }
        }

        guard let pathIndex else {
            let removedCount = routePath.count
            routePath.keepThrough(nil)
            removeHighPrioritySegmentStartIfNeeded(in: routePath)
            log.departureDebug(.pathCleared(removedCount: removedCount))
            return
        }

        let removalStartIndex = routePath.scopes.index(after: pathIndex)
        guard removalStartIndex < routePath.endIndex else {
            removeHighPrioritySegmentStartIfNeeded(in: routePath)
            log.departureDebug(.pathUnchanged(keepThrough: pathIndex))
            return
        }

        let removedCount = routePath.scopes.distance(from: removalStartIndex, to: routePath.endIndex)
        routePath.keepThrough(pathIndex)
        removeHighPrioritySegmentStartIfNeeded(in: routePath)
        log.departureDebug(.pathTrimmed(keepThrough: pathIndex, removedCount: removedCount))
    }

    func preservesCurrentPath(for match: DeclarationMatch) -> Bool {
        guard match.declaration.presentationKind != .push else {
            return false
        }

        guard
            let declaringScope = match.declaringPath.scope(at: match.declaringPathIndex),
            declaringScope.activeBranch == match.branchID
        else {
            return false
        }

        // A scope can host only one modal (sheet or cover) at a time.
        if RoutePresentationKind.modalKinds.contains(where: {
            routePresentation(from: declaringScope, matching: $0) != nil
        }) {
            return false
        }

        return true
    }

    func removeFromPath(_ routeScope: RouteScope) {
        guard
            let routePath = routePath(containing: routeScope),
            let pathIndex = routePath.scopes.firstIndex(where: { $0 === routeScope })
        else {
            log.departureDebug(.pathRemovalSkipped(scope: routeScope))
            return
        }

        log.departureDebug(.pathRemovalRequested(pathIndex: pathIndex, scope: routeScope))
        if pathIndex == routePath.scopes.startIndex {
            keepPathThrough(nil, in: routePath)
        } else {
            keepPathThrough(routePath.scopes.index(before: pathIndex), in: routePath)
        }
    }

    func removeHighPrioritySegmentStartIfNeeded(in routePath: RoutePath) {
        guard
            let highPrioritySegment,
            highPrioritySegment.path === routePath
        else {
            return
        }

        guard highPrioritySegment.startIndex < routePath.endIndex else {
            log.departureDebug(.highPrioritySegmentCleared)
            self.highPrioritySegment = nil
            return
        }
    }

    func routeScopeDidInstallInView(_ routeScope: RouteScope) {
        routeScope.mount()
        log.departureDebug(.scopeMounted(scope: routeScope))
    }

    func routeScopeDidLeaveView(_ routeScope: RouteScope) {
        guard routeScope.isMounted else { return }
        
        routeScope.unmount()
        log.departureDebug(.scopeUnmounted(scope: routeScope))
    }

    func waitForRouteScopesToLeaveView(_ routeScopes: [RouteScope]) async {
        let mountedRouteScopes = routeScopes.filter(\.isMounted)

        guard mountedRouteScopes.isEmpty == false else {
            log.departureDebug(.unmountWaitSkipped)
            return
        }

        log.departureDebug(.unmountWaitStarted(mounted: mountedRouteScopes.count))
        await withCheckedContinuation { continuation in
            var remainingCount = mountedRouteScopes.count

            for routeScope in mountedRouteScopes {
                routeScope.onUnmount {
                    remainingCount -= 1
                    log.departureDebug(.unmountWaitProgress(remaining: remainingCount))

                    if remainingCount == 0 {
                        continuation.resume()
                    }
                }
            }
        }
    }

    func routePath(containing routeScope: RouteScope) -> RoutePath? {
        if routeScope === root {
            return rootPath
        }

        if routeScope.mountedBranchID != nil {
            return routeScope.path
        }

        if let owningPath = routeScope.owningPath {
            return owningPath
        }

        if rootPath.contains(routeScope) {
            return rootPath
        }

        return routePath(containing: routeScope, under: root)
    }

    private func routePath(containing routeScope: RouteScope, under owner: RouteScope) -> RoutePath? {
        for branchScope in owner.mountedBranchScopes.values {
            if branchScope.path.contains(routeScope) {
                return branchScope.path
            }

            if let routePath = self.routePath(containing: routeScope, under: branchScope) {
                return routePath
            }
        }

        for scope in owner.path.scopes {
            if let routePath = self.routePath(containing: routeScope, under: scope) {
                return routePath
            }
        }

        return nil
    }

    private func ancestorUnwindResolution(
        from routePath: RoutePath,
        to target: UnwindTarget?
    ) -> (path: RoutePath, pathIndex: [RouteScope].Index?)? {
        guard case .id = target else {
            return nil
        }

        var scope = routePath.owner?.parent
        while let ancestorScope = scope {
            if let ancestorPath = self.routePath(containing: ancestorScope) {
                switch ancestorPath.unwindResolution(to: target) {
                case let .keepPathThrough(pathIndex):
                    return (ancestorPath, pathIndex)

                case .noRouteToUnwind, .targetNotFound:
                    break
                }
            }

            scope = ancestorScope.parent
        }

        return nil
    }

}

private extension RouteScope {
    func canDrivePresentation(for declaration: AnyRouteDeclaration) -> Bool {
        routeAttachments.contains {
            $0.routeType == declaration.routeType
            && $0.kind == declaration.kind
            && $0.drivesPresentation
        }
    }
}
