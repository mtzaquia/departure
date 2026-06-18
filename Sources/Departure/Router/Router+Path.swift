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

        switch unwindResolution(for: target) {
        case .noRouteToUnwind:
#if DEBUG
            log.departureDebug("unwind skipped | reason=no route")
#endif
            return true

        case .targetNotFound:
#if DEBUG
            log.departureDebug("unwind dropped | reason=target not found | target=\(String(describing: target))")
#endif
            return false

        case let .keepPathThrough(targetPathIndex):
            let removedScopes = routeScopesRemovedByKeepingPathThrough(targetPathIndex)
#if DEBUG
            log.departureDebug(
                "unwind accepted | keepThrough=\(String(describing: targetPathIndex)) | removing=\(removedScopes.count)"
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
            log.departureDebug("unwind completed | removed scopes left view")
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
        log.departureDebug("route append preparing | route=\(route.departureDebugDescription) | \(match.departureDebugDescription)")
#endif
        let removedScopes = routeScopesRemovedByKeepingPathThrough(match.pathIndex)
        keepPathThrough(match.pathIndex)

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

        return scope(at: match.pathIndex)?.activeBranch != match.branchID
    }

    func activateBranch(for match: DeclarationMatch) -> Bool {
        guard let scope = scope(at: match.pathIndex) else {
#if DEBUG
            log.departureDebug("branch activation failed | reason=no scope | pathIndex=\(String(describing: match.pathIndex))")
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
        keepPathThrough(match.pathIndex)

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
            highPrioritySegmentStartIndex = path.endIndex
#if DEBUG
            log.departureDebug("high-priority segment started | pathIndex=\(path.endIndex)")
#endif
        }

        path.append(RouteScope(id: route.id, route: route))
#if DEBUG
        log.departureDebug("route appended | route=\(route.departureDebugDescription) | pathCount=\(path.count)")
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
            scope(at: pendingRoute.match.pathIndex) === declaringScope
        else {
#if DEBUG
            log.departureDebug("pending resume skipped | reason=no matching pending route")
#endif
            return
        }

#if DEBUG
        log.departureDebug("pending route resuming | route=\(pendingRoute.route.departureDebugDescription)")
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
            log.departureDebug("route can present | reason=declaration drives presentation")
#endif
            return true
        }

        guard
            let declaringScope = scope(at: match.pathIndex),
            declaringScope.activeBranch == match.branchID
        else {
#if DEBUG
            log.departureDebug(
                "route cannot present | branch=\(match.branchID.departureDebugDescription) | reason=discovery branch inactive"
            )
#endif
            return false
        }

        let activeLocalScope = declaringScope.activeLocalScope
        let canPresent = activeLocalScope.id == match.branchID
            && activeLocalScope.canDrivePresentation(for: match.declaration)
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

    func keepPathThrough(_ pathIndex: [RouteScope].Index?) {
        guard let pathIndex else {
#if DEBUG
            let removedCount = path.count
#endif
            path.removeAll()
            removeHighPrioritySegmentStartIfNeeded()
#if DEBUG
            log.departureDebug("path cleared | removed=\(removedCount)")
#endif
            return
        }

        let removalStartIndex = path.index(after: pathIndex)
        guard removalStartIndex < path.endIndex else {
            removeHighPrioritySegmentStartIfNeeded()
#if DEBUG
            log.departureDebug("path unchanged | keepThrough=\(pathIndex)")
#endif
            return
        }

#if DEBUG
        let removedCount = path.distance(from: removalStartIndex, to: path.endIndex)
#endif
        path.removeSubrange(removalStartIndex..<path.endIndex)
        removeHighPrioritySegmentStartIfNeeded()
#if DEBUG
        log.departureDebug("path trimmed | keepThrough=\(pathIndex) | removed=\(removedCount)")
#endif
    }

    func removeFromPath(_ routeScope: RouteScope) {
        guard let pathIndex = path.firstIndex(where: { $0 === routeScope }) else {
#if DEBUG
            log.departureDebug("path removal skipped | reason=scope not in path | scope=\(routeScope.departureDebugDescription)")
#endif
            return
        }

#if DEBUG
        log.departureDebug("path removal requested | pathIndex=\(pathIndex) | scope=\(routeScope.departureDebugDescription)")
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
                log.departureDebug("high-priority segment cleared")
#endif
            }
            self.highPrioritySegmentStartIndex = nil
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

private extension RouteScope {
    func canDrivePresentation(for declaration: AnyRouteDeclaration) -> Bool {
        routeAttachments.contains {
            $0.routeType == declaration.routeType
            && $0.kind == declaration.kind
            && $0.drivesPresentation
        }
    }
}

private enum UnwindResolution {
    case noRouteToUnwind
    case targetNotFound
    case keepPathThrough([RouteScope].Index?)
}
