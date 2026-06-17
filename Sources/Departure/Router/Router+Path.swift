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
        log.departureDebug("Unwind requested: target: \(String(describing: target)).")
#endif

        switch unwindResolution(for: target) {
        case .noRouteToUnwind:
#if DEBUG
            log.departureDebug("Unwind skipped: no route to unwind.")
#endif
            return true

        case .targetNotFound:
#if DEBUG
            log.departureDebug("Unwind dropped: target not found: \(String(describing: target)).")
#endif
            return false

        case let .keepPathThrough(targetPathIndex):
            let removedScopes = routeScopesRemovedByKeepingPathThrough(targetPathIndex)
#if DEBUG
            log.departureDebug(
                "Unwind accepted: keeping path through \(String(describing: targetPathIndex)), removing \(removedScopes.count) scope(s)."
            )
#endif

            unwindPresentationSnapshot = UnwindPresentationSnapshot(
                preservedPath: presentationPathPreservedByKeepingPathThrough(targetPathIndex),
                highPrioritySegmentStartIndex: highPrioritySegmentStartIndex
            )
            keepPathThrough(targetPathIndex)
            await waitForRouteScopesToLeaveView(removedScopes)
            unwindPresentationSnapshot = nil
#if DEBUG
            log.departureDebug("Unwind completed: removed scope(s) left view.")
#endif

            return true
        }
    }

    func pathIndex(of routeScope: RouteScope) -> [RouteScope].Index? {
        pathIndex(of: routeScope, in: path)
    }

    func pathIndex(
        of routeScope: RouteScope,
        in path: [RouteScope]
    ) -> [RouteScope].Index? {
        guard routeScope !== root else {
            return nil
        }

        if let pathIndex = path.firstIndex(where: { $0 === routeScope }) {
            return pathIndex
        }

        guard let parent = routeScope.parent else {
            return nil
        }

        return pathIndex(of: parent, in: path)
    }

    func contains(_ routeScope: RouteScope, in path: [RouteScope]) -> Bool {
        routeScope === root || pathIndex(of: routeScope, in: path) != nil || routeScope.parent === root
    }

    func scope(at pathIndex: [RouteScope].Index?) -> RouteScope? {
        guard let pathIndex else {
            return root
        }

        guard path.indices.contains(pathIndex) else {
            return nil
        }

        return path[pathIndex]
    }

    func appendRoute(_ route: any Route, after match: DeclarationMatch) async {
#if DEBUG
        log.departureDebug("Route append preparing: \(route.departureDebugDescription) after \(match.departureDebugDescription).")
#endif
        let removedScopes = routeScopesRemovedByKeepingPathThrough(match.pathIndex)
        keepPathThrough(match.pathIndex)

        if match.declaration.presentationKind == .push {
#if DEBUG
            log.departureDebug("Route append waiting for pushed scope(s) to leave view before pushing next route.")
#endif
            await waitForRouteScopesToLeaveView(removedScopes)
        }

        guard activateBranch(for: match) else {
#if DEBUG
            log.departureDebug("Route dropped: failed to activate branch \(match.branchID.departureDebugDescription).")
#endif
            return
        }

        appendOrPendRoute(
            route,
            after: match,
            startsHighPrioritySegment: false
        )
    }

    func activateBranch(for match: DeclarationMatch) -> Bool {
        guard let scope = scope(at: match.pathIndex) else {
#if DEBUG
            log.departureDebug("Branch activation failed: no scope at \(String(describing: match.pathIndex)).")
#endif
            return false
        }

        guard scope.activeBranch != match.branchID else {
#if DEBUG
            log.departureDebug(
                "Branch activation skipped: \(match.branchID.departureDebugDescription) already active in \(scope.departureDebugDescription)."
            )
#endif
            return true
        }

        let previousBranch = scope.activeBranch
        let didActivate = scope.setActiveBranch(match.branchID)

        if didActivate {
#if DEBUG
            log.departureDebug(
                "Branch activated: \(previousBranch.departureDebugDescription) -> \(match.branchID.departureDebugDescription) in \(scope.departureDebugDescription)."
            )
#endif
        } else {
#if DEBUG
            log.departureDebug(
                "Branch activation rejected: \(previousBranch.departureDebugDescription) -> \(match.branchID.departureDebugDescription) in \(scope.departureDebugDescription)."
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
            "High-priority segment replace preparing: \(route.departureDebugDescription) after \(match.departureDebugDescription)."
        )
#endif
        keepPathThrough(match.pathIndex)

        guard activateBranch(for: match) else {
#if DEBUG
            log.departureDebug("Route dropped: failed to activate branch \(match.branchID.departureDebugDescription).")
#endif
            return
        }

        appendOrPendRoute(
            route,
            after: match,
            startsHighPrioritySegment: true
        )
    }

    func appendOrPendRoute(
        _ route: any Route,
        after match: DeclarationMatch,
        startsHighPrioritySegment: Bool
    ) {
        guard canPresentRoute(after: match) else {
#if DEBUG
            log.departureDebug(
                "Route pending: \(route.departureDebugDescription) waits for branch \(match.branchID.departureDebugDescription) to install a local presentation scope."
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
            highPrioritySegmentStartIndex = path.endIndex
#if DEBUG
            log.departureDebug("High-priority segment starts at path index \(path.endIndex).")
#endif
        }

        path.append(RouteScope(id: route.id, route: route))
#if DEBUG
        log.departureDebug("Route appended: \(route.departureDebugDescription). Path count: \(path.count).")
#endif
    }

    func resumePendingRoute(for branch: AnyHashable, in declaringScope: RouteScope) {
#if DEBUG
        log.departureDebug(
            "Pending route resume check: branch \(branch.departureDebugDescription), declaring scope: \(declaringScope.departureDebugDescription)."
        )
#endif

        guard
            let pendingRoute,
            pendingRoute.match.branchID == branch,
            scope(at: pendingRoute.match.pathIndex) === declaringScope
        else {
#if DEBUG
            log.departureDebug("Pending route resume skipped: no matching pending route.")
#endif
            return
        }

#if DEBUG
        log.departureDebug("Pending route resuming: \(pendingRoute.route.departureDebugDescription).")
#endif
        keepPathThrough(pendingRoute.match.pathIndex)

        appendOrPendRoute(
            pendingRoute.route,
            after: pendingRoute.match,
            startsHighPrioritySegment: pendingRoute.startsHighPrioritySegment
        )
    }

    func canPresentRoute(after match: DeclarationMatch) -> Bool {
        guard match.declaration.drivesPresentation == false else {
#if DEBUG
            log.departureDebug("Route can present immediately: declaration drives presentation.")
#endif
            return true
        }

        guard
            let declaringScope = scope(at: match.pathIndex),
            declaringScope.activeBranch == match.branchID
        else {
#if DEBUG
            log.departureDebug(
                "Route cannot present yet: declaration is discovery-only and branch \(match.branchID.departureDebugDescription) is not active."
            )
#endif
            return false
        }

        let canPresent = declaringScope.activeLocalScope.id == match.branchID
        if canPresent {
#if DEBUG
            log.departureDebug("Route can present: branch \(match.branchID.departureDebugDescription) has an active local scope.")
#endif
        } else {
#if DEBUG
            log.departureDebug("Route cannot present yet: branch \(match.branchID.departureDebugDescription) has no active local scope.")
#endif
        }

        return canPresent
    }

    func keepPathThrough(_ pathIndex: [RouteScope].Index?) {
        guard let pathIndex else {
#if DEBUG
            let removedCount = path.count
#endif
            path.removeAll()
            removeHighPrioritySegmentStartIfNeeded()
#if DEBUG
            log.departureDebug("Path cleared: removed \(removedCount) scope(s).")
#endif
            return
        }

        let removalStartIndex = path.index(after: pathIndex)
        guard removalStartIndex < path.endIndex else {
            removeHighPrioritySegmentStartIfNeeded()
#if DEBUG
            log.departureDebug("Path unchanged: already kept through \(pathIndex).")
#endif
            return
        }

#if DEBUG
        let removedCount = path.distance(from: removalStartIndex, to: path.endIndex)
#endif
        path.removeSubrange(removalStartIndex..<path.endIndex)
        removeHighPrioritySegmentStartIfNeeded()
#if DEBUG
        log.departureDebug("Path trimmed: kept through \(pathIndex), removed \(removedCount) scope(s).")
#endif
    }

    func removeFromPath(_ routeScope: RouteScope) {
        guard let pathIndex = path.firstIndex(where: { $0 === routeScope }) else {
#if DEBUG
            log.departureDebug("Path removal skipped: scope not in path: \(routeScope.departureDebugDescription).")
#endif
            return
        }

#if DEBUG
        log.departureDebug("Path removal requested for scope at \(pathIndex): \(routeScope.departureDebugDescription).")
#endif
        if pathIndex == path.startIndex {
            keepPathThrough(nil)
        } else {
            keepPathThrough(path.index(before: pathIndex))
        }
    }

    func removeHighPrioritySegmentStartIfNeeded() {
        guard
            let highPrioritySegmentStartIndex,
            highPrioritySegmentStartIndex < path.endIndex
        else {
            if self.highPrioritySegmentStartIndex != nil {
#if DEBUG
                log.departureDebug("High-priority segment cleared.")
#endif
            }
            self.highPrioritySegmentStartIndex = nil
            return
        }
    }

    func routeScopeDidInstallInView(_ routeScope: RouteScope) {
        routeScope.mount()
#if DEBUG
        log.departureDebug("Route scope mounted: \(routeScope.departureDebugDescription).")
#endif
    }

    func routeScopeDidLeaveView(_ routeScope: RouteScope) {
        routeScope.unmount()
#if DEBUG
        log.departureDebug("Route scope unmounted: \(routeScope.departureDebugDescription).")
#endif
        removeFromPath(routeScope)
    }

    func waitForRouteScopesToLeaveView(_ routeScopes: [RouteScope]) async {
        let mountedRouteScopes = routeScopes.filter(\.isMounted)

        guard mountedRouteScopes.isEmpty == false else {
#if DEBUG
            log.departureDebug("Unmount wait skipped: no mounted route scopes.")
#endif
            return
        }

#if DEBUG
        log.departureDebug("Unmount wait started: \(mountedRouteScopes.count) mounted scope(s).")
#endif
        await withCheckedContinuation { continuation in
            var remainingCount = mountedRouteScopes.count

            for routeScope in mountedRouteScopes {
                routeScope.onUnmount {
                    remainingCount -= 1
#if DEBUG
                    log.departureDebug(
                        "Unmount wait progress: \(remainingCount) mounted scope(s) remaining."
                    )
#endif

                    if remainingCount == 0 {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func unwindResolution(for target: UnwindTarget?) -> UnwindResolution {
        guard let target else {
            guard let currentPathIndex = path.indices.last else {
                return .noRouteToUnwind
            }

            guard currentPathIndex > path.startIndex else {
                return .keepPathThrough(nil)
            }

            return .keepPathThrough(path.index(before: currentPathIndex))
        }

        switch target {
        case .root:
            return .keepPathThrough(nil)

        case let .id(id):
            if root.id == id {
                return .keepPathThrough(nil)
            }

            guard let pathIndex = path.lastIndex(where: { $0.id == id }) else {
                return .targetNotFound
            }

            return .keepPathThrough(pathIndex)
        }
    }

    private func routeScopesRemovedByKeepingPathThrough(_ pathIndex: [RouteScope].Index?) -> [RouteScope] {
        guard let pathIndex else {
            return path
        }

        let removalStartIndex = path.index(after: pathIndex)

        guard removalStartIndex < path.endIndex else {
            return []
        }

        return Array(path[removalStartIndex..<path.endIndex])
    }

    private func presentationPathPreservedByKeepingPathThrough(_ pathIndex: [RouteScope].Index?) -> [RouteScope] {
        guard let pathIndex else {
            return path
        }

        let preservationStartIndex = path.index(after: pathIndex)

        guard preservationStartIndex < path.endIndex else {
            return []
        }

        return Array(path[preservationStartIndex..<path.endIndex])
    }
}

private enum UnwindResolution {
    case noRouteToUnwind
    case targetNotFound
    case keepPathThrough([RouteScope].Index?)
}
