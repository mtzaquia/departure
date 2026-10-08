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

extension RouterEngine {
    final class PendingRoute {
        struct Append {
            let match: DeclarationMatch
            let blockingScopes: [RouteScope]

            init(
                match: DeclarationMatch,
                blockingScopes: [RouteScope] = []
            ) {
                self.match = match
                self.blockingScopes = blockingScopes
            }
        }

        let id: UUID
        let route: any Route
        let state: State
        let origin: RouteRequestOrigin?

        enum State {
            case request(CheckedContinuation<Void, Never>, stage: RouteRequestStage)
            case append(Append)
        }

        init(
            id: UUID = UUID(),
            route: any Route,
            state: State,
            origin: RouteRequestOrigin? = nil
        ) {
            self.id = id
            self.route = route
            self.state = state
            self.origin = origin
        }

        var append: Append? {
            guard case let .append(append) = state else {
                return nil
            }

            return append
        }

        func resumeRequestIfNeeded() {
            guard case let .request(continuation, _) = state else {
                return
            }

            continuation.resume()
        }
    }

    struct UnwindPresentationSnapshot {
        struct Outgoing {
            let host: RouteScope
            let projection: ResolvedRoutePresentation
            let retainsBinding: Bool
            let disablesAnimation: Bool
        }
        let id = UUID()
        let presentations: [PresentationKey: Outgoing]
    }

    struct UnwindHandlerDeliveryKey: Equatable, Hashable {
        let sourceScopeID: ObjectIdentifier
        let targetScopeID: AnyHashable
    }

    struct DeliveredUnwindHandler {
        weak var sourceScope: RouteScope?
    }

    @discardableResult
    func unwindAndWait(to target: UnwindTarget?, payload: Any? = nil, origin: RouteRequestOrigin? = nil) async -> Bool {
        #if DEBUG
        guard DepartureLogTrace.id != nil else {
            return await DepartureLogTrace.$id.withValue(DepartureLogTrace.nextID(prefix: "u")) {
                await unwindAndWait(to: target, payload: payload, origin: origin)
            }
        }
        #endif

        log.departureDebug(.unwindRequested(target: target))
        guard let sourceScope = navigationSource(origin) else { return false }

        switch target {
        case nil, .topmostAncestor:
            return await unwindPrevious(from: sourceScope, payload: payload)
        default: break
        }

        if case .root = target {
            guard let space = sourceScope.space else { return false }
            let plan = spaces.unwindPlan(for: .root(space))
            guard plan.removedScopes.isEmpty == false else {
                log.departureDebug(.unwindSkippedNoRoute)
                return false
            }

            log.departureDebug(.unwindAccepted(
                keepThrough: .owner,
                removing: plan.removedScopes.count
            ))

            return await performPlannedUnwind(
                for: sourceScope,
                payload: payload,
                in: space.root,
                plan: plan
            )
        }

        // Non-root targets differ only by which path they clear. `.nearestBranch` resolves against
        // the enclosing branch path. Everything else resolves against the current path.
        let routePath: RoutePath
        switch target {
        case .root:
            routePath = normalSpace.rootPath

        case .nearestBranch:
            guard let branchPath = nearestBranchPath(from: sourceScope) else {
                // Not inside a branch — there is nothing nearer to unwind to.
                log.departureDebug(.unwindSkippedNotInsideBranch)
                return false
            }
            routePath = branchPath

        case nil, .topmostAncestor, .id:
            routePath = spaces.routePath(containing: sourceScope) ?? spaces.activeSpace.currentRoutePath
        }

        switch routePath.unwindResolution(to: target) {
        case .noRouteToUnwind:
            log.departureDebug(.unwindSkippedNoRoute)
            return false

        case .targetNotFound:
            guard let ancestorResolution = spaces.ancestorUnwindResolution(from: routePath, to: target) else {
                log.departureDebug(.unwindDroppedTargetNotFound(target: target))
                return false
            }

            let plan = spaces.unwindPlan(for: .combined([
                .scoped(routePath: routePath, after: .owner),
                .scoped(routePath: ancestorResolution.path, after: ancestorResolution.position),
            ]))
            log.departureDebug(.unwindAcceptedAncestorTarget(
                keepThrough: ancestorResolution.position,
                removing: plan.removedScopes.count
            ))

            let targetScope = ancestorResolution.path.scope(at: ancestorResolution.position)
            return await performPlannedUnwind(
                for: sourceScope,
                payload: payload,
                in: targetScope,
                plan: plan
            )

        case let .keepPathThrough(targetPosition):
            let plan = spaces.unwindPlan(for: .scoped(routePath: routePath, after: targetPosition))
            log.departureDebug(.unwindAccepted(
                keepThrough: targetPosition,
                removing: plan.removedScopes.count
            ))

            let targetScope = unwindHandlerScope(
                for: target,
                in: routePath,
                keepThrough: targetPosition
            )

            return await performPlannedUnwind(
                for: sourceScope,
                payload: payload,
                in: targetScope,
                plan: plan
            )
        }
    }

