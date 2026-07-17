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

protocol IOS17NavigationStackPushWorkaroundHandling: AnyObject {
    func interceptDismissal(
        of presentation: RoutePresentation,
        matching presentationKind: RoutePresentationKind,
        in router: Router
    ) -> Bool
    func routeGraphDidMutate(in router: Router)
    func routeScopeDidInstall(_ routeScope: RouteScope)
    func routeScopeDidLeave(_ routeScope: RouteScope, in router: Router) -> Bool
    func startViewExitWatchdogs(for routeScopes: [RouteScope], in router: Router)
}

enum IOS17NavigationStackPushWorkaroundFactory {
    static func makeForCurrentPlatform() -> (any IOS17NavigationStackPushWorkaroundHandling)? {
#if os(iOS)
        if #unavailable(iOS 18) {
            return IOS17NavigationStackPushWorkaround()
        }
#endif
        return nil
    }
}

/// Reconciles erratic `NavigationStack` push binding write-backs on iOS 17.
///
/// The concrete workaround is unavailable from iOS 18 onward. Keep its engine touchpoints routed
/// through ``IOS17NavigationStackPushWorkaroundHandling`` so this file and those hooks can be
/// removed together when Departure no longer supports iOS 17.
@available(iOS, introduced: 17, obsoleted: 18, message: "Remove the iOS 17 NavigationStack push workaround")
final class IOS17NavigationStackPushWorkaround: IOS17NavigationStackPushWorkaroundHandling {
    struct PendingDismissal {
        let id = UUID()
        let scope: RouteScope
        let routePath: RoutePath
        let targetPosition: RoutePath.Position
        let unwindPlan: RouteForest.UnwindPlan
        let presentationOriginID: ObjectIdentifier?
    }

    var viewExitTimeout: Duration = .seconds(2)

    private var pendingDismissals: [ObjectIdentifier: PendingDismissal] = [:]
    private var viewExitWatchdogs: [ObjectIdentifier: Task<Void, Never>] = [:]

    func interceptDismissal(
        of presentation: RoutePresentation,
        matching presentationKind: RoutePresentationKind,
        in router: Router
    ) -> Bool {
        guard presentationKind == .push, presentation.scope.isInstalledInView else {
            return false
        }

        guard let dismissal = makePendingDismissal(for: presentation.scope, in: router) else {
            log.departureDebug(.ios17PushDismissalDropped(scope: presentation.scope))
            return true
        }

        pendingDismissals[ObjectIdentifier(presentation.scope)] = dismissal
        log.departureDebug(.ios17PushDismissalDeferred(scope: presentation.scope))
        return true
    }

    func routeGraphDidMutate(in router: Router) {
        reconcilePendingDismissals(in: router)
    }

    func routeScopeDidInstall(_ routeScope: RouteScope) {
        let scopeID = ObjectIdentifier(routeScope)
        guard let dismissal = pendingDismissals[scopeID] else {
            return
        }

        invalidate(dismissal)
    }

    func routeScopeDidLeave(_ routeScope: RouteScope, in router: Router) -> Bool {
        cancelViewExitWatchdog(for: routeScope)
        reconcilePendingDismissals(in: router)

        let scopeID = ObjectIdentifier(routeScope)
        guard let dismissal = pendingDismissals[scopeID] else {
            return false
        }

        Task { @MainActor [weak self, weak router, weak routeScope] in
            // SwiftUI delivers dismantle callbacks while holding observation accesses. Defer route
            // mutations out of that stack, and let same-update-cycle reinstallations cancel a
            // spurious push dismissal before changing the path.
            await Task.yield()
            guard let self, let router, let routeScope else {
                return
            }

            guard pendingDismissals[scopeID]?.id == dismissal.id else {
                return
            }

            guard routeScope.isInstalledInView == false else {
                return
            }

            guard isValid(dismissal, in: router) else {
                invalidate(dismissal)
                return
            }

            pendingDismissals[scopeID] = nil
            log.departureDebug(.ios17PushDismissalResumed(scope: routeScope))
            complete(dismissal, in: router)
        }
        return true
    }

    func startViewExitWatchdogs(for routeScopes: [RouteScope], in router: Router) {
        for routeScope in routeScopes {
            let scopeID = ObjectIdentifier(routeScope)
            guard viewExitWatchdogs[scopeID] == nil else {
                continue
            }

            viewExitWatchdogs[scopeID] = Task { @MainActor [weak self, weak router, weak routeScope] in
                do {
                    try await Task.sleep(for: self?.viewExitTimeout ?? .seconds(2))
                } catch {
                    return
                }

                guard let self, let router, let routeScope else {
                    return
                }

                viewExitWatchdogs[scopeID] = nil
                guard routeScope.isInstalledInView else {
                    return
                }

                log.departureDebug(.ios17ViewExitWaitTimedOut(scope: routeScope))
                router.routeScopeDidLeaveView(routeScope)
            }
        }
    }

