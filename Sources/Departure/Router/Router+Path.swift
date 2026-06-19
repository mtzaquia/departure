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
#if DEBUG
        log.departureDebug("unwind requested | target=\(String(describing: target))")
#endif

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
#if DEBUG
                log.departureDebug("unwind skipped | reason=not inside a branch")
#endif
                return true
            }
            routePath = branchPath

        case nil, .id:
            routePath = currentRoutePath
        }

        switch routePath.unwindResolution(to: target) {
        case .noRouteToUnwind:
#if DEBUG
            log.departureDebug("unwind skipped | reason=no route")
#endif
            return true

        case .targetNotFound:
            guard let ancestorResolution = ancestorUnwindResolution(from: routePath, to: target) else {
#if DEBUG
                log.departureDebug("unwind dropped | reason=target not found | target=\(String(describing: target))")
#endif
                return false
            }

            let removedScopes = routePath.scopesRemovedByKeepingThrough(nil)
            + ancestorResolution.path.scopesRemovedByKeepingThrough(ancestorResolution.pathIndex)
#if DEBUG
            log.departureDebug(
                "unwind accepted | reason=ancestor target | keepThrough=\(String(describing: ancestorResolution.pathIndex)) | removing=\(removedScopes.count)"
            )
#endif

            keepPathThrough(nil, in: routePath)
            keepPathThrough(ancestorResolution.pathIndex, in: ancestorResolution.path)
            await waitForRouteScopesToLeaveView(removedScopes)
#if DEBUG
            log.departureDebug("unwind completed | removed scopes left view")
#endif

            return true

        case let .keepPathThrough(targetPathIndex):
            let removedScopes = routePath.scopesRemovedByKeepingThrough(targetPathIndex)
#if DEBUG
            log.departureDebug(
                "unwind accepted | keepThrough=\(String(describing: targetPathIndex)) | removing=\(removedScopes.count)"
            )
#endif

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
#if DEBUG
            log.departureDebug("unwind completed | removed scopes left view")
#endif

            return true
        }
    }

    func appendRoute(_ route: any Route, after match: DeclarationMatch) async {
#if DEBUG
        log.departureDebug("route append preparing | route=\(route.departureDebugDescription) | \(match.departureDebugDescription)")
#endif
        let preservesCurrentPath = preservesCurrentPath(for: match)
        let removedScopes = preservesCurrentPath ? [] : match.path.scopesRemovedByKeepingThrough(match.pathIndex)

        if preservesCurrentPath == false {
            keepPathThrough(match.pathIndex, in: match.path)
        }

        if match.declaration.presentationKind == .push {
#if DEBUG
            log.departureDebug("route append waiting | reason=replacing pushed scope | removedScopes=\(removedScopes.count)")
#endif
            await waitForRouteScopesToLeaveView(removedScopes)
        }

        let waitsForBranchActivation = waitsForBranchActivation(for: match)

        guard activateBranch(for: match) else {
#if DEBUG
            log.departureDebug("route dropped | reason=branch activation failed | branch=\(match.branchID.departureDebugDescription)")
#endif
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
#if DEBUG
            log.departureDebug("branch activation failed | reason=no scope | pathIndex=\(String(describing: match.declaringPathIndex))")
#endif
            return false
        }

        guard scope.activeBranch != match.branchID else {
#if DEBUG
            log.departureDebug(
                "branch activation skipped | branch=\(match.branchID.departureDebugDescription) | reason=already active | scope=\(scope.departureDebugDescription)"
            )
#endif
            return true
        }

        let previousBranch = scope.activeBranch
        let didActivate = scope.setActiveBranch(match.branchID)

        if didActivate {
#if DEBUG
            log.departureDebug(
                "branch activated | from=\(previousBranch.departureDebugDescription) | to=\(match.branchID.departureDebugDescription) | scope=\(scope.departureDebugDescription)"
            )
#endif
        } else {
#if DEBUG
            log.departureDebug(
                "branch activation rejected | from=\(previousBranch.departureDebugDescription) | to=\(match.branchID.departureDebugDescription) | scope=\(scope.departureDebugDescription)"
            )
#endif
        }

        return didActivate
    }

    func replaceHighPrioritySegment(
        with route: any Route,
        after match: DeclarationMatch
    ) {
#if DEBUG
        log.departureDebug(
            "high-priority replace preparing | route=\(route.departureDebugDescription) | \(match.departureDebugDescription)"
        )
#endif
        keepPathThrough(match.pathIndex, in: match.path)

        let waitsForBranchActivation = waitsForBranchActivation(for: match)

        guard activateBranch(for: match) else {
#if DEBUG
            log.departureDebug("route dropped | reason=branch activation failed | branch=\(match.branchID.departureDebugDescription)")
#endif
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
#if DEBUG
            log.departureDebug(
                "route pending | route=\(route.departureDebugDescription) | branch=\(match.branchID.departureDebugDescription) | reason=waiting for activated branch host"
            )
#endif
            pendingRoute = PendingRoute(
                route: route,
                match: match,
                startsHighPrioritySegment: startsHighPrioritySegment
            )
            return
        }

        guard canPresentRoute(after: match) else {
#if DEBUG
            log.departureDebug(
                "route pending | route=\(route.departureDebugDescription) | branch=\(match.branchID.departureDebugDescription) | reason=waiting for local presentation scope"
            )
#endif
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
#if DEBUG
            log.departureDebug("high-priority segment started | pathIndex=\(match.path.endIndex)")
#endif
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
#if DEBUG
        log.departureDebug("route appended | route=\(route.departureDebugDescription) | pathCount=\(match.path.count)")
#endif
    }

    func resumePendingRoute(for branch: AnyHashable, in declaringScope: RouteScope) {
#if DEBUG
        log.departureDebug(
            "pending resume check | branch=\(branch.departureDebugDescription) | declaringScope=\(declaringScope.departureDebugDescription)"
        )
#endif

        guard
            let pendingRoute,
            pendingRoute.match.branchID == branch,
            pendingRoute.match.declaringPath.scope(at: pendingRoute.match.declaringPathIndex) === declaringScope
        else {
#if DEBUG
            log.departureDebug("pending resume skipped | reason=no matching pending route")
#endif
            return
        }

#if DEBUG
        log.departureDebug("pending route resuming | route=\(pendingRoute.route.departureDebugDescription)")
#endif
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
#if DEBUG
            log.departureDebug("route can present | reason=declaration drives presentation")
#endif
            return true
        }

        guard
            let declaringScope = match.declaringPath.scope(at: match.declaringPathIndex),
            declaringScope.activeBranch == match.branchID
        else {
#if DEBUG
            log.departureDebug(
                "route cannot present | branch=\(match.branchID.departureDebugDescription) | reason=discovery branch inactive"
            )
#endif
            return false
        }

        let activeLocalScope = declaringScope.activeLocalScope(for: match.branchID)
        let canPresent = activeLocalScope?.canDrivePresentation(for: match.declaration) == true
        if canPresent {
#if DEBUG
            log.departureDebug("route can present | branch=\(match.branchID.departureDebugDescription) | reason=active local scope")
#endif
        } else {
#if DEBUG
            log.departureDebug("route cannot present | branch=\(match.branchID.departureDebugDescription) | reason=no active local scope")
#endif
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
#if DEBUG
            let removedCount = routePath.count
#endif
            routePath.keepThrough(nil)
            removeHighPrioritySegmentStartIfNeeded(in: routePath)
#if DEBUG
            log.departureDebug("path cleared | removed=\(removedCount)")
#endif
            return
        }

        let removalStartIndex = routePath.scopes.index(after: pathIndex)
        guard removalStartIndex < routePath.endIndex else {
            removeHighPrioritySegmentStartIfNeeded(in: routePath)
#if DEBUG
            log.departureDebug("path unchanged | keepThrough=\(pathIndex)")
#endif
            return
        }

#if DEBUG
        let removedCount = routePath.scopes.distance(from: removalStartIndex, to: routePath.endIndex)
#endif
        routePath.keepThrough(pathIndex)
        removeHighPrioritySegmentStartIfNeeded(in: routePath)
#if DEBUG
        log.departureDebug("path trimmed | keepThrough=\(pathIndex) | removed=\(removedCount)")
#endif
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
#if DEBUG
            log.departureDebug("path removal skipped | reason=scope not in path | scope=\(routeScope.departureDebugDescription)")
#endif
            return
        }

