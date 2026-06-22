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

    func canDrivePresentation(matching presentationKind: RoutePresentationKind) -> Bool {
        if presentationKind == .push {
            return true
        }

        guard let parent else {
            return true
        }

        return parent.activeBranch == (branchID ?? id)
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
    func activeLocalScope(for branch: AnyHashable) -> RouteScope? {
        if let branchScope = branchScopes[branch] {
            return branchScope.activeLocalScope
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
        routeScope.branchID = branch
        if let sourceEnvironment {
            routeScope.updateSourceEnvironment(sourceEnvironment)
        }

        if branchScopes[branch] === routeScope {
            routeScope.parent = self
            return false
        }

        routeScope.parent = self
        branchScopes[branch] = routeScope
        log.departureDebug(.branchRegistered(branch: branch, parent: self, scope: routeScope))
        return true
    }

    func unregisterBranchScope(_ routeScope: RouteScope, for branch: AnyHashable) {
        guard let registeredScope = branchScopes[branch] else {
            return
        }

        guard registeredScope === routeScope else {
            log.departureDebug(.branchUnregisterSkipped(branch: branch, scope: routeScope))
            return
        }

        branchScopes[branch] = nil
        routeScope.parent = nil
        routeScope.branchID = nil
        log.departureDebug(.branchUnregistered(branch: branch, scope: routeScope))
    }
}
