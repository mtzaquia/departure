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

// MARK: - Derived State

extension RouteScope {
    var activeBranch: AnyHashable {
        branchContainer?.activeBranch ?? id
    }

    var activeLocalScope: RouteScope {
        path.last?.activeLocalScope
        ?? branchScopes[activeBranch]?.activeLocalScope
        ?? self
    }

    func participates(inBranch branch: AnyHashable) -> Bool {
        _ = participation.isConcurrent
        return branchContainer?.isConcurrent == true || activeBranch == branch
    }

    func canDrivePresentation(matching presentationKind: RoutePresentationKind) -> Bool {
        if !presentationKind.isModal {
            return true
        }

        guard let parent else {
            return true
        }

        return parent.participates(inBranch: branchID ?? id)
    }
}

// MARK: - Selection

extension RouteScope {
    @discardableResult
    func setActiveBranch(_ branch: AnyHashable) -> Bool {
        guard var branchContainer else {
            branchContainer = BranchContainerState(
                defaultBranch: branch,
                selection: nil
            )
            return true
        }

        let didSet = branchContainer.setActiveBranch(branch)
        self.branchContainer = branchContainer
        return didSet
    }
}

// MARK: - Branch Scopes

extension RouteScope {
    @discardableResult
    func registerBranchScope(
        _ routeScope: RouteScope,
        for branch: AnyHashable,
        sourceEnvironment: EnvironmentValues? = nil,
        presentationHostID: RoutePresentationHostID? = nil
    ) -> Bool {
        #if DEBUG
        routeScope.debugKind = .branch
        #endif
        if let sourceEnvironment {
            routeScope.updateSourceEnvironment(sourceEnvironment)
        }

        if let previousParent = routeScope.parent, previousParent !== self,
           let previousBranch = routeScope.branchID {
            previousParent.unregisterBranchScope(routeScope, for: previousBranch)
        }

        for previousBranch in ledger.branches(containing: routeScope) where previousBranch != branch {
            unregisterBranchScope(routeScope, for: previousBranch)
        }

        let previous = branchScopes[branch]
        ledger.setBranchSource(
            .init(scope: routeScope, environment: sourceEnvironment,
                presentationHostID: presentationHostID),
            for: branch
        )
        updateActiveBranchSource(for: branch)
        return branchScopes[branch] !== previous
    }

    func unregisterBranchScope(_ routeScope: RouteScope, for branch: AnyHashable) {
        guard ledger.removeBranchSource(routeScope, for: branch) else {
            log.departureDebug(.branchUnregisterSkipped(branch: branch, scope: routeScope))
            return
        }

        updateActiveBranchSource(for: branch)
    }

    private func updateActiveBranchSource(for branch: AnyHashable) {
        let previous = branchScopes[branch]
        let active = ledger.activeBranchSource(for: branch)
        if previous !== active?.scope {
            if let previous {
                previous.participation.isBranchHostRegistered = false
                previous.parent = nil
                previous.branchID = nil
                previous.adoptedRoutePresentationHostID = nil
                log.departureDebug(.branchUnregistered(branch: branch, scope: previous))
            }
            branchScopes[branch] = active?.scope
            if let active {
                active.scope.parent = self
                active.scope.branchID = branch
                active.scope.participation.isBranchHostRegistered = true
                log.departureDebug(.branchRegistered(branch: branch, parent: self, scope: active.scope))
            }
        }

        if let active {
            active.scope.adoptedRoutePresentationHostID = active.presentationHostID
            if let environment = active.environment {
                active.scope.updateSourceEnvironment(environment)
            }
        }
    }
}
