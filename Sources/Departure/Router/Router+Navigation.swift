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
    struct UnwindHandlerDeliveryKey: Equatable, Hashable {
        let sourceScopeID: ObjectIdentifier
        let targetScopeID: AnyHashable
    }

    struct DeliveredUnwindHandler {
        weak var sourceScope: RouteScope?
        let entry: Task<Void, Never>
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

        let retained: RouteScope
        let handlerScope: RouteScope?
        let plan: RouteSpaces.UnwindPlan
        switch target {
        case nil, .topmostAncestor:
            return await unwindPrevious(from: sourceScope, payload: payload)

        case .root:
            guard let space = sourceScope.space else { return false }
            retained = space.root
            handlerScope = retained
            plan = spaces.rootUnwindPlan(in: space)
            guard !plan.removedScopes.isEmpty else {
                log.departureDebug(.unwindSkippedNoRoute)
                return false
            }

        case .nearestBranch:
            guard let branchRoot = nearestBranchPath(from: sourceScope)?.owner else {
                log.departureDebug(.unwindSkippedNotInsideBranch)
                return false
            }
            retained = branchRoot
            // Branch reset notifies its container. An explicit branch-root ID
            // remains the opt-in target for a handler on the branch root itself.
            handlerScope = branchRoot.parent
            plan = RouteSpaces.UnwindPlan(retaining: [retained])

        case .id(let id):
            let path = spaces.routePath(containing: sourceScope) ?? spaces.activeSpace.currentRoutePath
            if let local = path.scope(withID: id) {
                retained = local
                handlerScope = local
                plan = RouteSpaces.UnwindPlan(retaining: [local])
            } else {
                guard let ancestor = spaces.ancestorUnwindScope(from: path, withID: id),
                      let owner = path.owner else {
                    log.departureDebug(.unwindDroppedTargetNotFound(target: target))
                    return false
                }
                let ancestorPlan = RouteSpaces.UnwindPlan(retaining: [owner, ancestor])
                log.departureDebug(.unwindAcceptedAncestorTarget(
                    keepThrough: ancestor, removing: ancestorPlan.removedScopes.count
                ))
                return await performPlannedUnwind(for: sourceScope, payload: payload, in: ancestor,
                    operation: beginNavigationOperation(plan: ancestorPlan))
            }
        }

        log.departureDebug(.unwindAccepted(keepThrough: retained, removing: plan.removedScopes.count))
        return await performPlannedUnwind(for: sourceScope, payload: payload, in: handlerScope,
            operation: beginNavigationOperation(plan: plan))
    }

    @discardableResult
    func unwindPrevious(from sourceScope: RouteScope, payload: Any? = nil) async -> Bool {
        log.departureDebug(.unwindPreviousRequested)

        guard isNavigationEligible(sourceScope) else { return false }
        if let space = sourceScope.space, sourceScope === space.root {
            return await dismissSpace(space, source: sourceScope, payload: payload)
        }
        guard
            let routePath = spaces.routePath(containing: sourceScope),
            let retained = routePath.scope(before: sourceScope)
        else {
            log.departureDebug(.unwindSkippedNoRoute)
            return false
        }

        let plan = RouteSpaces.UnwindPlan(retaining: [retained])
        guard plan.removedScopes.isEmpty == false else {
            log.departureDebug(.unwindSkippedNoRoute)
            return false
        }

        log.departureDebug(.unwindAccepted(
            keepThrough: retained,
            removing: plan.removedScopes.count
        ))

        return await performPlannedUnwind(
            for: sourceScope,
            payload: payload,
            in: retained,
            operation: beginNavigationOperation(plan: plan)
        )
    }

    func appendRoute(_ route: any Route, after match: ResolvedRouteTarget, origin: RouteRequestOrigin? = nil) async -> RouteScope? {
        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        guard navigationSource(origin) != nil, !match.presentingScope.hasConflictingPresentationHosts,
              !Task.isCancelled else { return nil }
        if await ios17NavigationStackPushWorkaround?.prepareAppend(after: match, in: self) == true {
            return nil
        }

        // Preparation may remove the requesting child. Its captured presentation anchor
        // must remain in the live top space for the accepted navigation to continue.
        guard isNavigationEligible(match.presentingScope), !Task.isCancelled else { return nil }
        if let equivalent = equivalentRouteMatch(to: route, after: match) {
            guard activateBranch(for: match) else { return nil }
            return await reuseEquivalentRoute(route, at: equivalent,
                plan: spaces.presentationUnwindPlan(after: match, retaining: equivalent))
        }

        log.departureDebug(.routeAppendPreparing(route: route, match: match))
        return await commitPresentation(route, after: match, unwinding: spaces.presentationUnwindPlan(after: match))
    }

    private func commitPresentation(
        _ route: any Route,
        after match: ResolvedRouteTarget,
        unwinding plan: RouteSpaces.UnwindPlan
    ) async -> RouteScope? {
        let operation = beginNavigationOperation(plan: plan, presentation: .init(route: route, match: match))
        return await withTaskCancellationHandler {
            commitNavigationOperation(operation, preservesModalPresentationBindings: false)
            if operation.removedScopes.contains(where: \.isInstalledInView) {
                replacePendingRoute(.presentation(operation))
                await waitForNavigationOperation(operation, releasesAfterModal: true)
                if takePendingPresentation(operation) {
                    if !Task.isCancelled { appendPreparedRoute(operation) }
                } else if operation.presentation != nil {
                    log.departureDebug(.routeAppendSuperseded(route: route))
                }
            } else {
                operation.outgoing = [:]
                appendPreparedRoute(operation)
            }
            finishNavigationOperation(operation)
            let destination = await operation.waitForPresentation()
            return !Task.isCancelled ? destination : nil
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPendingPresentation(operation)
            }
        }
    }

    func appendPreparedRoute(_ operation: NavigationOperation) {
        guard let presentation = operation.presentation,
              presentation.match.space === spaces.activeSpace else { operation.discardPresentation(); return }
        let match = presentation.match
        let waitsForBranchActivation = waitsForBranchActivation(for: match)
        guard activateBranch(for: match) else { operation.discardPresentation(); return }
        appendOrPendRoute(operation, waitsForBranchActivation: waitsForBranchActivation)
    }

    func reuseEquivalentRoute(_ route: any Route, at destination: RouteScope, plan: RouteSpaces.UnwindPlan) async -> RouteScope? {
        guard !Task.isCancelled else { return nil }
        if plan.removedScopes.isEmpty {
            if let current = destination.route { log.departureDebug(.routeNoOpEquivalent(route: route, currentRoute: current)) }
        } else {
            let operation = beginNavigationOperation(plan: plan)
            commitNavigationOperation(operation, preservesModalPresentationBindings: false)
            await completeUnwindOperation(operation, logsCompletion: false)
        }
        return isNavigationEligible(destination) && !Task.isCancelled ? destination : nil
    }

    func equivalentRouteMatch(
        to route: any Route,
        after match: ResolvedRouteTarget
    ) -> RouteScope? {
        // Replacement equality belongs to the selected slot, not an equal route
        // that happens to be pushed farther down the same path.
        if match.declaration.presentationKind == .replace {
            guard let presentation = routePresentation(from: match.presentingScope, matching: .replace,
                    hostedBy: match.presentationHostID),
                  presentation.scope.route?._isEqual(to: route) == true,
                  match.presentationPath.contains(presentation.scope)
            else { return nil }
            return presentation.scope
        }
        return equivalentRouteMatch(
            to: route,
            in: match.presentationPath,
            startingAt: match.presentingScope
        )
    }

    func equivalentRouteMatch(
        to route: any Route,
        in routePath: RoutePath,
        startingAt anchor: RouteScope? = nil
    ) -> RouteScope? {
        for scope in routePath.scopes.reversed() {
            if scope.route?._isEqual(to: route) == true {
                return scope
            }

            if anchor === scope {
                return nil
            }
        }

        guard (anchor == nil || anchor === routePath.owner),
              routePath.owner?.route?._isEqual(to: route) == true
        else {
            return nil
        }

        return routePath.owner
    }

    func waitsForBranchActivation(for match: ResolvedRouteTarget) -> Bool {
        guard let branchID = match.branchID else {
            return false
        }
        let owner = match.declaringScope
        if owner.isConcurrent, owner.branchScopes[branchID] != nil { return false }
        return owner.activeBranch != branchID
    }

    func activateBranch(for match: ResolvedRouteTarget) -> Bool {
        guard let branchID = match.branchID else {
            return true
        }

        let scope = match.declaringScope

        return activateBranch(branchID, in: scope)
    }

    func activateBranch(_ branchID: AnyHashable, in scope: RouteScope) -> Bool {
        guard canActivateBranch(branchID, in: scope) else { return false }
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

    func canActivateBranch(_ branchID: AnyHashable, in scope: RouteScope) -> Bool {
        isNavigationEligible(scope) && !scope.hasConflictingBranchSelection
            && (scope.activeBranch == branchID || scope.branchSelection?.acceptsValue(branchID) != false)
    }

    /// Gives an already-mounted branch host a turn to observe the selection update before resuming
    /// the request. A missing host resumes from its registration path instead.
    func schedulePendingRouteResume(_ operation: NavigationOperation) {
        guard
            let match = operation.presentation?.match,
            let branch = match.branchID,
            match.declaringScope.branchScopes[branch] != nil
        else {
            return
        }

        let declaringScope = match.declaringScope
        Task { @MainActor [weak self, weak declaringScope] in
            await Task.yield()

            guard let self, isPendingPresentation(operation) else { return }
            guard let declaringScope, declaringScope.activeBranch == branch,
                  declaringScope.branchScopes[branch] != nil else {
                cancelPendingPresentation(operation)
                return
            }

            resumePendingRoute(for: branch, in: declaringScope)
        }
    }

    @discardableResult
    func replaceElevatedSpace(
        _ priority: RoutePriority,
        with route: any Route,
        after match: ResolvedRouteTarget,
        origin: RouteRequestOrigin? = nil
    ) async -> RouteScope? {
        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        guard !Task.isCancelled, navigationSource(origin) != nil else { return nil }
        log.departureDebug(.elevatedPriorityReplacePreparing(route: route))

        // Commit the incoming root before awaiting native teardown: replacement
        // never exposes a temporary lower space or leaves a logical closing root.
        let operation = beginNavigationOperation(plan: spaces.space(for: priority).map {
            RouteSpaces.UnwindPlan(removing: [$0])
        })
        commitNavigationOperation(operation, preservesModalPresentationBindings: false)
        let scope = RouteScope(id: AnyHashable(route.id),
            route: route, definitions: match.declaration.childScope ?? .empty)
        scope.attachPresentation(to: root, declaration: match.declaration, priority: priority)
        let space = RouteSpace(priority: priority, root: scope)
        mutateRouteGraph {
            spaces.setElevatedSpace(space, for: priority)
        }
        log.departureDebug(.elevatedSpaceStarted)
        await waitForNavigationOperation(operation)
        finishNavigationOperation(operation)
        return isNavigationEligible(scope) && !Task.isCancelled ? scope : nil
    }

    func appendOrPendRoute(_ operation: NavigationOperation, waitsForBranchActivation: Bool = false) {
        guard let presentation = operation.presentation else { return }
        let route = presentation.route
        let match = presentation.match
        guard !waitsForBranchActivation else {
            if let branchID = match.branchID {
                log.departureDebug(.routePendingWaitingForActivatedBranchHost(route: route, branch: branchID))
            }
            replacePendingRoute(.presentation(operation))
            schedulePendingRouteResume(operation)
            return
        }

        replacePendingRoute(nil)
        let space = match.space
        guard space === spaces.activeSpace,
              spaces.routePath(containing: match.presentingScope) != nil,
              !match.presentingScope.hasConflictingPresentationHosts,
              match.presentingScope.routeAttachments.contains(match.declaration) else { operation.discardPresentation(); return }
        let appendedPath = match.presentationPath
        let scope = RouteScope(id: AnyHashable(route.id),
            route: route, definitions: match.declaration.childScope ?? .empty)
        mutateRouteGraph {
            let declaration = match.declaration
            scope.attachPresentation(to: match.presentingScope, declaration: declaration, priority: space.priority)
            appendedPath.append(scope)
        }
        log.departureDebug(.routeAppended(route: route, path: appendedPath.departureDebugPathDescription))
        operation.completePresentation(at: scope)
    }

    func resumePendingRoute(for branch: AnyHashable, in declaringScope: RouteScope) {
        guard let operation = pendingRoute?.operation,
              let presentation = operation.presentation,
              presentation.match.branchID == branch,
              presentation.match.declaringScope === declaringScope,
              declaringScope.branchScopes[branch] != nil else { return }

        guard takePendingPresentation(operation) else { return }
        guard presentation.match.space === spaces.activeSpace else { operation.discardPresentation(); return }
        log.departureDebug(.pendingRouteResuming(route: presentation.route))
        prepareRouteAppendPath(after: presentation.match)
        appendOrPendRoute(operation)
    }

    @discardableResult
    func prepareRouteAppendPath(after match: ResolvedRouteTarget) -> [RouteScope] {
        prepareRouteAppendPath(spaces.presentationUnwindPlan(after: match))
    }

    @discardableResult
    func prepareRouteAppendPath(_ plan: RouteSpaces.UnwindPlan) -> [RouteScope] {
        let removedScopes = plan.removedScopes
        applyUnwindPlan(plan)
        return removedScopes
    }

    func applyUnwindPlan(_ plan: RouteSpaces.UnwindPlan) {
        let effects = plan.retainedScopes.map { scope in
            (scope: scope, removedCount: scope.routePath.scopesRemoved(after: scope).count)
        }

        mutateRouteGraph {
            for effect in effects where effect.removedCount > 0 {
                effect.scope.routePath.keepThrough(effect.scope)
            }

            for space in plan.spacesToRemove where spaces.space(for: space.priority) === space {
                spaces.setElevatedSpace(nil, for: space.priority)
            }
        }

        for effect in effects {
            guard effect.removedCount > 0 else {
                log.departureDebug(.pathUnchanged(keepThrough: effect.scope))
                continue
            }

            if effect.scope === effect.scope.routePath.owner {
                log.departureDebug(.pathCleared(removedCount: effect.removedCount))
            } else {
                log.departureDebug(.pathTrimmed(
                    keepThrough: effect.scope,
                    removedCount: effect.removedCount
                ))
            }
        }
    }

    func removeFromPath(_ routeScope: RouteScope) {
        guard isNavigationEligible(routeScope) else { return }
        guard
            let routePath = spaces.routePath(containing: routeScope),
            let retained = routePath.scope(before: routeScope)
        else {
            log.departureDebug(.pathRemovalSkipped(scope: routeScope))
            return
        }

        log.departureDebug(.pathRemovalRequested(scope: routeScope))
        applyUnwindPlan(RouteSpaces.UnwindPlan(retaining: [retained]))
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
            applyUnwindPlan(RouteSpaces.UnwindPlan(removing: [space]))
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

    @discardableResult
    func performPlannedUnwind(
        for sourceScope: RouteScope?,
        payload: Any?,
        in targetScope: RouteScope?,
        operation: NavigationOperation
    ) async -> Bool {
        await deliverUnwindHandlers(for: sourceScope, payload: payload, in: targetScope, removing: operation.removedScopes)
        guard sourceScope.map(isNavigationEligible) ?? true, !Task.isCancelled else {
            finishNavigationOperation(operation)
            return false
        }
        commitNavigationOperation(operation)
        await completeUnwindOperation(operation, logsCompletion: true)
        return true
    }

    private func completeUnwindOperation(_ operation: NavigationOperation, logsCompletion: Bool) async {
        await waitForNavigationOperation(operation)
        if logsCompletion {
            log.departureDebug(.unwindCompleted(path: spaces.activeSpace.currentRoutePath.departureDebugPathDescription))
        }
        finishNavigationOperation(operation)
    }

    @discardableResult
    func dismissSpace(_ space: RouteSpace, source: RouteScope? = nil, payload: Any? = nil) async -> Bool {
        await dismissSpaces([space], source: source, payload: payload)
    }

    @discardableResult
    func dismissSpaces(_ candidates: [RouteSpace], source: RouteScope? = nil, payload: Any? = nil) async -> Bool {
        let captured = candidates.filter { $0.priority != .default && spaces.space(for: $0.priority) === $0 }
        guard !captured.isEmpty, !Task.isCancelled,
              source.map(isNavigationEligible) ?? true else { return false }
        let operation = beginNavigationOperation(plan: RouteSpaces.UnwindPlan(removing: captured))
        for space in captured.sorted(by: { $0.priority > $1.priority }) {
            await deliverUnwindHandlers(for: space.root, payload: payload, in: nil, removing: operation.removedScopes)
        }
        guard !Task.isCancelled, source.map(isNavigationEligible) ?? true else {
            finishNavigationOperation(operation)
            return false
        }
        commitNavigationOperation(operation)
        await waitForNavigationOperation(operation)
        finishNavigationOperation(operation)
        return true
    }

    /// Capture outgoing projections before cutting their owning edges in the live tree.
    func commitNavigationOperation(_ operation: NavigationOperation, preservesModalPresentationBindings: Bool = true) {
        guard let plan = operation.commit() else { return }
        let outgoing = outgoingPresentations(for: plan, preservesModalPresentationBindings: preservesModalPresentationBindings)
        if outgoing.values.contains(where: { $0.retainsBinding || $0.disablesAnimation }) {
            operation.outgoing = outgoing
        }
        applyUnwindPlan(plan)
    }

    func waitForNavigationOperation(_ operation: NavigationOperation, releasesAfterModal: Bool = false) async {
        defer { operation.outgoing = [:] }
        if releasesAfterModal, !operation.outgoing.isEmpty {
            let modals = operation.removedScopes.filter { $0.isInstalledInView && $0.presentationDeclaration?.presentationKind.isModal == true }
            if !modals.isEmpty {
                await waitForRouteScopesToLeaveView(modals)
                operation.outgoing = [:]
                guard isPendingPresentation(operation) else { return }
            }
        }
        await waitForRouteScopesToLeaveView(operation.removedScopes)
    }

    func outgoingPresentations(
        for plan: RouteSpaces.UnwindPlan,
        preservesModalPresentationBindings: Bool = true
    ) -> [PresentationKey: NavigationOperation.Outgoing] {
        // A departing modal tears down its nested NavigationStack as part of the same
        // transition. Keep that stack bound until the modal has left. For a push-only unwind,
        // every binding clears together, but only the outermost removed push animates so SwiftUI
        // coalesces the path change into one visible pop.
        let removed = Set(plan.removedScopes.map(ObjectIdentifier.init))
        func isDeparting(_ scope: RouteScope?) -> Bool {
            var ancestor = scope
            while let scope = ancestor {
                if removed.contains(ObjectIdentifier(scope)) { return true }
                ancestor = scope.previousScopeInSpace
            }
            return false
        }
        let containsDepartingModal = plan.removedScopes.contains {
            $0.presentationDeclaration?.presentationKind.isModal == true
        }

        var presentations: [PresentationKey: NavigationOperation.Outgoing] = [:]
        for path in plan.preservedPaths {
            let animatesFirstPush = !containsDepartingModal && !isDeparting(path.routePath.owner)
            for scope in path.scopes {
                guard let host = scope.presentationOrigin, let declaration = scope.presentationDeclaration,
                      shouldHostLocally(scope) else { continue }
                let key = PresentationKey(host, declaration.presentationKind)
                guard presentations[key] == nil else { continue }
                let retainsBinding = containsDepartingModal && isDeparting(host)
                    && (!declaration.presentationKind.isModal || preservesModalPresentationBindings)
                presentations[key] = .init(
                    presentation: .init(scope: scope, sourceEnvironment: host.sourceEnvironment),
                    retainsBinding: retainsBinding,
                    disablesAnimation: !containsDepartingModal && declaration.presentationKind == .push
                        && (!animatesFirstPush || scope !== path.scopes.first))
            }
        }
        return presentations
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

        guard let sourceScope else {
            return
        }

        guard let sourceRoute = sourceScope.route,
              let match = unwindHandlerBinding(for: sourceScope, in: targetScope, removing: removedScopes)?.declaration
        else {
            return
        }

        deliveredUnwindHandlers = deliveredUnwindHandlers.filter { $0.value.sourceScope != nil }

        let key = UnwindHandlerDeliveryKey(
            sourceScopeID: ObjectIdentifier(sourceScope),
            targetScopeID: match.scope.id
        )
        if let delivery = deliveredUnwindHandlers[key] {
            await delivery.entry.value
            return
        }

        let entry = Task { @MainActor in
            await withCheckedContinuation { started in
                Task { @MainActor in
                    // The callback enters before the entry task resumes. Every
                    // unwind sharing this delivery waits for that same boundary.
                    started.resume()
                    guard self.spaces.routePath(containing: match.scope) != nil else { return }
                    await match.handler.invoke(sourceRoute, payload, match.scope.id)
                }
            }
        }
        deliveredUnwindHandlers[key] = DeliveredUnwindHandler(sourceScope: sourceScope, entry: entry)
        await entry.value
    }

    private func unwindHandlerBinding(
        for sourceScope: RouteScope?, in targetScope: RouteScope?, removing removedScopes: [RouteScope]
    ) -> DeclarationBinding<RouteScope.UnwindHandlerMatch>? {
        guard let sourceScope, let route = sourceScope.route, let sourceSpace = sourceScope.space,
              spaces.routePath(containing: sourceScope) != nil else { return nil }
        let removed = Set(removedScopes.map(ObjectIdentifier.init))
        if let binding = targetScope?.firstUnwindHandlerBinding(for: type(of: route), in: spaces, excluding: removed) {
            return binding
        }
        // Notification follows the nearest surviving lower space, without
        // changing navigation ancestry or granting that space command authority.
        for space in spaces.allSpaces.reversed()
            where space.priority < sourceSpace.priority && !removed.contains(ObjectIdentifier(space.root)) {
            if let binding = space.currentRouteScope.firstUnwindHandlerBinding(for: type(of: route), in: spaces, excluding: removed) {
                return binding
            }
        }
        return nil
    }

    func beginNavigationOperation(plan: RouteSpaces.UnwindPlan? = nil,
        presentation: NavigationOperation.Presentation? = nil) -> NavigationOperation {
        let operation = NavigationOperation(plan: plan ?? RouteSpaces.UnwindPlan(), presentation: presentation)
        navigationOperations.append(operation)
        return operation
    }

    func finishNavigationOperation(_ operation: NavigationOperation) {
        guard let index = navigationOperations.firstIndex(where: { $0 === operation }) else { return }
        operation.outgoing = [:]
        operation.finishTeardown(awaitingHost: isPendingPresentation(operation))
        navigationOperations.remove(at: index)
        if !isNavigating { pendingRoute?.request?.resume(true) }
    }

    func outgoingPresentation(for key: PresentationKey) -> NavigationOperation.Outgoing? {
        navigationOperations.reversed().lazy.compactMap { $0.outgoing[key] }.first
    }

    enum RouteRequestStage {
        case resolve
        case presentResolved
    }

    private func isPendingPresentation(_ operation: NavigationOperation) -> Bool {
        pendingRoute?.operation === operation
    }

    @discardableResult
    private func takePendingPresentation(_ operation: NavigationOperation) -> Bool {
        guard isPendingPresentation(operation) else { return false }
        pendingRoute = nil
        return true
    }

    private func cancelPendingPresentation(_ operation: NavigationOperation) {
        if takePendingPresentation(operation) { operation.discardPresentation() }
    }

    func replacePendingRoute(_ pendingRoute: PendingNavigation?) {
        self.pendingRoute?.request?.resume()
        if let previous = self.pendingRoute?.operation, previous !== pendingRoute?.operation {
            previous.discardPresentation()
        }
        self.pendingRoute = pendingRoute
    }

    @discardableResult
    func requestRouteWhenReady(
        _ route: any Route,
        stage: RouteRequestStage = .resolve,
        origin: RouteRequestOrigin? = nil
    ) async -> RouteScope? {
        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        // A live lower-space handler can request its follow-up before unwind commits.
        // Coverage is evaluated after the global operation completes.
        guard Task.isCancelled == false, resolveRequestOrigin(origin) != nil else { return nil }
        if isNavigating {
            let request = PendingNavigation.Request(route: route)
            let ready = await withTaskCancellationHandler {
                defer {
                    if pendingRoute?.request === request { pendingRoute = nil }
                }
                repeat {
                    let ready = await withCheckedContinuation { continuation in
                        guard !Task.isCancelled else {
                            continuation.resume(returning: false)
                            return
                        }
                        request.continuation = continuation
                        if pendingRoute?.request !== request { replacePendingRoute(.request(request)) }
                    }
                    // A wake-up does not claim the slot. A newer attempt may win,
                    // or another unwind may start before this caller gets its turn.
                    guard ready, !Task.isCancelled, pendingRoute?.request === request,
                          resolveRequestOrigin(origin) != nil else { return false }
                } while isNavigating
                return true
            } onCancel: {
                Task { @MainActor [weak self] in
                    if self?.pendingRoute?.request === request {
                        self?.replacePendingRoute(nil)
                    }
                }
            }
            guard ready else { return nil }
        }

        guard !Task.isCancelled, navigationSource(origin) != nil else { return nil }
        // A ready caller still occupies the latest slot until it resumes. An
        // eligible new attempt supersedes it even after teardown has finished.
        if pendingRoute?.request != nil { replacePendingRoute(nil) }
        switch stage {
        case .resolve:
            return await requestRoute(route, origin: origin)
        case .presentResolved:
            return await presentResolvedRoute(route, origin: origin)
        }
    }

    func performPresentationDismissalUnwind(for sourceScope: RouteScope?, in targetScope: RouteScope?, plan: RouteSpaces.UnwindPlan) {
        guard !plan.removedScopes.isEmpty else { applyUnwindPlan(plan); return }
        let operation = beginNavigationOperation(plan: plan)
        // Without a callback, native write-back can commit in this call stack.
        // With a callback, use the same before-commit boundary as explicit unwind.
        guard unwindHandlerBinding(for: sourceScope, in: targetScope, removing: operation.removedScopes)?.declaration != nil else {
            commitNavigationOperation(operation)
            Task { @MainActor in await completeUnwindOperation(operation, logsCompletion: false) }
            return
        }
        Task { @MainActor in
            await performPlannedUnwind(for: sourceScope, payload: nil, in: targetScope,
                operation: operation)
        }
    }

}

private extension RouteScope {
    struct UnwindHandlerMatch {
        let handler: AnyUnwindHandler
        let scope: RouteScope
    }

    func firstUnwindHandlerBinding(for routeType: any Route.Type, in spaces: RouteSpaces,
                                  excluding removed: Set<ObjectIdentifier>) -> DeclarationBinding<UnwindHandlerMatch>? {
        guard spaces.routePath(containing: self) != nil else { return nil }
        var scope: RouteScope? = self

        while let currentScope = scope {
            if !removed.contains(ObjectIdentifier(currentScope)),
               let binding = currentScope.hookBinding(for: .unwindHandler(ObjectIdentifier(routeType)), in: spaces) {
                guard let handler = binding.declaration?.unwindHandler(for: routeType) else { return .conflict }
                return .declared(UnwindHandlerMatch(handler: handler, scope: currentScope))
            }

            scope = currentScope.previousScopeInSpace
        }

        return nil
    }

}
