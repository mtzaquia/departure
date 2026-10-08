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
                operation: beginNavigationOperation(plan: plan)
            )
        }

        // Non-root targets differ only by which path they clear. `.nearestBranch` resolves against
        // the enclosing branch path. Everything else resolves against the current path.
        let routePath: RoutePath
        switch target {
        case .root:
            routePath = defaultSpace.rootPath

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
                operation: beginNavigationOperation(plan: plan)
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
                operation: beginNavigationOperation(plan: plan)
            )
        }
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
            operation: beginNavigationOperation(plan: plan)
        )
    }

    func appendRoute(_ route: any Route, after match: DeclarationMatch, origin: RouteRequestOrigin? = nil) async {
        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        guard navigationSource(origin) != nil, let host = match.presentationHost,
              !host.hasConflictingPresentationHosts, !Task.isCancelled else { return }
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
        let operation = beginNavigationOperation(plan: plan, presentation: .init(route: route, match: match))
        commitNavigationOperation(operation, preservesModalPresentationBindings: false)
        if operation.removedScopes.contains(where: \.isInstalledInView) {
            replacePendingRoute(.presentation(operation))
            await withTaskCancellationHandler {
                await waitForNavigationOperation(operation, releasesAfterModal: true)
                if pendingRoute?.operation === operation {
                    replacePendingRoute(nil)
                    if !Task.isCancelled { appendPreparedRoute(operation) }
                } else if operation.presentation != nil {
                    log.departureDebug(.routeAppendSuperseded(route: route))
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    if self?.pendingRoute?.operation === operation { self?.replacePendingRoute(nil) }
                }
            }
        } else {
            operation.outgoing = [:]
            appendPreparedRoute(operation)
        }
        await finishNavigationOperation(operation)
    }

    func appendPreparedRoute(_ operation: NavigationOperation) {
        guard let presentation = operation.presentation,
              presentation.match.space === spaces.activeSpace else { return }
        let match = presentation.match
        let waitsForBranchActivation = waitsForBranchActivation(for: match)
        guard activateBranch(for: match) else { return }
        appendOrPendRoute(operation, waitsForBranchActivation: waitsForBranchActivation)
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
        guard !Task.isCancelled else { return true }
        let operation = beginNavigationOperation(plan: plan)
        commitNavigationOperation(operation, preservesModalPresentationBindings: false)
        await completeUnwindOperation(operation, logsCompletion: false)
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
        guard isNavigationEligible(scope), !scope.hasConflictingBranchSelection else { return false }
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

    @discardableResult
    func replaceElevatedSpace(
        _ priority: RoutePriority,
        with route: any Route,
        after match: DeclarationMatch,
        origin: RouteRequestOrigin? = nil
    ) async -> RouteSpace? {
        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        guard !Task.isCancelled, navigationSource(origin) != nil else { return nil }
        log.departureDebug(.elevatedPriorityReplacePreparing(route: route))

        // Commit the incoming root before awaiting native teardown: replacement
        // never exposes a temporary lower space or leaves a logical closing root.
        let operation = beginNavigationOperation(plan: spaces.space(for: priority).map {
            spaces.unwindPlan(for: .space($0))
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
        await finishNavigationOperation(operation)
        return space
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
            schedulePendingRouteResume(for: match)
            return
        }

        replacePendingRoute(nil)
        guard let presentationHost = resolvePresentationHost(for: match) else { return }
        let appendedPath = match.presentationLocation.path
        mutateRouteGraph {
            let declaration = presentationHost.declaration
            let scope = RouteScope(id: AnyHashable(route.id),
                route: route, definitions: declaration.childScope ?? .empty)
            scope.attachPresentation(to: presentationHost.scope, declaration: declaration, priority: match.space.priority)
            appendedPath.append(scope)
        }
        log.departureDebug(.routeAppended(route: route, path: appendedPath.departureDebugPathDescription))
        operation.presentation = nil
    }

    func resumePendingRoute(for branch: AnyHashable, in declaringScope: RouteScope) {
        guard let operation = pendingRoute?.operation,
              let presentation = operation.presentation,
              presentation.match.branchID == branch,
              presentation.match.declarationLocation.scope === declaringScope,
              declaringScope.branchScopes[branch] != nil else { return }

        replacePendingRoute(nil)
        guard presentation.match.space === spaces.activeSpace else { return }
        log.departureDebug(.pendingRouteResuming(route: presentation.route))
        prepareRouteAppendPath(after: presentation.match)
        appendOrPendRoute(operation)
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
        operation: NavigationOperation
    ) async -> Bool {
        await deliverUnwindHandlers(for: sourceScope, payload: payload, in: targetScope, removing: operation.removedScopes)
        guard sourceScope.map(isNavigationEligible) ?? true, !Task.isCancelled else {
            await finishNavigationOperation(operation)
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
        await finishNavigationOperation(operation)
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
        let operation = beginNavigationOperation(plan: spaces.unwindPlan(for: .combined(captured.map { .space($0) })))
        for space in captured.sorted(by: { $0.priority > $1.priority }) {
            await deliverUnwindHandlers(for: space.root, payload: payload, in: nil, removing: operation.removedScopes)
        }
        guard !Task.isCancelled, source.map(isNavigationEligible) ?? true else {
            await finishNavigationOperation(operation)
            return false
        }
        commitNavigationOperation(operation)
        await waitForNavigationOperation(operation)
        await finishNavigationOperation(operation)
        return true
    }

    /// Capture outgoing projections before cutting their owning edges in the live tree.
    func commitNavigationOperation(_ operation: NavigationOperation, preservesModalPresentationBindings: Bool = true) {
        guard let plan = operation.plan else { return }
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
                guard pendingRoute?.operation === operation else { return }
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

        var presentations: [PresentationKey: NavigationOperation.Outgoing] = [:]
        for path in plan.preservedPaths {
            for scope in path.scopes {
                guard let host = scope.presentationOrigin, let declaration = scope.presentationDeclaration,
                      shouldHostLocally(declaration, in: path.routePath) else { continue }
                let key = PresentationKey(host, declaration.presentationKind)
                guard presentations[key] == nil else { continue }
                let retainsBinding = containsDepartingModal && departingHostScopeIDs.contains(ObjectIdentifier(host))
                    && (!declaration.presentationKind.isModal || preservesModalPresentationBindings)
                presentations[key] = .init(
                    projection: .init(presentation: .init(scope: scope, declaration: declaration, sourceEnvironment: host.sourceEnvironment),
                        routePath: path.routePath, isLive: false),
                    retainsBinding: retainsBinding,
                    disablesAnimation: unanimatedPushPresentationScopeIDs.contains(ObjectIdentifier(scope)))
            }
        }
        return presentations
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
        let operation = NavigationOperation(plan: plan, presentation: presentation)
        navigationOperations.append(operation)
        return operation
    }

    func finishNavigationOperation(_ operation: NavigationOperation) async {
        guard let index = navigationOperations.firstIndex(where: { $0 === operation }) else { return }
        operation.outgoing = [:]
        operation.plan = nil
        navigationOperations.remove(at: index)
        if !isNavigating { await drainPendingRouteRequests() }
    }

    func outgoingPresentation(for key: PresentationKey) -> NavigationOperation.Outgoing? {
        navigationOperations.reversed().lazy.compactMap { $0.outgoing[key] }.first
    }

    enum RouteRequestStage {
        case resolve
        case presentResolved
    }

    func drainPendingRouteRequests() async {
        guard case let .request(request) = pendingRoute else { return }
        pendingRoute = nil
        // Queued work runs from the completing operation, but cancellation still belongs
        // to its original caller. The request owns that execution until it finishes.
        let execution = Task { @MainActor in
            await requestRouteWhenReady(request.route, stage: request.stage, origin: request.origin)
        }
        request.execution = execution
        let targetSpace = await execution.value
        request.execution = nil
        request.resume(targetSpace)
    }

    func replacePendingRoute(_ pendingRoute: PendingNavigation?) {
        if case let .request(request) = self.pendingRoute { request.resume() }
        self.pendingRoute = pendingRoute
    }

    @discardableResult
    func requestRouteWhenReady(
        _ route: any Route,
        stage: RouteRequestStage = .resolve,
        origin: RouteRequestOrigin? = nil
    ) async -> RouteSpace? {
        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        // A live lower-space handler can request its follow-up before unwind commits.
        // Coverage is evaluated after the global operation completes.
        guard Task.isCancelled == false, resolveRequestOrigin(origin) != nil else { return nil }
        guard isNavigating == false else {
            let request = PendingNavigation.Request(route: route, stage: stage, origin: origin)
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    guard Task.isCancelled == false else {
                        continuation.resume(returning: nil)
                        return
                    }

                    request.continuation = continuation
                    replacePendingRoute(.request(request))
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    request.execution?.cancel()
                    if case let .request(pending) = self?.pendingRoute, pending === request {
                        self?.replacePendingRoute(nil)
                    }
                }
            }
        }

        guard navigationSource(origin) != nil else { return nil }
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