    @discardableResult
    func unwindPrevious(from sourceScope: RouteScope, payload: Any? = nil) async -> Bool {
        log.departureDebug(.unwindPreviousRequested)

        guard isNavigationEligible(sourceScope) else { return false }
        if let space = sourceScope.space, sourceScope === space.root {
            return await dismissSpace(space, source: sourceScope)
        }
        guard
            let routePath = spaces.routePath(containing: sourceScope),
            let targetPosition = routePath.positionBefore(sourceScope)
        else {
            log.departureDebug(.unwindSkippedNoRoute)
            return false
        }

        let plan = spaces.unwindPlan(for: .scoped(routePath: routePath, after: targetPosition))
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

        return await performPlannedUnwind(
            for: sourceScope,
            payload: payload,
            in: targetScope,
            plan: plan
        )
    }

    func appendRoute(_ route: any Route, after match: DeclarationMatch, origin: RouteRequestOrigin? = nil) async {
        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        if await deferRouteAppendIfNeeded(route, after: match) {
            return
        }

        guard navigationSource(origin) != nil, let host = match.presentationHost, !Task.isCancelled else { return }
        if await ios17NavigationStackPushWorkaround?.prepareAppend(after: match, in: self) == true {
            return
        }

        // Preparation may remove the requesting child. Its captured presentation anchor
        // must remain in the live top space for the accepted navigation to continue.
        guard isNavigationEligible(host), !Task.isCancelled else { return }
        if await unwindToExistingEquivalentRouteIfNeeded(route, after: match) {
            return
        }

        log.departureDebug(.routeAppendPreparing(route: route, match: match))
        await commitPresentation(route, after: match, unwinding: routeAppendUnwindPlan(after: match))
    }

    private func commitPresentation(
        _ route: any Route,
        after match: DeclarationMatch,
        unwinding plan: RouteSpaces.UnwindPlan
    ) async {
        let token = beginNavigationTransaction()
        let transition = commitTransition(plan, preservesModalPresentationBindings: false)
        if await !deferRouteAppend(route, after: match, until: transition.removedScopes,
            presentationSnapshotID: transition.snapshotID) {
            clearUnwindPresentationSnapshot(id: transition.snapshotID)
            appendPreparedRoute(route, after: match)
        }
        await finishNavigationTransaction(token)
    }

    func appendPreparedRoute(_ route: any Route, after match: DeclarationMatch) {
        guard match.space === spaces.activeSpace else { return }
        let waitsForBranchActivation = waitsForBranchActivation(for: match)
        guard activateBranch(for: match) else { return }
        appendOrPendRoute(route, after: match, waitsForBranchActivation: waitsForBranchActivation)
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

        return await reuseEquivalentRoute(route, in: match.presentationLocation.path,
            through: equivalentRouteMatch,
            plan: spaces.presentationTransitionPlan(after: match, transition: .keepEquivalent(through: equivalentRouteMatch)))
    }

    func unwindToExistingEquivalentRouteInPrioritySpaceIfNeeded(
        _ route: any Route,
        priority: RoutePriority
    ) async -> Bool {
        guard
            let space = spaces.space(for: priority),
            space.root.route?._isEqual(to: route) == true
        else {
            return false
        }

        return await reuseEquivalentRoute(route, in: space.rootPath, through: .owner,
            plan: spaces.unwindPlan(for: .root(space)))
    }

