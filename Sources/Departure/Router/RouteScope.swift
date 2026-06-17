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
    struct Branch: Identifiable {
        let id: AnyHashable

        var routeAttachments: [AnyRouteDeclaration] = []
        var hookAttachments: [AnyHookDeclaration] = []
    }

    private(set) var id: AnyHashable
    let route: (any Route)?
    weak var parent: RouteScope?

    private var defaultBranch: Branch.ID
    private(set) var branches: [Branch]
    private(set) var branchSelection: AnyRouteBranchSelection?
    private var branchScopes: [Branch.ID: RouteScope] = [:]
    private var unmountObservers: [@MainActor () -> Void] = []

    #if DEBUG
    private(set) var debugKind = DebugKind.root
    #endif

    private(set) var isMounted = false
    private(set) var sourceEnvironment = EnvironmentValues()

    var activeBranch: Branch.ID {
        branchSelection?.value() ?? defaultBranch
    }

    var currentRoute: (any Route)? {
        route ?? parent?.currentRoute
    }

    var activeLocalScope: RouteScope {
        branchScopes[activeBranch]?.activeLocalScope ?? self
    }

    var canDrivePresentation: Bool {
        guard let parent else {
            return true
        }

        return parent.activeBranch == id
    }

    var routeAttachments: [AnyRouteDeclaration] {
        activeBranchScope?.routeAttachments ?? []
    }

    var hookAttachments: [AnyHookDeclaration] {
        activeBranchScope?.hookAttachments ?? []
    }

    private var activeBranchScope: Branch? {
        branches.first { $0.id == activeBranch }
    }

    init(id: AnyHashable, route: (any Route)?, parent: RouteScope? = nil) {
        self.id = id
        self.route = route
        self.parent = parent
        self.defaultBranch = id
        self.branches = [Branch(id: id)]
    }

    @discardableResult
    func setActiveBranch(_ branch: AnyHashable) -> Bool {
        if let branchSelection {
            return branchSelection.setValue(branch)
        }

        defaultBranch = branch
        return true
    }

    @discardableResult
    func registerBranchScope(_ routeScope: RouteScope, for branch: AnyHashable) -> Bool {
        #if DEBUG
        routeScope.debugKind = .branch
        #endif

        guard branchScopes[branch] !== routeScope else {
            routeScope.parent = self
            return false
        }

        routeScope.parent = self
        branchScopes[branch] = routeScope
#if DEBUG
        log.departureDebug(
            "branch registered | branch=\(branch.departureDebugDescription) | parent=\(departureDebugDescription) | scope=\(routeScope.departureDebugDescription)"
        )
#endif
        return true
    }

    func unregisterBranchScope(_ routeScope: RouteScope, for branch: AnyHashable) {
        guard let registeredScope = branchScopes[branch] else {
            return
        }

        guard registeredScope === routeScope else {
#if DEBUG
            log.departureDebug(
                "branch unregister skipped | branch=\(branch.departureDebugDescription) | reason=scope mismatch | scope=\(routeScope.departureDebugDescription)"
            )
#endif
            return
        }

#if DEBUG
        log.departureDebug(
            "branch unregistered | branch=\(branch.departureDebugDescription) | scope=\(routeScope.departureDebugDescription)"
        )
#endif
        branchScopes[branch] = nil
        routeScope.parent = nil
    }

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

    func firstRouteAttachment(for routeType: (some Route).Type) -> RouteAttachmentMatch? {
        if let match = firstRouteAttachment(for: routeType, in: activeBranch) {
            return match
        }

        for branch in branches where branch.id != activeBranch {
            if let match = firstRouteAttachment(for: routeType, in: branch.id) {
                return match
            }
        }

        return nil
    }

    private func firstRouteAttachment(
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

    struct RouteAttachmentMatch {
        let branchID: AnyHashable
        let declaration: AnyRouteDeclaration
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

// MARK: - Hydration

extension RouteScope {
    func hydrateRoutes(
        id: AnyHashable?,
        branchSelection: AnyRouteBranchSelection?,
        routeDeclarations: [RouteScopeDeclaration],
        sourceEnvironment: EnvironmentValues? = nil
    ) {
        let hookDeclarations = branches.flatMap(\.hookAttachments)

        if let sourceEnvironment {
            self.sourceEnvironment = sourceEnvironment
        }

        if let id {
            self.id = id
            if branchSelection == nil {
                defaultBranch = id
            }
        }

        self.branchSelection = branchSelection
        self.branches = Self.branches(
            activeBranch: self.activeBranch,
            routeDeclarations: routeDeclarations,
            hookDeclarations: hookDeclarations
        )
#if DEBUG
        let branchDescription = branchDebugDescription.map { ", branches: \($0)" } ?? ""
        log.departureDebug(
            "routes hydrated | scope=\(departureDebugDescription) | declarations=\(routeDeclarations.count)\(branchDescription)"
        )
#endif
    }

    func hydrateHooks(
        hookDeclarations: [AnyHookDeclaration]
    ) {
        let branchIndex = branches.index(for: activeBranch)
        branches[branchIndex].hookAttachments = hookDeclarations
#if DEBUG
        log.departureDebug(
            "hooks hydrated | scope=\(departureDebugDescription) | hooks=\(hookDeclarations.count)"
        )
#endif
    }

    private static func branches(
        activeBranch: AnyHashable,
        routeDeclarations: [RouteScopeDeclaration],
        hookDeclarations: [AnyHookDeclaration]
    ) -> [Branch] {
        var branches: [Branch] = [Branch(id: activeBranch)]

        for declaration in routeDeclarations {
            let branchID = declaration.branch ?? activeBranch
            let branchIndex = branches.index(for: branchID)
            branches[branchIndex].routeAttachments.append(contentsOf: declaration.routes)
        }

        if hookDeclarations.isEmpty == false {
            let branchIndex = branches.index(for: activeBranch)
            branches[branchIndex].hookAttachments.append(contentsOf: hookDeclarations)
        }

        return branches
    }
}

private extension Array where Element == RouteScope.Branch {
    mutating func index(for id: AnyHashable) -> Index {
        if let index = firstIndex(where: { $0.id == id }) {
            return index
        }

        append(RouteScope.Branch(id: id))
        return index(before: endIndex)
    }
}
