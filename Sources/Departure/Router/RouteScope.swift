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
import SwiftUI

final class RouteScope: Identifiable {
    struct RouteAttachmentMatch {
        let branchID: AnyHashable
        let declaration: AnyRouteDeclaration
    }

    private(set) var id: AnyHashable
    let route: (any Route)?
    weak var parent: RouteScope?

    private let initialID: AnyHashable
    var mountedBranchID: AnyHashable?
    var defaultBranch: Branch.ID
    private(set) var branches: [Branch]
    private(set) var branchSelection: AnyRouteBranchSelection?
    var mountedBranchScopes: [Branch.ID: RouteScope] = [:]

    private var routeSourceID: AnyHashable?
    private var hookSourceID: AnyHashable?
    private var unmountObservers: [@MainActor () -> Void] = []

    lazy var path = RoutePath(owner: self)
    weak var owningPath: RoutePath?

    weak var hostScope: RouteScope?
    var hostDeclaration: AnyRouteDeclaration?

    weak var pushChild: RouteScope?
    weak var modalChild: RouteScope?

    #if DEBUG
    var debugKind = DebugKind.root
    #endif

    private(set) var isMounted = false
    private(set) var sourceEnvironment = EnvironmentValues()

    init(id: AnyHashable, route: (any Route)?, parent: RouteScope? = nil) {
        self.id = id
        self.route = route
        self.parent = parent
        self.initialID = id
        self.defaultBranch = id
        self.branches = [Branch(id: id)]
    }
}

// MARK: - Derived State

extension RouteScope {
    var currentRoute: (any Route)? {
        route ?? parent?.currentRoute
    }
}

// MARK: - Lifecycle

extension RouteScope {
    func mount() {
        isMounted = true
    }

    func unmount() {
        isMounted = false

        unmountObservers.forEach { $0() }
        unmountObservers.removeAll()
    }

    func onUnmount(_ observer: @escaping @MainActor () -> Void) {
        guard isMounted else {
            observer()
            return
        }

        unmountObservers.append(observer)
    }
}

// MARK: - Route Attachment Lookup

extension RouteScope {
    func firstRouteAttachment(for routeType: (some Route).Type) -> RouteAttachmentMatch? {
        if let match = firstRouteAttachment(for: routeType, in: activeBranch) {
            return match
        }

        if let match = firstAdoptedRouteAttachment(for: routeType) {
            return match
        }

        for branch in branches where branch.id != activeBranch {
            if let match = firstRouteAttachment(for: routeType, in: branch.id) {
                return match
            }
        }

        return nil
    }

    func firstMountedBranchRouteAttachment(
        for routeType: (some Route).Type,
        in branch: AnyHashable
    ) -> RouteAttachmentMatch? {
        guard
            let mountedScope = mountedBranchScopes[branch]?.activeLocalScope,
            mountedScope !== self,
            let match = mountedScope.firstRouteAttachment(for: routeType)
        else {
            return nil
        }

        return RouteAttachmentMatch(branchID: branch, declaration: match.declaration)
    }
}

// MARK: - Hydration

extension RouteScope {
    func hydrateRoutes(
        sourceID: AnyHashable = AnyHashable("default"),
        id: AnyHashable?,
        branchSelection: AnyRouteBranchSelection?,
        routeDeclarations: [RouteScopeDeclaration],
        sourceEnvironment: EnvironmentValues? = nil
    ) {
        let hookDeclarations = branches.flatMap(\.hookAttachments)
        routeSourceID = sourceID
        self.sourceEnvironment = sourceEnvironment ?? EnvironmentValues()

        if let id {
            self.id = id
            if branchSelection == nil {
                defaultBranch = id
            }
        }

        self.branchSelection = branchSelection
        self.branches = makeBranches(
            from: routeDeclarations,
            activeBranch: activeBranch,
            hookDeclarations: hookDeclarations
        )
        log.departureDebug(.routesHydrated(scope: self, declarationCount: routeDeclarations.count))
    }

    func clearRoutes(sourceID: AnyHashable) {
        guard routeSourceID == sourceID else {
            return
        }

        routeSourceID = nil
        id = initialID
        defaultBranch = initialID
        branchSelection = nil
        sourceEnvironment = EnvironmentValues()
        branches = [Branch(id: initialID)]
        log.departureDebug(.routesCleared(scope: self))
    }

    func updateSourceEnvironment(_ sourceEnvironment: EnvironmentValues) {
        self.sourceEnvironment = sourceEnvironment
    }

    func hydrateHooks(
        sourceID: AnyHashable = AnyHashable("default"),
        hookDeclarations: [AnyHookDeclaration]
    ) {
        hookSourceID = sourceID
        let branchIndex = branches.index(for: activeBranch)
        var actionTypeIDs = Set<ObjectIdentifier>()
        var routeTypeIDs = Set<ObjectIdentifier>()

        for hookDeclaration in hookDeclarations {
            if let actionType = hookDeclaration.actionInterceptorType {
                let inserted = actionTypeIDs
                    .insert(ObjectIdentifier(actionType))
                    .inserted

                if inserted == false {
                    log.departureWarning(
                        """
                        Duplicate action interceptor for \(String(reflecting: actionType)) in scope \(String(describing: id)), branch \(String(describing: branches[branchIndex].id)). The first interceptor will be used.
                        """
                    )
                }
            }

            if let routeType = hookDeclaration.unwindHandlerRouteType {
                let inserted = routeTypeIDs
                    .insert(ObjectIdentifier(routeType))
                    .inserted

                if inserted == false {
                    log.departureWarning(
                        """
                        Duplicate unwind handler for \(String(reflecting: routeType)) in scope \(String(describing: id)), branch \(String(describing: branches[branchIndex].id)). The first handler will be used.
                        """
                    )
                }
            }
        }

        branches[branchIndex].hookAttachments = hookDeclarations
        log.departureDebug(.hooksHydrated(scope: self, hookCount: hookDeclarations.count))
    }

    func clearHooks(sourceID: AnyHashable) {
        guard hookSourceID == sourceID else {
            return
        }

        hookSourceID = nil
        let branchIndex = branches.index(for: activeBranch)
        branches[branchIndex].hookAttachments = []
        log.departureDebug(.hooksCleared(scope: self))
    }
}

// MARK: - Private Helpers

private extension RouteScope {
    func firstRouteAttachment(
        for routeType: (some Route).Type,
        in branchID: AnyHashable
    ) -> RouteAttachmentMatch? {
        guard
            let branch = branches.first(where: { $0.id == branchID }),
            let declaration = branch.routeAttachments.first(where: { attachment in
                routeType == attachment.routeType
            })
        else {
            return nil
        }

        return RouteAttachmentMatch(branchID: branch.id, declaration: declaration)
    }

}

#if DEBUG
extension RouteScope {
    enum DebugKind {
        case root
        case branch
    }
}
#endif