    private func reuseEquivalentRoute(_ route: any Route, in path: RoutePath, through position: RoutePath.Position, plan: RouteSpaces.UnwindPlan) async -> Bool {
        guard !plan.removedScopes.isEmpty else {
            if let current = path.scope(at: position)?.route { log.departureDebug(.routeNoOpEquivalent(route: route, currentRoute: current)) }
            return true
        }
        await performPlannedUnwind(for: plan.removedScopes.last, payload: nil, in: path.scope(at: position), plan: plan,
            preservesModalPresentationBindings: false, logsCompletion: false)
        return true
    }

    func equivalentRouteMatch(
        to route: any Route,
        after match: DeclarationMatch
    ) -> RoutePath.Position? {
        // Replacement equality belongs to the selected slot, not an equal route
        // that happens to be pushed farther down the same path.
        if match.declaration.presentationKind == .replace {
            guard let host = match.presentationHost,
                  let presentation = routePresentation(from: host, matching: .replace,
                    hostedBy: match.presentationHostID),
                  presentation.scope.route?._isEqual(to: route) == true,
                  let position = match.presentationLocation.path.position(of: presentation.scope)
            else { return nil }
            return position
        }
        return equivalentRouteMatch(
            to: route,
            in: match.presentationLocation.path,
            startingAt: match.presentationLocation.position
        )
    }