#if DEBUG
        log.departureDebug("path removal requested | pathIndex=\(pathIndex) | scope=\(routeScope.departureDebugDescription)")
#endif
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
#if DEBUG
            log.departureDebug("high-priority segment cleared")
#endif
            self.highPrioritySegment = nil
            return
        }
    }

    func routeScopeDidInstallInView(_ routeScope: RouteScope) {
        routeScope.mount()
#if DEBUG
        log.departureDebug("scope mounted | scope=\(routeScope.departureDebugDescription)")
#endif
    }

    func routeScopeDidLeaveView(_ routeScope: RouteScope) {
        guard routeScope.isMounted else { return }
        
        routeScope.unmount()
#if DEBUG
        log.departureDebug("scope unmounted | scope=\(routeScope.departureDebugDescription)")
#endif
    }

    func waitForRouteScopesToLeaveView(_ routeScopes: [RouteScope]) async {
        let mountedRouteScopes = routeScopes.filter(\.isMounted)

        guard mountedRouteScopes.isEmpty == false else {
#if DEBUG
            log.departureDebug("unmount wait skipped | reason=no mounted scopes")
#endif
            return
        }

#if DEBUG
        log.departureDebug("unmount wait started | mounted=\(mountedRouteScopes.count)")
#endif
        await withCheckedContinuation { continuation in
            var remainingCount = mountedRouteScopes.count

            for routeScope in mountedRouteScopes {
                routeScope.onUnmount {
                    remainingCount -= 1
#if DEBUG
                    log.departureDebug(
                        "unmount wait progress | remaining=\(remainingCount)"
                    )
#endif

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