    private func makePendingDismissal(
        for presentationScope: RouteScope,
        in router: Router
    ) -> PendingDismissal? {
        guard
            let routePath = router.routeForest.routePath(containing: presentationScope),
            routePath.scopes.contains(where: { $0 === presentationScope }),
            let targetPosition = routePath.positionBefore(presentationScope),
            presentationScope.presentationDeclaration?.presentationKind == .push,
            isActivePresentationPath(routePath, in: router)
        else {
            return nil
        }

        return PendingDismissal(
            scope: presentationScope,
            routePath: routePath,
            targetPosition: targetPosition,
            unwindPlan: router.routeForest.unwindPlan(for: .scoped(
                routePath: routePath,
                after: targetPosition
            )),
            presentationOriginID: presentationScope.presentationOrigin.map(ObjectIdentifier.init)
        )
    }

    private func isValid(_ dismissal: PendingDismissal, in router: Router) -> Bool {
        let scope = dismissal.scope
        guard router.routeForest.routePath(containing: scope) === dismissal.routePath,
              dismissal.routePath.scopes.contains(where: { $0 === scope }),
              dismissal.routePath.positionBefore(scope) == dismissal.targetPosition,
              scope.presentationDeclaration?.presentationKind == .push,
              scope.presentationOrigin.map(ObjectIdentifier.init) == dismissal.presentationOriginID,
              isActivePresentationPath(dismissal.routePath, in: router)
        else {
            return false
        }

        let currentPlan = router.routeForest.unwindPlan(for: .scoped(
            routePath: dismissal.routePath,
            after: dismissal.targetPosition
        ))
        return hasSameStructure(dismissal.unwindPlan, currentPlan)
    }

    private func reconcilePendingDismissals(in router: Router) {
        let invalidDismissals = pendingDismissals.values.filter {
            isValid($0, in: router) == false
        }

        for dismissal in invalidDismissals {
            invalidate(dismissal)
        }
    }

    private func invalidate(_ dismissal: PendingDismissal) {
        let scopeID = ObjectIdentifier(dismissal.scope)
        guard pendingDismissals[scopeID]?.id == dismissal.id else {
            return
        }

        pendingDismissals[scopeID] = nil
        log.departureDebug(.ios17PushDismissalDropped(scope: dismissal.scope))
    }

    private func isActivePresentationPath(_ routePath: RoutePath, in router: Router) -> Bool {
        guard let tree = router.routeForest.tree(containing: routePath) else {
            return false
        }

        return routePath === tree.rootPath
            || tree.activeBranchPaths().contains(where: { $0 === routePath })
    }

    private func complete(_ dismissal: PendingDismissal, in router: Router) {
        router.performPresentationDismissalUnwind(
            for: dismissal.scope,
            in: dismissal.routePath.scope(at: dismissal.targetPosition),
            removing: dismissal.unwindPlan.removedScopes
        ) {
            router.applyUnwindPlan(dismissal.unwindPlan)
        }
    }

    private func cancelViewExitWatchdog(for routeScope: RouteScope) {
        viewExitWatchdogs.removeValue(forKey: ObjectIdentifier(routeScope))?.cancel()
    }

    private func hasSameStructure(
        _ first: RouteForest.UnwindPlan,
        _ second: RouteForest.UnwindPlan
    ) -> Bool {
        guard first.clearsElevatedTrees == second.clearsElevatedTrees,
              first.pathTrims.count == second.pathTrims.count,
              first.preservedPaths.count == second.preservedPaths.count,
              first.removedScopes.elementsEqual(second.removedScopes, by: { $0 === $1 })
        else {
            return false
        }

        let trimsMatch = first.pathTrims.allSatisfy { trim in
            second.pathTrims.contains {
                $0.path === trim.path && $0.keepThrough == trim.keepThrough
            }
        }
        guard trimsMatch else {
            return false
        }

        return first.preservedPaths.allSatisfy { path in
            second.preservedPaths.contains {
                $0.routePath === path.routePath
                && $0.scopes.elementsEqual(path.scopes, by: { $0 === $1 })
            }
        }
    }
}
