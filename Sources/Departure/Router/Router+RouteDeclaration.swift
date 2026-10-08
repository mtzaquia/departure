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
    // Return the matched space so action retry cannot acquire an unrelated
    // foreground space's authority after resolution or queued work is rejected.
    @discardableResult
    func requestRoute(_ route: some Route, origin: RouteRequestOrigin? = nil) async -> RouteSpace? {
        #if DEBUG
        guard DepartureLogTrace.id != nil else {
            return await DepartureLogTrace.$id.withValue(DepartureLogTrace.nextID(prefix: "r")) {
                await requestRoute(route, origin: origin)
            }
        }
        #endif

        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        log.departureDebug(.routeRequested(route: route))

        let resolvedRoute = await resolveRouteChain(startingWith: route)
        guard let resolvedRoute else { return nil }

        // Resolution can suspend while another command starts an unwind. Re-enter the
        // readiness gate without evaluating the resolved route a second time.
        return await requestRouteWhenReady(resolvedRoute, stage: .presentResolved, origin: origin)
    }

    @discardableResult
    func presentResolvedRoute(_ resolvedRoute: any Route, origin: RouteRequestOrigin? = nil) async -> RouteSpace? {
        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        guard let source = navigationSource(origin), !Task.isCancelled else { return nil }
        switch transitionPlan(for: resolvedRoute, origin: origin) {
        case .noOp(let currentRoute):
            guard activateOrigin(origin) else { return nil }
            log.departureDebug(.routeNoOpEquivalent(route: resolvedRoute, currentRoute: currentRoute))
            return source.space

        case .dropNoDeclaration(let routeType):
            log.departureWarning(.routeDroppedNoDeclaration(routeType: routeType))
            return nil

        case .dropConflictingDeclaration(let routeType):
            log.departureWarning("Route `\(routeType)` was ignored because its declarations conflict.")
            return nil

        case .dropBlockedByElevatedPriority(let match):
            logMatchedRoute(resolvedRoute, to: match)
            log.departureDebug(.routeBlockedByElevatedPriority(route: resolvedRoute))
            return nil

        case .append(let match):
            guard activatePresentationOwner(match) else { return nil }
            logMatchedRoute(resolvedRoute, to: match)
            log.departureDebug(.routeAcceptedAppend(route: resolvedRoute))
            await appendRoute(resolvedRoute, after: match, origin: origin)
            return Task.isCancelled ? nil : match.space

        case .replaceElevatedSpace(let priority, let match):
            logMatchedRoute(resolvedRoute, to: match)
            let existingSpace = spaces.space(for: priority)
            if await unwindToExistingEquivalentRouteInPrioritySpaceIfNeeded(resolvedRoute, priority: priority) {
                return existingSpace
            }

            log.departureDebug(.routeAcceptedReplaceElevatedPriority(route: resolvedRoute))
            return await replaceElevatedSpace(priority, with: resolvedRoute, after: match)
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

    private func transitionPlan(for route: any Route, origin: RouteRequestOrigin? = nil) -> RouteTransitionPlan {
        let routeType = type(of: route)
        log.departureDebug(.routeLookupStarted(
            routeType: routeType,
            activePath: spaces.activeSpace.currentRoutePath.departureDebugPathDescription
        ))
        guard let binding = spaces.firstDeclaration(including: routeType, origin: origin) else {
            return .dropNoDeclaration(routeType: routeType)
        }
        guard let match = binding.declaration else { return .dropConflictingDeclaration(routeType: routeType) }

        if match.declaration.priority == .default, let source = resolveRequestOrigin(origin),
           let currentRoute = source.route, currentRoute._isEqual(to: route),
           let host = match.presentationHost,
           source.attachedPresentationDeclaration(presentedBy: host,
                matching: match.declaration.presentationKind, hostedBy: match.presentationHostID) != nil {
            return .noOp(currentRoute: currentRoute)
        }

        return switch priorityDecision(for: match) {
        case .drop:
            .dropBlockedByElevatedPriority(match: match)

        case .append:
            .append(match: match)

        case .replaceElevatedSpace(let priority):
            .replaceElevatedSpace(priority: priority, match: match)
        }
    }

    private func logMatchedRoute(_ route: any Route, to match: DeclarationMatch) {
        log.departureDebug(.routeMatched(route: route, match: match))
    }
}

extension RouterEngine {
    enum RouteTransitionPlan {
        case noOp(currentRoute: any Route)
        case dropNoDeclaration(routeType: any Route.Type)
        case dropConflictingDeclaration(routeType: any Route.Type)
        case dropBlockedByElevatedPriority(match: DeclarationMatch)
        case append(match: DeclarationMatch)
        case replaceElevatedSpace(priority: RoutePriority, match: DeclarationMatch)
    }

    enum PriorityDecision {
        case append
        case replaceElevatedSpace(RoutePriority)
        case drop
    }

    struct DeclarationMatch {
        enum LookupStrategy: Equatable {
            case currentPath(spacePriority: RoutePriority)
            case ancestorPath(spacePriority: RoutePriority)
            case rootPath(spacePriority: RoutePriority)
            case defaultRootActiveBranchScope
            case defaultRootDeclarations
        }

        struct Location {
            let path: RoutePath
            let position: RoutePath.Position

            var scope: RouteScope? {
                path.scope(at: position)
            }
        }

        let presentationLocation: Location
        let space: RouteSpace
        let declarationLocation: Location
        let branchID: AnyHashable?
        let declaration: AnyRouteDeclaration
        let lookupStrategy: LookupStrategy

        var presentationHost: RouteScope? { presentationLocation.scope }

        var presentationHostID: RoutePresentationHostID? { presentationHost?.presentationHostID }

        init(
            presentationLocation: Location,
            space: RouteSpace,
            declarationLocation: Location,
            branchID: AnyHashable?,
            declaration: AnyRouteDeclaration,
            lookupStrategy: LookupStrategy
        ) {
            self.presentationLocation = presentationLocation
            self.space = space
            self.declarationLocation = declarationLocation
            self.branchID = branchID
            self.declaration = declaration
            self.lookupStrategy = lookupStrategy
        }
    }

    func priorityDecision(for match: DeclarationMatch) -> PriorityDecision {
        if match.declaration.priority == .default {
            return match.space === spaces.activeSpace ? .append : .drop
        }

        guard match.declaration.priority != .default else {
            return spaces.activeSpace.priority == .default ? .append : .drop
        }

        if spaces.activeSpace.priority > match.declaration.priority {
            return .drop
        }

        return .replaceElevatedSpace(match.declaration.priority)
    }

    /// The path owned by the branch nearest to the current position, or `nil` when the current
    /// position is not inside any branch. `.nearestBranch` unwinds clear this path back to its root.
    var nearestBranchPath: RoutePath? { nearestBranchPath(from: currentRouteScope) }

    func nearestBranchPath(from sourceScope: RouteScope) -> RoutePath? {
        var scope: RouteScope? = sourceScope
        while let current = scope {
            if current.branchID != nil {
                return current.path
            }

            scope = current.previousScopeInSpace
        }

        return nil
    }

}

extension RouterEngine.DeclarationMatch {
    init(
        routePath: (path: RoutePath, position: RoutePath.Position),
        space: RouteSpace,
        declaringPath: RoutePath,
        declaringPosition: RoutePath.Position,
        attachment: RouteScope.RouteAttachmentMatch,
        lookupStrategy: LookupStrategy
    ) {
        self.init(
            presentationLocation: .init(path: routePath.path, position: routePath.position),
            space: space,
            declarationLocation: .init(path: declaringPath, position: declaringPosition),
            branchID: attachment.branchID,
            declaration: attachment.declaration,
            lookupStrategy: lookupStrategy
        )
    }


}

extension RouterEngine {
    /// Selects enclosing branches without altering their independent paths.
    func activateOrigin(_ origin: RouteRequestOrigin?) -> Bool {
        guard let origin else { return true }
        guard let source = origin.resolve(in: spaces) else { return false }
        return activateScopeAncestors(source)
    }

    /// A reroute to a common ancestor activates that destination's owner, rather
    /// than revealing the originally requested branch underneath it.
    private func activatePresentationOwner(_ match: DeclarationMatch) -> Bool {
        let source = match.branchID == nil
            ? match.presentationHost ?? match.declarationLocation.scope
            : match.declarationLocation.scope
        guard let source else { return false }
        return activateScopeAncestors(source)
    }

    private func activateScopeAncestors(_ scope: RouteScope) -> Bool {
        var source = scope
        var ancestry: [(RouteScope, AnyHashable)] = []
        while let previous = source.previousScopeInSpace {
            if let branch = source.branchID { ancestry.append((previous, branch)) }
            source = previous
        }
        for (owner, branch) in ancestry.reversed() {
            guard activateBranch(branch, in: owner) else { return false }
        }
        return true
    }
}
