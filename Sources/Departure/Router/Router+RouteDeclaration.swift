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
    // Preserve the exact reached destination across resolution, native staging
    // and queued work. Action retries must not infer it from the foreground path.
    @discardableResult
    func requestRoute(_ route: some Route, origin: RouteRequestOrigin? = nil) async -> RouteScope? {
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
    func presentResolvedRoute(_ resolvedRoute: any Route, origin: RouteRequestOrigin? = nil) async -> RouteScope? {
        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        guard let source = navigationSource(origin), !Task.isCancelled else { return nil }
        let routeType = type(of: resolvedRoute)
        log.departureDebug(.routeLookupStarted(
            routeType: routeType,
            activePath: spaces.activeSpace.currentRoutePath.departureDebugPathDescription
        ))
        guard let binding = spaces.firstDeclaration(including: routeType, origin: origin) else {
            log.departureWarning(.routeDroppedNoDeclaration(routeType: routeType))
            return nil
        }
        guard let match = binding.declaration else {
            log.departureWarning("Route `\(routeType)` was ignored because its declarations conflict.")
            return nil
        }

        let priority = match.declaration.priority
        if priority == .default, let currentRoute = source.route, currentRoute._isEqual(to: resolvedRoute),
           source.attachedPresentationDeclaration(presentedBy: match.presentingScope,
                matching: match.declaration.presentationKind, hostedBy: match.presentationHostID) != nil {
            guard activateOrigin(origin) else { return nil }
            log.departureDebug(.routeNoOpEquivalent(route: resolvedRoute, currentRoute: currentRoute))
            return source
        }

        guard priority == .default
            ? match.space === spaces.activeSpace
            : priority >= spaces.activeSpace.priority else {
            log.departureDebug(.routeMatched(route: resolvedRoute, match: match))
            log.departureDebug(.routeBlockedByElevatedPriority(route: resolvedRoute))
            return nil
        }

        if priority == .default {
            guard activatePresentationOwner(match) else { return nil }
            log.departureDebug(.routeMatched(route: resolvedRoute, match: match))
            log.departureDebug(.routeAcceptedAppend(route: resolvedRoute))
            return await appendRoute(resolvedRoute, after: match, origin: origin)
        }

        log.departureDebug(.routeMatched(route: resolvedRoute, match: match))
        if let space = spaces.space(for: priority), space.root.route?._isEqual(to: resolvedRoute) == true {
            return await reuseEquivalentRoute(resolvedRoute, at: space.root,
                plan: spaces.rootUnwindPlan(in: space))
        }
        log.departureDebug(.routeAcceptedReplaceElevatedPriority(route: resolvedRoute))
        return await replaceElevatedSpace(priority, with: resolvedRoute, after: match, origin: origin)
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
}

extension RouterEngine {
    struct ResolvedRouteTarget {
        enum LookupStrategy: Equatable {
            case currentPath(spacePriority: RoutePriority)
            case defaultRootActiveBranchScope
            case defaultRootDeclarations
        }

        let space: RouteSpace
        let presentingScope: RouteScope
        let declaringScope: RouteScope
        let declaration: AnyRouteDeclaration
        let lookupStrategy: LookupStrategy

        var branchID: AnyHashable? {
            presentingScope.ancestry.first { $0.branchID != nil && $0.parent === declaringScope }?.branchID
        }
        var presentationPath: RoutePath { presentingScope.routePath }
        var declaringPath: RoutePath { declaringScope.routePath }
        var presentationHostID: RoutePresentationHostID? { presentingScope.presentationHostID }
    }

    /// The path owned by the branch nearest to the current position, or `nil` when the current
    /// position is not inside any branch. `.nearestBranch` unwinds clear this path back to its root.
    var nearestBranchPath: RoutePath? { nearestBranchPath(from: currentRouteScope) }

    func nearestBranchPath(from sourceScope: RouteScope) -> RoutePath? {
        sourceScope.ancestry.first { $0.branchID != nil }?.path
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
    private func activatePresentationOwner(_ match: ResolvedRouteTarget) -> Bool {
        if let branch = match.branchID, !canActivateBranch(branch, in: match.declaringScope) { return false }
        let source = match.branchID == nil
            ? match.presentingScope
            : match.declaringScope
        return activateScopeAncestors(source)
    }

    private func activateScopeAncestors(_ scope: RouteScope) -> Bool {
        let ancestry: [(RouteScope, AnyHashable)] = scope.ancestry.compactMap { source in
            guard let branch = source.branchID, let previous = source.previousScopeInSpace else { return nil }
            return (previous, branch)
        }
        // Validate all bindings before writing any enclosing selection. Keep the
        // final presentation branch's activation at its existing staging boundary.
        guard ancestry.allSatisfy({ canActivateBranch($0.1, in: $0.0) }) else { return false }
        for (owner, branch) in ancestry.reversed() {
            guard activateBranch(branch, in: owner) else { return false }
        }
        return true
    }
}
