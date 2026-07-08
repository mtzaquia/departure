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
    final class PendingRoute {
        struct Append {
            let match: DeclarationMatch
            let behavior: RouteAppendBehavior
            let blockingScopes: [RouteScope]

            init(
                match: DeclarationMatch,
                behavior: RouteAppendBehavior,
                blockingScopes: [RouteScope] = []
            ) {
                self.match = match
                self.behavior = behavior
                self.blockingScopes = blockingScopes
            }
        }

        let route: any Route
        let state: State

        enum State {
            case request(CheckedContinuation<Void, Never>)
            case append(Append)
        }

        init(route: any Route, state: State) {
            self.route = route
            self.state = state
        }

        var append: Append? {
            guard case let .append(append) = state else {
                return nil
            }

            return append
        }

        func resumeRequestIfNeeded() {
            guard case let .request(continuation) = state else {
                return
            }

            continuation.resume()
        }
    }

    struct UnwindPresentationSnapshot {
        struct PreservedRoutePath {
            let routePath: RoutePath
            let scopes: [RouteScope]
        }

        let preservedPaths: [PreservedRoutePath]
        let routeForest: RouteForest

        init(
            preservedPaths: [PreservedRoutePath],
            routeForest: RouteForest
        ) {
            self.preservedPaths = preservedPaths
            self.routeForest = routeForest
        }
    }

    struct EquivalentRouteMatch {
        let position: RoutePath.Position
    }

    struct UnwindHandlerDeliveryKey: Equatable, Hashable {
        let sourceScopeID: ObjectIdentifier
        let targetScopeID: AnyHashable

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.sourceScopeID == rhs.sourceScopeID
            && lhs.targetScopeID == rhs.targetScopeID
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(sourceScopeID)
            hasher.combine(targetScopeID)
        }
    }

    struct DeliveredUnwindHandler {
        weak var sourceScope: RouteScope?
    }

    enum RouteAppendBehavior {
        case append
        case startElevatedTree(RoutePriority)

        var startsElevatedTree: Bool {
            if case .startElevatedTree = self {
                return true
            }

            return false
        }
    }

    @discardableResult
    func unwindAndWait(to target: UnwindTarget?, payload: Any? = nil) async -> Bool {
        log.departureDebug(.unwindRequested(target: target))
        let sourceScope = currentRouteScope

        if case .root = target {
            let plan = routeForest.unwindPlan(for: .root)
            log.departureDebug(.unwindAccepted(
                keepThrough: .owner,
                removing: plan.removedScopes.count
            ))

            await performPlannedUnwind(
                for: sourceScope,
                payload: payload,
                in: root,
                plan: plan
            )
            return true
        }

        // Non-root targets differ only by which path they clear. `.nearestBranch` resolves against
        // the enclosing branch path (no-op when there isn't one). Everything else resolves against
        // the current path.
        let routePath: RoutePath
        switch target {
        case .root:
            routePath = normalTree.rootPath

        case .nearestBranch:
            guard let branchPath = nearestBranchPath else {
                // Not inside a branch — there is nothing nearer to unwind to.
                log.departureDebug(.unwindSkippedNotInsideBranch)
                return true
            }
            routePath = branchPath

        case nil, .previous, .id:
            routePath = routeForest.activeTree.currentRoutePath
        }

        switch routePath.unwindResolution(to: target) {
        case .noRouteToUnwind:
            log.departureDebug(.unwindSkippedNoRoute)
            return true

        case .targetNotFound:
            guard let ancestorResolution = routeForest.ancestorUnwindResolution(from: routePath, to: target) else {
                log.departureDebug(.unwindDroppedTargetNotFound(target: target))
                return false
            }

            let plan = routeForest.unwindPlan(for: .combined([
                .scoped(routePath: routePath, after: .owner),
                .scoped(routePath: ancestorResolution.path, after: ancestorResolution.position),
            ]))
            log.departureDebug(.unwindAcceptedAncestorTarget(
                keepThrough: ancestorResolution.position,
                removing: plan.removedScopes.count
            ))

            let targetScope = ancestorResolution.path.scope(at: ancestorResolution.position)
            await performPlannedUnwind(
                for: sourceScope,
                payload: payload,
                in: targetScope,
                plan: plan
            )

            return true

        case let .keepPathThrough(targetPosition):
            let plan = routeForest.unwindPlan(for: .scoped(routePath: routePath, after: targetPosition))
            log.departureDebug(.unwindAccepted(
                keepThrough: targetPosition,
                removing: plan.removedScopes.count
            ))

            let targetScope = unwindHandlerScope(
                for: target,
                in: routePath,
                keepThrough: targetPosition
            )

            await performPlannedUnwind(
                for: sourceScope,
                payload: payload,
                in: targetScope,
                plan: plan,
                preservesSnapshot: target != nil
            )

            return true
        }
    }

    @discardableResult
    func unwindRoute(from sourceScope: RouteScope, payload: Any? = nil) async -> Bool {
        log.departureDebug(.unwindRequested(target: nil))

        guard
            let routePath = routeForest.routePath(containing: sourceScope),
            let targetPosition = routePath.positionBefore(sourceScope)
        else {
            log.departureDebug(.unwindSkippedNoRoute)
            return true
        }

        let plan = routeForest.unwindPlan(for: .scoped(routePath: routePath, after: targetPosition))
        guard plan.removedScopes.isEmpty == false else {
            log.departureDebug(.unwindSkippedNoRoute)
            return true
        }

        log.departureDebug(.unwindAccepted(
            keepThrough: targetPosition,
            removing: plan.removedScopes.count
        ))

        let targetScope = unwindHandlerScope(
            for: nil,
            in: routePath,
            keepThrough: targetPosition
        )

        await performPlannedUnwind(
            for: sourceScope,
            payload: payload,
            in: targetScope,
            plan: plan
        )

        return true
    }

    func appendRoute(_ route: any Route, after match: DeclarationMatch) async {
        if await deferRouteAppendIfNeeded(route, after: match) {
            return
        }

        if await unwindToExistingEquivalentRouteIfNeeded(route, after: match) {
            return
        }

        log.departureDebug(.routeAppendPreparing(route: route, match: match))
        let removedScopes = prepareNormalAppendPath(after: match)

        if removedScopes.isEmpty == false {
            log.departureDebug(.routeAppendWaitingReplacingScopes(removedScopes: removedScopes.count))
            if await deferRouteAppend(route, after: match, until: removedScopes) {
                return
            }
        }

        appendPreparedRoute(route, after: match)
    }

    func appendPreparedRoute(_ route: any Route, after match: DeclarationMatch) {
        let waitsForBranchActivation = waitsForBranchActivation(for: match)

        guard activateBranch(for: match) else {
            if let branchID = match.branchID {
                log.departureDebug(.routeDroppedBranchActivationFailed(branch: branchID))
            }
            return
        }

        appendOrPendRoute(
            route,
            after: match,
            behavior: .append,
            waitsForBranchActivation: waitsForBranchActivation
        )
    }

    func unwindToExistingEquivalentRouteIfNeeded(_ route: any Route, after match: DeclarationMatch) async -> Bool {
        guard let equivalentRouteMatch = equivalentRouteMatch(to: route, after: match) else {
            return false
        }

        guard activateBranch(for: match) else {
            if let branchID = match.branchID {
                log.departureDebug(.routeDroppedBranchActivationFailed(branch: branchID))
            }
            return true
        }

        let targetPosition = equivalentRouteMatch.position
        let removedScopes = match.path.scopesRemovedAfter(targetPosition)
        let sourceScope = removedScopes.last
        let targetScope = match.path.scope(at: targetPosition)
        guard removedScopes.isEmpty == false else {
            if let existingRoute = match.path.scope(at: targetPosition)?.route {
                log.departureDebug(.routeNoOpEquivalent(route: route, currentRoute: existingRoute))
            }
            return true
        }

        await performAcceptedUnwind(
            for: sourceScope,
            payload: nil,
            in: targetScope,
            removing: removedScopes,
            logsCompletion: false
        ) {
            keepPathThrough(targetPosition, in: match.path)
        }
        return true
    }

    func unwindToExistingEquivalentRouteInPriorityTreeIfNeeded(
        _ route: any Route,
        priority: RoutePriority
    ) async -> Bool {
        guard
            let tree = routeForest.tree(for: priority),
            let equivalentRouteMatch = equivalentRouteMatch(to: route, in: tree.currentRoutePath)
        else {
            return false
        }

        let targetPosition = equivalentRouteMatch.position
        let removedScopes = tree.currentRoutePath.scopesRemovedAfter(targetPosition)
        let sourceScope = removedScopes.last
        let targetScope = tree.currentRoutePath.scope(at: targetPosition)
        guard removedScopes.isEmpty == false else {
            if let existingRoute = tree.currentRoutePath.scope(at: targetPosition)?.route {
                log.departureDebug(.routeNoOpEquivalent(route: route, currentRoute: existingRoute))
            }
            return true
        }

        await performAcceptedUnwind(
            for: sourceScope,
            payload: nil,
            in: targetScope,
            removing: removedScopes,
            logsCompletion: false
        ) {
            keepPathThrough(targetPosition, in: tree.currentRoutePath)
        }
        return true
    }

    func equivalentRouteMatch(
        to route: any Route,
        after match: DeclarationMatch
    ) -> EquivalentRouteMatch? {
        equivalentRouteMatch(to: route, in: match.path, startingAt: match.position)
    }

    func equivalentRouteMatch(
        to route: any Route,
        in routePath: RoutePath,
        startingAt position: RoutePath.Position? = nil
    ) -> EquivalentRouteMatch? {
        for scope in routePath.scopes.reversed() {
            if scope.route?._isEqual(to: route) == true {
                return EquivalentRouteMatch(position: .scope(scope))
            }

            if position == .scope(scope) {
                return nil
            }
        }

        guard (position == nil || position == .owner),
              routePath.owner?.route?._isEqual(to: route) == true
        else {
            return nil
        }

        return EquivalentRouteMatch(position: .owner)
    }

    func waitsForBranchActivation(for match: DeclarationMatch) -> Bool {
        guard let branchID = match.branchID else {
            return false
        }

        return match.declaringPath.scope(at: match.declaringPosition)?.activeBranch != branchID
    }

    func activateBranch(for match: DeclarationMatch) -> Bool {
        guard let branchID = match.branchID else {
            return true
        }

        guard let scope = match.declaringPath.scope(at: match.declaringPosition) else {
            log.departureDebug(.branchActivationFailed(position: match.declaringPosition))
            return false
        }

        guard scope.activeBranch != branchID else {
            log.departureDebug(.branchActivationSkipped(branch: branchID, scope: scope))
            return true
        }

        let previousBranch = scope.activeBranch
        var didActivate = false
        mutateRouteGraph {
            didActivate = scope.setActiveBranch(branchID)
        }

        if didActivate {
            log.departureDebug(.branchActivated(from: previousBranch, to: branchID, scope: scope))
        } else {
            log.departureDebug(.branchActivationRejected(from: previousBranch, to: branchID, scope: scope))
        }

        return didActivate
    }

    func replaceElevatedTree(
        _ priority: RoutePriority,
        with route: any Route,
        after match: DeclarationMatch
    ) {
        log.departureDebug(.highPriorityReplacePreparing(route: route, match: match))

        let waitsForBranchActivation = waitsForBranchActivation(for: match)

        guard activateBranch(for: match) else {
            if let branchID = match.branchID {
                log.departureDebug(.routeDroppedBranchActivationFailed(branch: branchID))
            }
            return
        }

        appendOrPendRoute(
            route,
            after: match,
            behavior: .startElevatedTree(priority),
            waitsForBranchActivation: waitsForBranchActivation
        )
    }

    func appendOrPendRoute(
        _ route: any Route,
        after match: DeclarationMatch,
        behavior: RouteAppendBehavior,
        waitsForBranchActivation: Bool = false
    ) {
        guard waitsForBranchActivation == false else {
            if let branchID = match.branchID {
                log.departureDebug(.routePendingWaitingForActivatedBranchHost(route: route, branch: branchID))
            }
            replacePendingRoute(PendingRoute(
                route: route,
                state: .append(.init(match: match, behavior: behavior))
            ))
            return
        }

        guard canPresentRoute(after: match) else {
            if let branchID = match.branchID {
                log.departureDebug(.routePendingWaitingForLocalPresentationScope(route: route, branch: branchID))
            }
            replacePendingRoute(PendingRoute(
                route: route,
                state: .append(.init(match: match, behavior: behavior))
            ))
            return
        }

        replacePendingRoute(nil)

        // Resolve the host once, at write time, so the SwiftUI bindings read it directly instead of
        // re-deriving the closest declaring scope on every read. The presenter is not always the
        // declarer: when the route is placed into a different path than the one it was discovered
        // in (a branch adopting a top-level/branch declaration), the branch scope that owns the
        // target path is the presenter. Otherwise the declaring scope within the path hosts it.
        let hostScope = match.path === match.declaringPath
            ? match.path.scope(at: match.position)
            : match.path.owner

        if behavior.startsElevatedTree, hostScope == nil {
            return
        }

        mutateRouteGraph {
            if case .startElevatedTree(let priority) = behavior {
                trimExistingElevatedTreeForReplacement(priority)
                guard let presentationScope = hostScope else {
                    return
                }

                let rootScope = RouteScope(id: UUID(), route: nil)
                let routePath = RoutePath(owner: rootScope)
                let hostDeclaration = drivingDeclaration(for: match, hostedBy: presentationScope)
                let tree = RouteTree(
                    priority: priority,
                    root: rootScope,
                    rootPath: routePath,
                    anchor: .init(routeScope: presentationScope, declaration: hostDeclaration)
                )
                let appendedScope = RouteScope(id: route.id, route: route)
                appendedScope.hostScope = presentationScope
                appendedScope.hostDeclaration = hostDeclaration
                routePath.append(appendedScope)
                routeForest.setElevatedTree(tree, for: priority)
                log.departureDebug(.elevatedTreeStarted)
                return
            }

            let appendedScope = RouteScope(id: route.id, route: route)
            appendedScope.hostScope = hostScope
            appendedScope.hostDeclaration = hostScope.map {
                drivingDeclaration(for: match, hostedBy: $0)
            } ?? match.declaration

            if match.declaration.presentationKind == .push {
                hostScope?.pushChild = appendedScope
            } else {
                hostScope?.modalChild = appendedScope
            }
            match.path.append(appendedScope)
        }
        log.departureDebug(.routeAppended(route: route, pathCount: match.path.count))
    }

    func drivingDeclaration(for match: DeclarationMatch, hostedBy hostScope: RouteScope) -> AnyRouteDeclaration {
        hostScope.routeAttachments.first(where: {
            $0.routeType == match.declaration.routeType
            && $0.presentationKind == match.declaration.presentationKind
            && $0.drivesPresentation
        }) ?? match.declaration
    }

    func resumePendingRoute(for branch: AnyHashable, in declaringScope: RouteScope) {
        log.departureDebug(.pendingResumeCheck(branch: branch, declaringScope: declaringScope))

        guard
            let pendingRoute,
            let append = pendingRoute.append,
            append.match.branchID == branch,
            append.match.declaringPath.scope(at: append.match.declaringPosition) === declaringScope
        else {
            log.departureDebug(.pendingResumeSkipped)
            return
        }

        replacePendingRoute(nil)
        log.departureDebug(.pendingRouteResuming(route: pendingRoute.route))
        let pendingMatch = append.match
        let appendBehavior = append.behavior
        guard let branchID = pendingMatch.branchID else {
            return
        }

        let match = pendingMatch.updatingPresentationPath(
            routeForest.routePath(
                forBranch: branchID,
                under: declaringScope,
                declaration: pendingMatch.declaration
            )
        )
        switch appendBehavior {
        case .append:
            prepareNormalAppendPath(after: match)

        case .startElevatedTree:
            break
        }

        appendOrPendRoute(
            pendingRoute.route,
            after: match,
            behavior: appendBehavior
        )
    }

    func canPresentRoute(after match: DeclarationMatch) -> Bool {
        guard let branchID = match.branchID else {
            log.departureDebug(.routeCanPresentDeclarationDrivesPresentation)
            return true
        }

        guard
            let declaringScope = match.declaringPath.scope(at: match.declaringPosition),
            declaringScope.activeBranch == branchID
        else {
            log.departureDebug(.routeCannotPresentDiscoveryBranchInactive(branch: branchID))
            return false
        }

        let activeLocalScope = declaringScope.activeLocalScope(for: branchID)
        let canPresent = activeLocalScope?.canDrivePresentation(for: match.declaration) == true
        if canPresent {
            log.departureDebug(.routeCanPresentActiveLocalScope(branch: branchID))
        } else {
            log.departureDebug(.routeCannotPresentNoActiveLocalScope(branch: branchID))
        }

        return canPresent
    }

    @discardableResult
    func prepareNormalAppendPath(after match: DeclarationMatch) -> [RouteScope] {
        var removedScopes: [RouteScope] = []

        guard preservesCurrentPath(for: match) == false else {
            return prepareDeclaringPathForAppend(after: match)
        }

        let trimPosition = positionToKeepBeforeAppending(after: match)
        removedScopes.append(contentsOf: match.path.scopesRemovedAfter(trimPosition))
        keepPathThrough(trimPosition, in: match.path)
        removedScopes.append(contentsOf: prepareDeclaringPathForAppend(after: match))
        return removedScopes
    }

    func prepareDeclaringPathForAppend(after match: DeclarationMatch) -> [RouteScope] {
        guard match.path !== match.declaringPath else {
            return []
        }

        let removedScopes = match.declaringPath.scopesRemovedAfter(match.declaringPosition)
        keepPathThrough(match.declaringPosition, in: match.declaringPath)
        return removedScopes
    }

    func keepPathThrough(_ position: RoutePath.Position, in routePath: RoutePath) {
        let removedScopes = routePath.scopesRemovedAfter(position)
        guard removedScopes.isEmpty == false else {
            mutateRouteGraph {
                removeEmptyElevatedTreesIfNeeded(in: routePath)
            }
            log.departureDebug(.pathUnchanged(keepThrough: position))
            return
        }

        mutateRouteGraph {
            releaseHostSlots(for: removedScopes)
            routePath.keepThrough(position)
            removeEmptyElevatedTreesIfNeeded(in: routePath)
        }
        if position == .owner {
            log.departureDebug(.pathCleared(removedCount: removedScopes.count))
        } else {
            log.departureDebug(.pathTrimmed(keepThrough: position, removedCount: removedScopes.count))
        }
    }

    func releaseHostSlots(for routeScopes: [RouteScope]) {
        for removed in routeScopes {
            if removed.hostScope?.pushChild === removed {
                removed.hostScope?.pushChild = nil
            }
            if removed.hostScope?.modalChild === removed {
                removed.hostScope?.modalChild = nil
            }
        }
    }

    func preservesCurrentPath(for match: DeclarationMatch) -> Bool {
        guard match.declaration.presentationKind != .push else {
            return false
        }

        guard let declaringScope = match.declaringPath.scope(at: match.declaringPosition) else {
            return false
        }

        if let branchID = match.branchID, declaringScope.activeBranch != branchID {
            return false
        }

        return firstModalPositionAfterPresentationPoint(for: match) == nil
    }

    func positionToKeepBeforeAppending(after match: DeclarationMatch) -> RoutePath.Position {
        guard match.declaration.presentationKind != .push else {
            return match.position
        }

        guard let modalPosition = firstModalPositionAfterPresentationPoint(for: match),
              let modalScope = match.path.scope(at: modalPosition)
        else {
            return match.position
        }

        return match.path.positionBefore(modalScope) ?? .owner
    }

    func firstModalPositionAfterPresentationPoint(for match: DeclarationMatch) -> RoutePath.Position? {
        guard match.declaration.presentationKind != .push else {
            return nil
        }

        return match.path.firstModalPosition(after: match.position)
    }

    func removeFromPath(_ routeScope: RouteScope) {
        guard
            let routePath = routeForest.routePath(containing: routeScope),
            let positionBeforeRemovedScope = routePath.positionBefore(routeScope)
        else {
            log.departureDebug(.pathRemovalSkipped(scope: routeScope))
            return
        }

        log.departureDebug(.pathRemovalRequested(scope: routeScope))
        keepPathThrough(positionBeforeRemovedScope, in: routePath)
    }

    func trimExistingElevatedTreeForReplacement(_ priority: RoutePriority) {
        guard let tree = routeForest.tree(for: priority) else {
            return
        }

        keepPathThrough(.owner, in: tree.rootPath)
        routeForest.setElevatedTree(nil, for: priority)
    }

    func removeEmptyElevatedTreesIfNeeded(in routePath: RoutePath) {
        for priority in [RoutePriority.critical, .high] {
            guard
                let tree = routeForest.tree(for: priority),
                tree.contains(routePath)
            else {
                continue
            }

            guard tree.rootPath.isEmpty == false else {
                log.departureDebug(.elevatedTreeCleared)
                routeForest.setElevatedTree(nil, for: priority)
                continue
            }
        }
    }

    func routeScopeDidInstallInView(_ routeScope: RouteScope) {
        routeScope.installInView()
        log.departureDebug(.scopeInstalledInView(scope: routeScope))
    }

    func routeScopeDidLeaveView(_ routeScope: RouteScope) {
        guard routeScope.isInstalledInView else { return }

        mutateRouteGraph {
            routeScope.uninstallFromView()
            clearElevatedTreeIfNeeded(forRemovedViewScope: routeScope)
        }
        log.departureDebug(.scopeUninstalledFromView(scope: routeScope))
    }

    func clearElevatedTreeIfNeeded(forRemovedViewScope routeScope: RouteScope) {
        for priority in [RoutePriority.critical, .high]
        where routeForest.tree(for: priority)?.elevatedRouteScope === routeScope {
            log.departureDebug(.elevatedTreeCleared)
            routeForest.setElevatedTree(nil, for: priority)
        }
    }

    func waitForRouteScopesToLeaveView(_ routeScopes: [RouteScope]) async {
        let installedRouteScopes = routeScopes.filter(\.isInstalledInView)

        guard installedRouteScopes.isEmpty == false else {
            log.departureDebug(.viewExitWaitSkipped)
            return
        }

        log.departureDebug(.viewExitWaitStarted(installed: installedRouteScopes.count))
        await withCheckedContinuation { continuation in
            var remainingCount = installedRouteScopes.count

            for routeScope in installedRouteScopes {
                routeScope.onUninstallFromView {
                    remainingCount -= 1
                    log.departureDebug(.viewExitWaitProgress(remaining: remainingCount))

                    if remainingCount == 0 {
                        continuation.resume()
                    }
                }
            }
        }
    }

    func deferRouteAppendIfNeeded(_ route: any Route, after match: DeclarationMatch) async -> Bool {
        guard let pendingAppend = pendingRoute?.append,
              pendingAppend.blockingScopes.isEmpty == false
        else {
            return false
        }

        if pendingAppend.blockingScopes.contains(where: \.isInstalledInView) == false {
            pendingRoute = nil
            return false
        }

        _ = await deferRouteAppend(route, after: match, until: pendingAppend.blockingScopes)
        return true
    }

    func deferRouteAppend(_ route: any Route, after match: DeclarationMatch, until routeScopes: [RouteScope]) async -> Bool {
        let installedRouteScopes = routeScopes.filter(\.isInstalledInView)
        guard installedRouteScopes.isEmpty == false else {
            await waitForRouteScopesToLeaveView(routeScopes)
            return false
        }

        let pendingAppend = PendingRoute(
            route: route,
            state: .append(.init(
                match: match,
                behavior: .append,
                blockingScopes: installedRouteScopes
            ))
        )
        replacePendingRoute(pendingAppend)

        await waitForRouteScopesToLeaveView(installedRouteScopes)

        guard pendingRoute === pendingAppend else {
            log.departureDebug(.routeAppendSuperseded(route: route))
            return true
        }

        pendingRoute = nil
        appendPreparedRoute(route, after: match)
        return true
    }

    func unwindHandlerScope(
        for target: UnwindTarget?,
        in routePath: RoutePath,
        keepThrough position: RoutePath.Position
    ) -> RouteScope? {
        switch target {
        case .nearestBranch:
            // `.nearestBranch` targets the container that owns the branch. An explicit
            // `.id(branchRootID)` is the opt-in path for hooks on the branch root itself.
            return routePath.owner?.parent

        default:
            if position == .owner,
               let tree = routeForest.tree(containing: routePath),
               tree.priority != .normal {
                return tree.anchor?.routeScope
            }

            return routePath.scope(at: position)
        }
    }

    func performPlannedUnwind(
        for sourceScope: RouteScope?,
        payload: Any?,
        in targetScope: RouteScope?,
        plan: RouteForest.UnwindPlan,
        preservesSnapshot: Bool = true,
        logsCompletion: Bool = true
    ) async {
        await performAcceptedUnwind(
            for: sourceScope,
            payload: payload,
            in: targetScope,
            removing: plan.removedScopes,
            logsCompletion: logsCompletion,
            afterScopesLeave: {
                unwindPresentationSnapshot = nil
            }
        ) {
            if preservesSnapshot {
                unwindPresentationSnapshot = UnwindPresentationSnapshot(
                    preservedPaths: plan.preservedPaths.map {
                        UnwindPresentationSnapshot.PreservedRoutePath(
                            routePath: $0.routePath,
                            scopes: $0.scopes
                        )
                    },
                    routeForest: routeForest
                )
            }

            for trim in plan.pathTrims {
                keepPathThrough(trim.keepThrough, in: trim.path)
            }

            if plan.clearsElevatedTrees {
                mutateRouteGraph {
                    routeForest.clearElevatedTrees()
                }
            }
        }
    }

    func performAcceptedUnwind(
        for sourceScope: RouteScope?,
        payload: Any?,
        in targetScope: RouteScope?,
        removing removedScopes: [RouteScope],
        logsCompletion: Bool = true,
        afterScopesLeave: () -> Void = {},
        updatePath: () -> Void
    ) async {
        isNavigationInProgress = true
        await deliverUnwindHandlers(
            for: sourceScope,
            payload: payload,
            in: targetScope,
            removing: removedScopes
        )
        updatePath()
        await waitForRouteScopesToLeaveView(removedScopes)
        afterScopesLeave()
        if logsCompletion {
            log.departureDebug(.unwindCompleted)
        }
        await finishNavigationTransaction()
    }

    func deliverUnwindHandlers(
        for sourceScope: RouteScope?,
        payload: Any?,
        in targetScope: RouteScope?,
        removing removedScopes: [RouteScope]
    ) async {
        guard removedScopes.isEmpty == false else {
            return
        }

        guard let sourceScope, let targetScope else {
            return
        }

        guard let sourceRoute = sourceScope.route,
              let match = targetScope.firstUnwindHandlerMatch(for: type(of: sourceRoute))
        else {
            return
        }

        deliveredUnwindHandlers = deliveredUnwindHandlers.filter { $0.value.sourceScope != nil }

        let key = UnwindHandlerDeliveryKey(
            sourceScopeID: ObjectIdentifier(sourceScope),
            targetScopeID: match.scope.id
        )
        guard deliveredUnwindHandlers[key] == nil else {
            return
        }
        deliveredUnwindHandlers[key] = DeliveredUnwindHandler(sourceScope: sourceScope)

        Task { @MainActor in
            await match.handler.invoke(sourceRoute, payload, match.scope.id)
        }
        await Task.yield()
    }

    func finishNavigationTransaction() async {
        isNavigationInProgress = false
        await drainPendingRouteRequests()
    }

    func drainPendingRouteRequests() async {
        guard let route = pendingRoute,
              case .request = route.state
        else {
            return
        }

        pendingRoute = nil
        await requestRoute(route.route)
        route.resumeRequestIfNeeded()
    }

    func replacePendingRoute(_ pendingRoute: PendingRoute?) {
        self.pendingRoute?.resumeRequestIfNeeded()
        self.pendingRoute = pendingRoute
    }

    func requestRouteWhenReady(_ route: any Route) async {
        guard isNavigationInProgress == false else {
            await withCheckedContinuation { continuation in
                replacePendingRoute(PendingRoute(
                    route: route,
                    state: .request(continuation)
                ))
            }
            return
        }

        await requestRoute(route)
    }

    func performPresentationDismissalUnwind(
        for sourceScope: RouteScope?,
        in targetScope: RouteScope?,
        removing removedScopes: [RouteScope],
        updatePath: () -> Void
    ) {
        if removedScopes.isEmpty == false {
            isNavigationInProgress = true
            Task { @MainActor in
                await deliverUnwindHandlers(
                    for: sourceScope,
                    payload: nil,
                    in: targetScope,
                    removing: removedScopes
                )
                await waitForRouteScopesToLeaveView(removedScopes)
                await finishNavigationTransaction()
            }
        }
        updatePath()
    }
}

