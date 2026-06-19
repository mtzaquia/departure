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

// MARK: - Types

extension RouteScope {
    struct Branch: Identifiable {
        let id: AnyHashable

        var routeAttachments: [AnyRouteDeclaration] = []
        var hookAttachments: [AnyHookDeclaration] = []
    }
}

// MARK: - Derived State

extension RouteScope {
    var activeBranch: Branch.ID {
        branchSelection?.value() ?? defaultBranch
    }

    var activeLocalScope: RouteScope {
        path.last?.activeLocalScope
        ?? mountedBranchScopes[activeBranch]?.activeLocalScope
        ?? self
    }

    func canDrivePresentation(matching presentationKind: RoutePresentationKind) -> Bool {
        if presentationKind == .push {
            return true
        }

        guard let parent else {
            return true
        }

        return parent.activeBranch == (mountedBranchID ?? id)
    }

    var routeAttachments: [AnyRouteDeclaration] {
        let local = activeBranchScope?.routeAttachments ?? []
        let adopted = adoptedRouteAttachments
        if adopted.isEmpty {
            return local
        }
        if local.isEmpty {
            return adopted
        }
        return local + adopted
    }

    var hookAttachments: [AnyHookDeclaration] {
        activeBranchScope?.hookAttachments ?? []
    }
}

// MARK: - Selection

extension RouteScope {
    @discardableResult
    func setActiveBranch(_ branch: AnyHashable) -> Bool {
        if let branchSelection {
            return branchSelection.setValue(branch)
        }

        defaultBranch = branch
        return true
    }
}

// MARK: - Mounted Scopes

extension RouteScope {
    func activeLocalScope(for branch: AnyHashable) -> RouteScope? {
        if let mountedScope = mountedBranchScopes[branch] {
            return mountedScope.activeLocalScope
        }

        guard branch == activeBranch else {
            return nil
        }

        return self
    }

    @discardableResult
    func registerBranchScope(
        _ routeScope: RouteScope,
        for branch: AnyHashable,
        sourceEnvironment: EnvironmentValues? = nil
    ) -> Bool {
        #if DEBUG
        routeScope.debugKind = .branch
        #endif
        routeScope.mountedBranchID = branch
        if let sourceEnvironment {
            routeScope.updateSourceEnvironment(sourceEnvironment)
        }

        if mountedBranchScopes[branch] === routeScope {
            routeScope.parent = self
            return false
        }

        routeScope.parent = self
        mountedBranchScopes[branch] = routeScope
#if DEBUG
        log.departureDebug(
            "branch registered | branch=\(branch.departureDebugDescription) | parent=\(departureDebugDescription) | scope=\(routeScope.departureDebugDescription)"
        )
#endif
        return true
    }

    func unregisterBranchScope(_ routeScope: RouteScope, for branch: AnyHashable) {
        guard let registeredScope = mountedBranchScopes[branch] else {
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

        mountedBranchScopes[branch] = nil
        routeScope.parent = nil
        routeScope.mountedBranchID = nil
#if DEBUG
        log.departureDebug(
            "branch unregistered | branch=\(branch.departureDebugDescription) | scope=\(routeScope.departureDebugDescription)"
        )
#endif
    }
}

// MARK: - Declaration Adoption

extension RouteScope {
    func routeDeclarations(adoptedByBranch branchID: AnyHashable) -> [RouteScopeDeclaration] {
        guard
            let branch = branches.first(where: { $0.id == branchID }),
            branch.routeAttachments.isEmpty == false
        else {
            return []
        }

        return [
            RouteScopeDeclaration(
                routes: branch.routeAttachments.map {
                    $0.drivingPresentation(true)
                }
            ),
        ]
    }

    func firstAdoptedRouteAttachment(for routeType: (some Route).Type) -> RouteAttachmentMatch? {
        guard
            let declaration = adoptedRouteAttachments.first(where: { attachment in
                routeType == attachment.routeType
            })
        else {
            return nil
        }

        return RouteAttachmentMatch(branchID: activeBranch, declaration: declaration)
    }
}

// MARK: - Hydration

extension RouteScope {
    func makeBranches(
        from routeDeclarations: [RouteScopeDeclaration],
        activeBranch: AnyHashable,
        hookDeclarations: [AnyHookDeclaration]
    ) -> [Branch] {
        var branches = [Branch(id: activeBranch)]

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

// MARK: - Private Helpers

private extension RouteScope {
    var activeBranchScope: Branch? {
        branches.first { $0.id == activeBranch }
    }

    var adoptedRouteAttachments: [AnyRouteDeclaration] {
        guard let mountedBranchID else {
            return []
        }

        return parent?
            .routeDeclarations(adoptedByBranch: mountedBranchID)
            .flatMap(\.routes) ?? []
    }

}

extension Array where Element == RouteScope.Branch {
    mutating func index(for id: AnyHashable) -> Index {
        if let index = firstIndex(where: { $0.id == id }) {
            return index
        }

        append(RouteScope.Branch(id: id))
        return index(before: endIndex)
    }
}