    func equivalentRouteMatch(
        to route: any Route,
        in routePath: RoutePath,
        startingAt position: RoutePath.Position? = nil
    ) -> RoutePath.Position? {
        for scope in routePath.scopes.reversed() {
            if scope.route?._isEqual(to: route) == true {
                return .scope(scope)
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

        return .owner
    }

    func waitsForBranchActivation(for match: DeclarationMatch) -> Bool {
        guard let branchID = match.branchID else {
            return false
        }
        guard let owner = match.declarationLocation.scope else { return false }
        if owner.isConcurrent, owner.branchScopes[branchID] != nil { return false }
        return owner.activeBranch != branchID
    }

    func activateBranch(for match: DeclarationMatch) -> Bool {
        guard let branchID = match.branchID else {
            return true
        }

        guard let scope = match.declarationLocation.scope else {
            log.departureDebug(.branchActivationFailed(position: match.declarationLocation.position))
            return false
        }

        return activateBranch(branchID, in: scope)
    }

    func activateBranch(_ branchID: AnyHashable, in scope: RouteScope) -> Bool {
        guard isNavigationEligible(scope) else { return false }
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

    func replaceElevatedSpace(
        _ priority: RoutePriority,
        with route: any Route,
        after match: DeclarationMatch
    ) async {
        log.departureDebug(.elevatedPriorityReplacePreparing(route: route))

        // Commit the incoming root before awaiting native teardown: replacement
        // never exposes a temporary lower space or leaves a logical closing root.
        let token = beginNavigationTransaction()
        let transition = spaces.space(for: priority).map {
            commitTransition(spaces.unwindPlan(for: .space($0)), preservesModalPresentationBindings: false)
        }
        mutateRouteGraph {
            let scope = RouteScope(id: match.declaration.scopeID ?? AnyHashable(route.id),
                route: route, definitions: match.declaration.childScope ?? .empty)
            scope.attachPresentation(to: root, declaration: match.declaration, priority: priority)
            spaces.setElevatedSpace(RouteSpace(priority: priority, root: scope), for: priority)
        }
        log.departureDebug(.elevatedSpaceStarted)
        if let transition { await finishTransition(transition) }
        await finishNavigationTransaction(token)
    }

    func appendOrPendRoute(
        _ route: any Route,
        after match: DeclarationMatch,
        waitsForBranchActivation: Bool = false
    ) {
        guard waitsForBranchActivation == false else {
            if let branchID = match.branchID {
                log.departureDebug(.routePendingWaitingForActivatedBranchHost(route: route, branch: branchID))
            }
            replacePendingRoute(PendingRoute(
                route: route,
                state: .append(.init(match: match))
            ))
            schedulePendingRouteResume(for: match)
            return
        }

        guard let presentationHost = resolvePresentationHost(for: match) else {
            replacePendingRoute(nil)
            return
        }

        replacePendingRoute(nil)
        let presentationOrigin = presentationHost.scope
        let presentationDeclaration = presentationHost.declaration

        let appendedPath = match.presentationLocation.path
        mutateRouteGraph {
            let scope = RouteScope(id: presentationDeclaration.scopeID ?? AnyHashable(route.id),
                route: route, definitions: presentationDeclaration.childScope ?? .empty)
            scope.attachPresentation(to: presentationOrigin, declaration: presentationDeclaration, priority: match.space.priority)
            appendedPath.append(scope)
        }
        log.departureDebug(.routeAppended(
            route: route,
            path: appendedPath.departureDebugPathDescription
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

        guard append.match.space === spaces.activeSpace else {
            replacePendingRoute(nil)
            return
        }
        replacePendingRoute(nil)
        log.departureDebug(.pendingRouteResuming(route: pendingRoute.route))
        let match = append.match
        prepareRouteAppendPath(after: match)
        appendOrPendRoute(pendingRoute.route, after: match)
    }

    func resolvePresentationHost(
        for match: DeclarationMatch
    ) -> (scope: RouteScope, declaration: AnyRouteDeclaration)? {
        guard let scope = match.presentationHost,
              spaces.routePath(containing: scope) != nil,
              scope.routeAttachments.contains(match.declaration) else { return nil }
        return (scope, match.declaration)
    }

    @discardableResult
    func prepareRouteAppendPath(after match: DeclarationMatch) -> [RouteScope] {
        prepareRouteAppendPath(routeAppendUnwindPlan(after: match))
    }

    @discardableResult
    func prepareRouteAppendPath(_ plan: RouteSpaces.UnwindPlan) -> [RouteScope] {
        let removedScopes = plan.removedScopes
        applyUnwindPlan(plan)
        return removedScopes
    }

    func applyUnwindPlan(_ plan: RouteSpaces.UnwindPlan) {
        let pathTrimEffects = plan.pathTrims.map { trim in
            (trim: trim, removedCount: trim.removedScopes.count)
        }

        mutateRouteGraph {
            for effect in pathTrimEffects where effect.removedCount > 0 {
                effect.trim.path.keepThrough(effect.trim.keepThrough)
            }

            for space in plan.spacesToRemove where spaces.space(for: space.priority) === space {
                spaces.setElevatedSpace(nil, for: space.priority)
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

    func routeAppendUnwindPlan(after match: DeclarationMatch) -> RouteSpaces.UnwindPlan {
        spaces.presentationTransitionPlan(after: match, transition: .append)
    }

    func removeFromPath(_ routeScope: RouteScope) {
        guard isNavigationEligible(routeScope) else { return }
        guard
            let routePath = spaces.routePath(containing: routeScope),
            let positionBeforeRemovedScope = routePath.positionBefore(routeScope)
        else {
            log.departureDebug(.pathRemovalSkipped(scope: routeScope))
            return
        }

        log.departureDebug(.pathRemovalRequested(scope: routeScope))
        applyUnwindPlan(spaces.unwindPlan(for: .scoped(
            routePath: routePath,
            after: positionBeforeRemovedScope
        )))
    }

    func hostDidAttach(_ scope: RouteScope, view: PlatformView?, id: UUID) {
        let becameReady = scope.attachHost(view, id: id)
        if becameReady {
            log.departureDebug(.scopeInstalledInView(scope: scope))
            ios17NavigationStackPushWorkaround?.routeScopeDidInstall(scope)
        }
        if let branch = scope.branchID, let parent = scope.parent {
            resumePendingRoute(for: branch, in: parent)
        }
    }

    func hostDidDetach(_ scope: RouteScope, id: UUID) {
        guard scope.detachHost(id: id) else { return }
        log.departureDebug(.scopeUninstalledFromView(scope: scope))
        if ios17NavigationStackPushWorkaround?.routeScopeDidLeave(scope, in: self) == true { return }
        clearElevatedSpaceIfNeeded(forRemovedViewScope: scope)
    }

    func clearElevatedSpaceIfNeeded(forRemovedViewScope routeScope: RouteScope) {
        for priority in [RoutePriority.critical, .high] {
            guard
                let space = spaces.space(for: priority),
                space.root === routeScope
            else {
                continue
            }

            log.departureDebug(.elevatedSpaceCleared)
            applyUnwindPlan(spaces.unwindPlan(for: .space(space)))
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
            await routeScope.waitUntilUninstalled()
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
        presentationSnapshotID: UUID? = nil
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
                blockingScopes: installedRouteScopes
            ))
        )
        replacePendingRoute(pendingAppend)

        let transition = AppliedTransition(removedScopes: installedRouteScopes, snapshotID: presentationSnapshotID)
        guard await finishTransition(transition, releasesAfterModal: true, isCurrent: { self.pendingRoute === pendingAppend }) else {
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
            return routePath.scope(at: position)
        }
    }

    @discardableResult
    func performPlannedUnwind(
        for sourceScope: RouteScope?,
        payload: Any?,
        in targetScope: RouteScope?,
        plan: RouteSpaces.UnwindPlan,
        preservesModalPresentationBindings: Bool = true,
        logsCompletion: Bool = true
    ) async -> Bool {
        let token = beginNavigationTransaction()
        await deliverUnwindHandlers(for: sourceScope, payload: payload, in: targetScope, removing: plan.removedScopes)
        guard sourceScope.map(isNavigationEligible) ?? true, !Task.isCancelled else {
            await finishNavigationTransaction(token)
            return false
        }
        let transition = commitTransition(plan, preservesModalPresentationBindings: preservesModalPresentationBindings)
        await finishCoordinatedTransition(transition, token: token, logsCompletion: logsCompletion)
        return true
    }

    @discardableResult
    func dismissSpace(_ space: RouteSpace, source: RouteScope? = nil) async -> Bool {
        await dismissSpaces([space], source: source)
    }

    @discardableResult
    func dismissSpaces(_ candidates: [RouteSpace], source: RouteScope? = nil) async -> Bool {
        let captured = candidates.filter { $0.priority != .normal && spaces.space(for: $0.priority) === $0 }
        guard !captured.isEmpty, !Task.isCancelled,
              source.map(isNavigationEligible) ?? true else { return false }
        let token = beginNavigationTransaction()
        let plan = spaces.unwindPlan(for: .combined(captured.map { .space($0) }))
        let transition = commitTransition(plan)
        await finishCoordinatedTransition(transition, token: token, logsCompletion: false)
        return true
    }

    struct AppliedTransition {
        let removedScopes: [RouteScope]
        let snapshotID: UUID?
    }

    /// Every transition captures outgoing projections before mutating the live paths.
    func commitTransition(_ plan: RouteSpaces.UnwindPlan, preservesModalPresentationBindings: Bool = true) -> AppliedTransition {
        let snapshotID = installUnwindPresentationSnapshot(for: plan, preservesModalPresentationBindings: preservesModalPresentationBindings)
        applyUnwindPlan(plan)
        return AppliedTransition(removedScopes: plan.removedScopes, snapshotID: snapshotID)
    }

    @discardableResult
    func finishTransition(_ transition: AppliedTransition, releasesAfterModal: Bool = false, isCurrent: () -> Bool = { true }) async -> Bool {
        defer { clearUnwindPresentationSnapshot(id: transition.snapshotID) }
        if releasesAfterModal, transition.snapshotID != nil {
            let modals = transition.removedScopes.filter { $0.isInstalledInView && $0.presentationDeclaration?.presentationKind.isModal == true }
            if !modals.isEmpty {
                await waitForRouteScopesToLeaveView(modals)
                clearUnwindPresentationSnapshot(id: transition.snapshotID)
                guard isCurrent() else { return false }
            }
        }
        await waitForRouteScopesToLeaveView(transition.removedScopes)
        return isCurrent()
    }

    private func finishCoordinatedTransition(_ transition: AppliedTransition, token: NavigationTransaction.Token, logsCompletion: Bool) async {
        await finishTransition(transition)
        if logsCompletion {
            log.departureDebug(.unwindCompleted(path: spaces.activeSpace.currentRoutePath.departureDebugPathDescription))
        }
        await finishNavigationTransaction(token)
    }

    func installUnwindPresentationSnapshot(
        for plan: RouteSpaces.UnwindPlan,
        preservesModalPresentationBindings: Bool = true
    ) -> UUID? {
        let snapshot = makeUnwindPresentationSnapshot(
            for: plan,
            preservesModalPresentationBindings: preservesModalPresentationBindings
        )

        guard snapshot.presentations.values.contains(where: { $0.retainsBinding || $0.disablesAnimation })
        else {
            return nil
        }

        unwindPresentationSnapshot = snapshot
        return snapshot.id
    }

    func makeUnwindPresentationSnapshot(
        for plan: RouteSpaces.UnwindPlan,
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

            return presentationKind.isModal
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

        var presentations: [PresentationKey: UnwindPresentationSnapshot.Outgoing] = [:]
        for path in plan.preservedPaths {
            for scope in path.scopes {
                guard let host = scope.presentationOrigin, let declaration = scope.presentationDeclaration,
                      shouldHostLocally(declaration, in: path.routePath) else { continue }
                let key = PresentationKey(host, declaration.presentationKind)
                guard presentations[key] == nil else { continue }
                let retainsBinding = containsDepartingModal && departingHostScopeIDs.contains(ObjectIdentifier(host))
                    && (!declaration.presentationKind.isModal || preservesModalPresentationBindings)
                presentations[key] = .init(host: host,
                    projection: .init(presentation: .init(scope: scope, declaration: declaration, sourceEnvironment: host.sourceEnvironment),
                        routePath: path.routePath, isLive: false),
                    retainsBinding: retainsBinding,
                    disablesAnimation: unanimatedPushPresentationScopeIDs.contains(ObjectIdentifier(scope)))
            }
        }
        return UnwindPresentationSnapshot(presentations: presentations)
    }

    func departingPresentationHostScopeIDs(
        in plan: RouteSpaces.UnwindPlan
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

                hostOrAncestorScope = currentScope.previousScopeInSpace
            }

            return nil
        }

        return Set(departingPresentationHostScopeIDs)
    }

    func outermostPushPresentationScopeIDs(
        in plan: RouteSpaces.UnwindPlan
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

                ancestorScope = currentScope.previousScopeInSpace
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
              let match = targetScope.firstUnwindHandlerMatch(for: type(of: sourceRoute), in: spaces)
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
            guard self.spaces.routePath(containing: match.scope) != nil else { return }
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

    enum RouteRequestStage {
        case resolve
        case presentResolved
    }

    func drainPendingRouteRequests() async {
        guard let route = pendingRoute,
              case let .request(_, stage) = route.state
        else {
            return
        }

        pendingRoute = nil
        await requestRouteWhenReady(route.route, stage: stage, origin: route.origin)
        route.resumeRequestIfNeeded()
    }

    func replacePendingRoute(_ pendingRoute: PendingRoute?) {
        self.pendingRoute?.resumeRequestIfNeeded()
        self.pendingRoute = pendingRoute
    }

    func requestRouteWhenReady(
        _ route: any Route,
        stage: RouteRequestStage = .resolve,
        origin: RouteRequestOrigin? = nil
    ) async {
        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        guard Task.isCancelled == false, navigationSource(origin) != nil else { return }
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
                        state: .request(continuation, stage: stage),
                        origin: origin
                    ))
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelPendingRequest(id: requestID)
                }
            }
            return
        }

        switch stage {
        case .resolve:
            await requestRoute(route, origin: origin)
        case .presentResolved:
            await presentResolvedRoute(route, origin: origin)
        }
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

    func performPresentationDismissalUnwind(for sourceScope: RouteScope?, in targetScope: RouteScope?, plan: RouteSpaces.UnwindPlan) {
        guard !plan.removedScopes.isEmpty else { applyUnwindPlan(plan); return }
        let token = beginNavigationTransaction()
        // Native binding write-back must change live state in this call stack.
        let transition = commitTransition(plan)
        Task { @MainActor in
            await deliverUnwindHandlers(for: sourceScope, payload: nil, in: targetScope, removing: transition.removedScopes)
            await finishCoordinatedTransition(transition, token: token, logsCompletion: false)
        }
    }

}

private extension RouteScope {
    struct UnwindHandlerMatch {
        let handler: AnyUnwindHandler
        let scope: RouteScope
    }

    func firstUnwindHandlerMatch(for routeType: any Route.Type, in spaces: RouteSpaces) -> UnwindHandlerMatch? {
        guard spaces.routePath(containing: self) != nil else { return nil }
        var scope: RouteScope? = self

        while let currentScope = scope {
            if let binding = currentScope.hookBinding(for: .unwindHandler(ObjectIdentifier(routeType)), in: spaces) {
                guard let handler = binding.declaration?.unwindHandler(for: routeType) else { return nil }
                return UnwindHandlerMatch(handler: handler, scope: currentScope)
            }

            scope = currentScope.previousScopeInSpace
        }

        return nil
    }

}