private extension RouteScope {
    struct UnwindHandlerMatch {
        let handler: AnyUnwindHandler
        let scope: RouteScope
    }

    func canDrivePresentation(for declaration: AnyRouteDeclaration) -> Bool {
        routeAttachments.contains {
            $0.routeType == declaration.routeType
            && $0.kind == declaration.kind
            && $0.drivesPresentation
        }
    }

    func firstUnwindHandlerMatch(for routeType: any Route.Type) -> UnwindHandlerMatch? {
        var scope: RouteScope? = self

        while let currentScope = scope {
            if let handler = currentScope.firstUnwindHandler(for: routeType) {
                return UnwindHandlerMatch(handler: handler, scope: currentScope)
            }

            scope = currentScope.nextScopeForUnwindHandlerMatch
        }

        return nil
    }

    var nextScopeForUnwindHandlerMatch: RouteScope? {
        if let owningPath,
           let index = owningPath.scopes.firstIndex(where: { $0 === self }) {
            guard index > owningPath.scopes.startIndex else {
                return owningPath.owner
            }

            return owningPath.scopes[owningPath.scopes.index(before: index)]
        }

        return parent
    }

    func firstUnwindHandler(for routeType: any Route.Type) -> AnyUnwindHandler? {
        for attachment in hookAttachments {
            if let handler = attachment.unwindHandler(for: routeType) {
                return handler
            }
        }

        return nil
    }
}
