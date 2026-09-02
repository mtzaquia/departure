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

        let id: UUID
        let route: any Route
        let state: State

        enum State {
            case request(CheckedContinuation<Void, Never>)
            case append(Append)
        }

        init(
            id: UUID = UUID(),
            route: any Route,
            state: State
        ) {
            self.id = id
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
        let id = UUID()
        let preservedPaths: [RouteForest.PreservedRoutePath]
        let routeForest: RouteForest
        let preservesModalPresentationBindings: Bool
        let preservesPushPresentationBindings: Bool
        let departingPresentationHostScopeIDs: Set<ObjectIdentifier>
        let unanimatedPushPresentationScopeIDs: Set<ObjectIdentifier>

        init(
            preservedPaths: [RouteForest.PreservedRoutePath],
            routeForest: RouteForest,
            preservesModalPresentationBindings: Bool,
            preservesPushPresentationBindings: Bool,
            departingPresentationHostScopeIDs: Set<ObjectIdentifier>,
            unanimatedPushPresentationScopeIDs: Set<ObjectIdentifier>
        ) {
            self.preservedPaths = preservedPaths
            self.routeForest = routeForest
            self.preservesModalPresentationBindings = preservesModalPresentationBindings
            self.preservesPushPresentationBindings = preservesPushPresentationBindings
            self.departingPresentationHostScopeIDs = departingPresentationHostScopeIDs
            self.unanimatedPushPresentationScopeIDs = unanimatedPushPresentationScopeIDs
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

        var elevatedPriority: RoutePriority? {
            if case .startElevatedTree(let priority) = self {
                return priority
            }

            return nil
        }
    }

    @discardableResult
    func unwindAndWait(to target: UnwindTarget?, payload: Any? = nil) async -> Bool {
        #if DEBUG
        guard DepartureLogTrace.id != nil else {
            return await DepartureLogTrace.$id.withValue(DepartureLogTrace.nextID(prefix: "u")) {
                await unwindAndWait(to: target, payload: payload)
            }
        }
        #endif

        log.departureDebug(.unwindRequested(target: target))
        let sourceScope = currentRouteScope

        if case .root = target {
            let plan = routeForest.unwindPlan(for: .root)
            guard plan.removedScopes.isEmpty == false else {
                log.departureDebug(.unwindSkippedNoRoute)
                return false
            }

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
        // the enclosing branch path. Everything else resolves against the current path.
        let routePath: RoutePath
        switch target {
        case .root:
            routePath = normalTree.rootPath

        case .nearestBranch:
            guard let branchPath = nearestBranchPath else {
                // Not inside a branch — there is nothing nearer to unwind to.
                log.departureDebug(.unwindSkippedNotInsideBranch)
                return false
            }
            routePath = branchPath

        case nil, .topmostAncestor, .id:
            routePath = routeForest.activeTree.currentRoutePath
        }

        switch routePath.unwindResolution(to: target) {
        case .noRouteToUnwind:
            log.departureDebug(.unwindSkippedNoRoute)
            return false

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
    func unwindPrevious(from sourceScope: RouteScope, payload: Any? = nil) async -> Bool {
        log.departureDebug(.unwindPreviousRequested)

        guard
            let routePath = routeForest.routePath(containing: sourceScope),
            let targetPosition = routePath.positionBefore(sourceScope)
        else {
            log.departureDebug(.unwindSkippedNoRoute)
            return false
        }

        let plan = routeForest.unwindPlan(for: .scoped(routePath: routePath, after: targetPosition))
        guard plan.removedScopes.isEmpty == false else {
            log.departureDebug(.unwindSkippedNoRoute)
            return false
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
            plan: plan,
            preservesSnapshot: false
        )

        return true
    }

    func appendRoute(_ route: any Route, after match: DeclarationMatch) async {
        // A branch declaration can be discovered before SwiftUI has mounted its host. Do not
        // prepare the append path until that host exists: the fallback path points at the
        // declaring tree and trimming it would remove routes unrelated to the pending request.
        if requiresBranchHostRegistration(for: match) {
            appendPreparedRoute(route, after: match)
            return
        }

        if await deferRouteAppendIfNeeded(route, after: match) {
            return
        }

        if await unwindToExistingEquivalentRouteIfNeeded(route, after: match) {
            return
        }

        log.departureDebug(.routeAppendPreparing(route: route, match: match))
        let unwindPlan = routeAppendUnwindPlan(after: match)
        let snapshotID = installRouteAppendPresentationSnapshot(for: unwindPlan)
        let removedScopes = prepareRouteAppendPath(unwindPlan)

        if removedScopes.isEmpty == false {
            log.departureDebug(.routeAppendWaitingReplacingScopes(removedScopes: removedScopes.count))
            if await deferRouteAppend(
                route,
                after: match,
                until: removedScopes,
                presentationSnapshotID: snapshotID
            ) {
                clearUnwindPresentationSnapshot(id: snapshotID)
                return
            }
        }

        clearUnwindPresentationSnapshot(id: snapshotID)
        appendPreparedRoute(route, after: match)
    }

    func appendPreparedRoute(
        _ route: any Route,
        after match: DeclarationMatch,
        behavior: RouteAppendBehavior = .append
    ) {
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
            behavior: behavior,
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
        let unwindPlan = equivalentRouteUnwindPlan(
            after: match,
            keepingThrough: targetPosition
        )
        let removedScopes = unwindPlan.removedScopes
        let sourceScope = removedScopes.last
        let targetScope = match.presentationLocation.path.scope(at: targetPosition)
        guard removedScopes.isEmpty == false else {
            if let existingRoute = match.presentationLocation.path.scope(at: targetPosition)?.route {
                log.departureDebug(.routeNoOpEquivalent(route: route, currentRoute: existingRoute))
            }
            return true
        }

        let snapshotID = installRouteAppendPresentationSnapshot(for: unwindPlan)
        await performAcceptedUnwind(
            for: sourceScope,
            payload: nil,
            in: targetScope,
            removing: removedScopes,
            logsCompletion: false,
            afterScopesLeave: {
                clearUnwindPresentationSnapshot(id: snapshotID)
            }
        ) {
            applyUnwindPlan(unwindPlan)
        }
        return true
    }

    func equivalentRouteUnwindPlan(
        after match: DeclarationMatch,
        keepingThrough targetPosition: RoutePath.Position
    ) -> RouteForest.UnwindPlan {
        routeForest.presentationTransitionPlan(
            after: match,
            transition: .keepEquivalent(through: targetPosition)
        )
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

        let routePath = tree.currentRoutePath
        let targetPosition = equivalentRouteMatch.position
        let unwindPlan = routeForest.unwindPlan(for: .scoped(
            routePath: routePath,
            after: targetPosition
        ))
        let removedScopes = unwindPlan.removedScopes
        let sourceScope = removedScopes.last
        let targetScope = routePath.scope(at: targetPosition)
        guard removedScopes.isEmpty == false else {
            if let existingRoute = routePath.scope(at: targetPosition)?.route {
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
            applyUnwindPlan(unwindPlan)
        }
        return true
    }

    func equivalentRouteMatch(
        to route: any Route,
        after match: DeclarationMatch
    ) -> EquivalentRouteMatch? {
        equivalentRouteMatch(
            to: route,
            in: match.presentationLocation.path,
            startingAt: match.presentationLocation.position
        )
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

        return match.declarationLocation.scope?.activeBranch != branchID
    }

    func requiresBranchHostRegistration(for match: DeclarationMatch) -> Bool {
        guard
            let branchID = match.branchID,
            let declaringScope = match.declarationLocation.scope
        else {
            return false
        }

        return declaringScope.branchScopes[branchID] == nil
    }

    func activateBranch(for match: DeclarationMatch) -> Bool {
        guard let branchID = match.branchID else {
            return true
        }

        guard let scope = match.declarationLocation.scope else {
            log.departureDebug(.branchActivationFailed(position: match.declarationLocation.position))
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

    /// Gives an already-mounted branch host a turn to observe the selection update before resuming
    /// the request. A missing host resumes from its registration path instead.
    func schedulePendingRouteResume(for match: DeclarationMatch) {
        guard
            let branch = match.branchID,
            let declaringScope = match.declarationLocation.scope,
            declaringScope.branchScopes[branch] != nil
        else {
            return
        }

        Task { @MainActor [weak self, weak declaringScope] in
            await Task.yield()

            guard let self, let declaringScope, declaringScope.activeBranch == branch else {
                return
            }

            resumePendingRoute(for: branch, in: declaringScope)
        }
    }

    func replaceElevatedTree(
        _ priority: RoutePriority,
        with route: any Route,
        after match: DeclarationMatch
    ) async {
        log.departureDebug(.elevatedPriorityReplacePreparing(route: route))

        if let existingTree = routeForest.tree(for: priority) {
            let unwindPlan = routeForest.unwindPlan(for: .tree(existingTree))
            let snapshotID = installRouteAppendPresentationSnapshot(for: unwindPlan)
            let removedScopes = prepareRouteAppendPath(unwindPlan)

            if removedScopes.isEmpty == false,
               await deferRouteAppend(
                route,
                after: match,
                until: removedScopes,
                presentationSnapshotID: snapshotID,
                behavior: .startElevatedTree(priority)
               ) {
                clearUnwindPresentationSnapshot(id: snapshotID)
                return
            }

            clearUnwindPresentationSnapshot(id: snapshotID)
        }

        appendPreparedRoute(
            route,
            after: match,
            behavior: .startElevatedTree(priority)
        )
    }

    func appendOrPendRoute(
        _ route: any Route,
        after match: DeclarationMatch,
        behavior: RouteAppendBehavior,
        waitsForBranchActivation: Bool = false
    ) {
        let match = routeForest.refreshingPresentationLocation(for: match)

        guard waitsForBranchActivation == false else {
            if let branchID = match.branchID {
                log.departureDebug(.routePendingWaitingForActivatedBranchHost(route: route, branch: branchID))
            }
            replacePendingRoute(PendingRoute(
                route: route,
                state: .append(.init(match: match, behavior: behavior))
            ))
            schedulePendingRouteResume(for: match)
            return
        }

        guard let presentationHost = resolvePresentationHost(for: match) else {
            if let branchID = match.branchID {
                log.departureDebug(.routePendingWaitingForLocalPresentationScope(route: route, branch: branchID))
                replacePendingRoute(PendingRoute(
                    route: route,
                    state: .append(.init(match: match, behavior: behavior))
                ))
            }
            return
        }

        replacePendingRoute(nil)
        let presentationOrigin = presentationHost.scope
        let presentationDeclaration = presentationHost.declaration

        var appendedPath: RoutePath?
        mutateRouteGraph {
            if case .startElevatedTree(let priority) = behavior {
                let rootScope = RouteScope(id: UUID(), route: nil)
                let routePath = RoutePath(owner: rootScope)
                let tree = RouteTree(
                    priority: priority,
                    root: rootScope,
                    rootPath: routePath,
                    elevatedOrigin: .init(
                        scope: presentationOrigin,
                        declaration: presentationDeclaration,
                        sourceEnvironment: presentationOrigin.sourceEnvironmentReference
                    )
                )
                let appendedScope = RouteScope(id: route.id, route: route)
                appendedScope.attachPresentation(
                    to: presentationOrigin,
                    declaration: presentationDeclaration
                )
                routePath.append(appendedScope)
                routeForest.setElevatedTree(tree, for: priority)
                appendedPath = routePath
                log.departureDebug(.elevatedTreeStarted)
                return
            }

            let appendedScope = RouteScope(id: route.id, route: route)
            appendedScope.attachPresentation(
                to: presentationOrigin,
                declaration: presentationDeclaration
            )

            match.presentationLocation.path.append(appendedScope)
            appendedPath = match.presentationLocation.path
        }
        log.departureDebug(.routeAppended(
            route: route,
            path: appendedPath?.departureDebugPathDescription ?? "root"
        ))
    }

    func resumePendingRoute(for branch: AnyHashable, in declaringScope: RouteScope) {
        guard
            let pendingRoute,
            let append = pendingRoute.append,
            append.match.branchID == branch,
            append.match.declarationLocation.scope === declaringScope,
            declaringScope.branchScopes[branch] != nil
        else {
            return
        }

        replacePendingRoute(nil)
        log.departureDebug(.pendingRouteResuming(route: pendingRoute.route))
        let pendingMatch = append.match
        let appendBehavior = append.behavior
        let match = routeForest.refreshingPresentationLocation(for: pendingMatch)
        switch appendBehavior {
        case .append:
            prepareRouteAppendPath(after: match)

        case .startElevatedTree:
            break
        }

        appendOrPendRoute(
            pendingRoute.route,
            after: match,
            behavior: appendBehavior
        )
    }

    func resolvePresentationHost(
        for match: DeclarationMatch
    ) -> (scope: RouteScope, declaration: AnyRouteDeclaration)? {
        let resolution = match.presentationHost.flatMap { scope in
            scope.drivingPresentationDeclaration(
                matching: match.declaration,
                hostedBy: match.presentationHostID
            ).map { (scope, $0) }
        }
        guard let branchID = match.branchID else {
            if resolution != nil {
                log.departureDebug(.routeCanPresentDeclarationDrivesPresentation)
            }
            return resolution
        }

        if resolution != nil {
            log.departureDebug(.routeCanPresentActiveLocalScope(branch: branchID))
        } else if match.declarationLocation.scope?.activeBranch != branchID {
            log.departureDebug(.routeCannotPresentDiscoveryBranchInactive(branch: branchID))
        } else {
            log.departureDebug(.routeCannotPresentNoActiveLocalScope(branch: branchID))
        }

        return resolution
    }

    @discardableResult
    func prepareRouteAppendPath(after match: DeclarationMatch) -> [RouteScope] {
        prepareRouteAppendPath(routeAppendUnwindPlan(after: match))
    }

    @discardableResult
    func prepareRouteAppendPath(_ plan: RouteForest.UnwindPlan) -> [RouteScope] {
        let removedScopes = plan.removedScopes
        applyUnwindPlan(plan)
        return removedScopes
    }

    func applyUnwindPlan(_ plan: RouteForest.UnwindPlan) {
        let pathTrimEffects = plan.pathTrims.map { trim in
            (trim: trim, removedCount: trim.removedScopes.count)
        }

        mutateRouteGraph {
            for effect in pathTrimEffects where effect.removedCount > 0 {
                effect.trim.path.keepThrough(effect.trim.keepThrough)
            }

            for priority in plan.elevatedTreePrioritiesToClear {
                routeForest.setElevatedTree(nil, for: priority)
            }
        }

        for effect in pathTrimEffects {
            guard effect.removedCount > 0 else {
                log.departureDebug(.pathUnchanged(keepThrough: effect.trim.keepThrough))
                continue
            }

            if effect.trim.keepThrough == .owner {
                log.departureDebug(.pathCleared(removedCount: effect.removedCount))
            } else {
                log.departureDebug(.pathTrimmed(
                    keepThrough: effect.trim.keepThrough,
                    removedCount: effect.removedCount
                ))
            }
        }
    }

    func routeAppendUnwindPlan(after match: DeclarationMatch) -> RouteForest.UnwindPlan {
        routeForest.presentationTransitionPlan(after: match, transition: .append)
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
        applyUnwindPlan(routeForest.unwindPlan(for: .scoped(
            routePath: routePath,
            after: positionBeforeRemovedScope
        )))
    }

    func routeScopeDidInstallInView(_ routeScope: RouteScope) {
        let wasInstalled = routeScope.isInstalledInView
        routeScope.viewLifecycle.install()
        log.departureDebug(.scopeInstalledInView(scope: routeScope))

        guard wasInstalled == false else {
            return
        }

        ios17NavigationStackPushWorkaround?.routeScopeDidInstall(routeScope)
    }

    func routeScopeDidLeaveView(_ routeScope: RouteScope) {
        guard routeScope.isInstalledInView else { return }

        routeScope.viewLifecycle.uninstall()
        log.departureDebug(.scopeUninstalledFromView(scope: routeScope))

        if ios17NavigationStackPushWorkaround?.routeScopeDidLeave(routeScope, in: self) == true {
            return
        }

        clearElevatedTreeIfNeeded(forRemovedViewScope: routeScope)
    }

    func clearElevatedTreeIfNeeded(forRemovedViewScope routeScope: RouteScope) {
        for priority in [RoutePriority.critical, .high] {
            guard
                let tree = routeForest.tree(for: priority),
                tree.elevatedRouteScope === routeScope
            else {
                continue
            }

            log.departureDebug(.elevatedTreeCleared)
            applyUnwindPlan(routeForest.unwindPlan(for: .tree(tree)))
        }
    }

    func waitForRouteScopesToLeaveView(_ routeScopes: [RouteScope]) async {
        let installedRouteScopes = routeScopes.filter(\.isInstalledInView)

        guard installedRouteScopes.isEmpty == false else {
            log.departureDebug(.viewExitWaitSkipped)
            return
        }

        log.departureDebug(.viewExitWaitStarted(installed: installedRouteScopes.count))
        ios17NavigationStackPushWorkaround?.startViewExitWatchdogs(
            for: installedRouteScopes,
            in: self
        )

        for (index, routeScope) in installedRouteScopes.enumerated() {
            await routeScope.viewLifecycle.waitUntilUninstalled()
            log.departureDebug(.viewExitWaitProgress(
                remaining: installedRouteScopes.count - index - 1
            ))
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

    func deferRouteAppend(
        _ route: any Route,
        after match: DeclarationMatch,
        until routeScopes: [RouteScope],
        presentationSnapshotID: UUID? = nil,
        behavior: RouteAppendBehavior = .append
    ) async -> Bool {
        let installedRouteScopes = routeScopes.filter(\.isInstalledInView)
        guard installedRouteScopes.isEmpty == false else {
            await waitForRouteScopesToLeaveView(routeScopes)
            return false
        }

        let pendingAppend = PendingRoute(
            route: route,
            state: .append(.init(
                match: match,
                behavior: behavior,
                blockingScopes: installedRouteScopes
            ))
        )
        replacePendingRoute(pendingAppend)

        if let presentationSnapshotID {
            // The snapshot keeps pushes stable while their enclosing modal dismisses. Release it
            // as soon as every removed modal has left; otherwise a removed push is kept alive by
            // the same snapshot this append is waiting for it to invalidate.
            let installedModalScopes = installedRouteScopes.filter {
                guard let presentationKind = $0.presentationDeclaration?.presentationKind else {
                    return false
                }

                return presentationKind != .push
            }

            if installedModalScopes.isEmpty == false {
                await waitForRouteScopesToLeaveView(installedModalScopes)
                clearUnwindPresentationSnapshot(id: presentationSnapshotID)

                guard pendingRoute === pendingAppend else {
                    log.departureDebug(.routeAppendSuperseded(route: route))
                    return true
                }
            }
        }

        await waitForRouteScopesToLeaveView(installedRouteScopes)

        guard pendingRoute === pendingAppend else {
            log.departureDebug(.routeAppendSuperseded(route: route))
            return true
        }

        pendingRoute = nil
        appendPreparedRoute(route, after: match, behavior: behavior)
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
                return tree.elevatedOrigin?.scope
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
        var snapshotID: UUID?
        await performAcceptedUnwind(
            for: sourceScope,
            payload: payload,
            in: targetScope,
            removing: plan.removedScopes,
            logsCompletion: logsCompletion,
            afterScopesLeave: {
                clearUnwindPresentationSnapshot(id: snapshotID)
            }
        ) {
            if preservesSnapshot {
                let snapshot = makeUnwindPresentationSnapshot(for: plan)
                unwindPresentationSnapshot = snapshot
                snapshotID = snapshot.id
            }

            applyUnwindPlan(plan)
        }
    }

    func installRouteAppendPresentationSnapshot(for plan: RouteForest.UnwindPlan) -> UUID? {
        let snapshot = makeUnwindPresentationSnapshot(
            for: plan,
            preservesModalPresentationBindings: false
        )

        guard snapshot.preservesPushPresentationBindings
            || snapshot.unanimatedPushPresentationScopeIDs.isEmpty == false
        else {
            return nil
        }

        unwindPresentationSnapshot = snapshot
        return snapshot.id
    }

    func makeUnwindPresentationSnapshot(
        for plan: RouteForest.UnwindPlan,
        preservesModalPresentationBindings: Bool = true
    ) -> UnwindPresentationSnapshot {
        // A departing modal tears down its nested NavigationStack as part of the same
        // transition. Keep that stack bound until the modal has left. For a push-only unwind,
        // every binding clears together, but only the outermost removed push animates so SwiftUI
        // coalesces the path change into one visible pop.
        let containsDepartingModal = plan.removedScopes.contains {
            guard let presentationKind = $0.presentationDeclaration?.presentationKind else {
                return false
            }

            return presentationKind != .push
        }
        let animatedPushPresentationScopeIDs = containsDepartingModal
            ? []
            : outermostPushPresentationScopeIDs(in: plan)
        let removedPushPresentationScopeIDs = Set(plan.removedScopes.compactMap { routeScope in
            routeScope.presentationDeclaration?.presentationKind == .push
                ? ObjectIdentifier(routeScope)
                : nil
        })
        let departingHostScopeIDs = departingPresentationHostScopeIDs(in: plan)
        let unanimatedPushPresentationScopeIDs = containsDepartingModal
            ? []
            : removedPushPresentationScopeIDs.subtracting(animatedPushPresentationScopeIDs)

        return UnwindPresentationSnapshot(
            preservedPaths: plan.preservedPaths,
            routeForest: routeForest,
            preservesModalPresentationBindings: preservesModalPresentationBindings,
            preservesPushPresentationBindings: containsDepartingModal,
            departingPresentationHostScopeIDs: departingHostScopeIDs,
            unanimatedPushPresentationScopeIDs: unanimatedPushPresentationScopeIDs
        )
    }

    func departingPresentationHostScopeIDs(
        in plan: RouteForest.UnwindPlan
    ) -> Set<ObjectIdentifier> {
        let removedScopeIDs = Set(plan.removedScopes.map(ObjectIdentifier.init))
        let departingPresentationHostScopeIDs = plan.removedScopes.compactMap { removedScope -> ObjectIdentifier? in
            guard let host = removedScope.presentationOrigin else {
                return nil
            }

            var hostOrAncestorScope: RouteScope? = host
            while let currentScope = hostOrAncestorScope {
                if removedScopeIDs.contains(ObjectIdentifier(currentScope)) {
                    return ObjectIdentifier(host)
                }

                hostOrAncestorScope = currentScope.previousScopeInTree
            }

            return nil
        }

        return Set(departingPresentationHostScopeIDs)
    }

    func outermostPushPresentationScopeIDs(
        in plan: RouteForest.UnwindPlan
    ) -> Set<ObjectIdentifier> {
        let removedScopeIDs = Set(plan.removedScopes.map(ObjectIdentifier.init))

        return Set(plan.preservedPaths.compactMap { preservedPath in
            guard
                let firstRemovedScope = preservedPath.scopes.first,
                firstRemovedScope.presentationDeclaration?.presentationKind == .push
            else {
                return nil
            }

            var ancestorScope = preservedPath.routePath.owner
            while let currentScope = ancestorScope {
                if removedScopeIDs.contains(ObjectIdentifier(currentScope)) {
                    return nil
                }

                ancestorScope = currentScope.previousScopeInTree
            }

            return ObjectIdentifier(firstRemovedScope)
        })
    }

    func clearUnwindPresentationSnapshot(id: UUID?) {
        guard unwindPresentationSnapshot?.id == id else {
            return
        }

        unwindPresentationSnapshot = nil
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
        let transaction = beginNavigationTransaction()
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
            log.departureDebug(.unwindCompleted(
                path: routeForest.activeTree.currentRoutePath.departureDebugPathDescription
            ))
        }
        await finishNavigationTransaction(transaction)
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

    func beginNavigationTransaction() -> NavigationTransaction.Token {
        navigationTransaction.begin()
    }

    func finishNavigationTransaction(_ token: NavigationTransaction.Token) async {
        guard navigationTransaction.finish(token) else {
            return
        }

        guard navigationTransaction.isInProgress == false else {
            return
        }

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
        guard navigationTransaction.isInProgress == false else {
            let requestID = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    guard Task.isCancelled == false else {
                        continuation.resume()
                        return
                    }

                    replacePendingRoute(PendingRoute(
                        id: requestID,
                        route: route,
                        state: .request(continuation)
                    ))
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelPendingRequest(id: requestID)
                }
            }
            return
        }

        await requestRoute(route)
    }

    func cancelPendingRequest(id: UUID) {
        guard let pendingRoute,
              pendingRoute.id == id,
              case .request = pendingRoute.state
        else {
            return
        }

        replacePendingRoute(nil)
    }

    func performPresentationDismissalUnwind(
        for sourceScope: RouteScope?,
        in targetScope: RouteScope?,
        removing removedScopes: [RouteScope],
        updatePath: () -> Void
    ) {
        if removedScopes.isEmpty == false {
            let transaction = beginNavigationTransaction()
            Task { @MainActor in
                await deliverUnwindHandlers(
                    for: sourceScope,
                    payload: nil,
                    in: targetScope,
                    removing: removedScopes
                )
                await waitForRouteScopesToLeaveView(removedScopes)
                await finishNavigationTransaction(transaction)
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

    func firstUnwindHandlerMatch(for routeType: any Route.Type) -> UnwindHandlerMatch? {
        var scope: RouteScope? = self

        while let currentScope = scope {
            if let handler = currentScope.firstUnwindHandler(for: routeType) {
                return UnwindHandlerMatch(handler: handler, scope: currentScope)
            }

            scope = currentScope.previousScopeInTree
        }

        return nil
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
