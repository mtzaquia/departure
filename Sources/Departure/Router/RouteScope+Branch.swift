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
    // Enumerate owned branch paths for unwind plans and presentation projections.
    func branchPaths(includingInactive: Bool = true) -> [RoutePath] {
        let branches = branchScopes.keys.compactMap { branch in
            includingInactive || participates(inBranch: branch) ? branchScopes[branch] : nil
        }
        return branches.flatMap { [$0.path] + $0.branchPaths(includingInactive: includingInactive) }
            + path.scopes.flatMap { $0.branchPaths(includingInactive: includingInactive) }
    }

    var activeBranch: AnyHashable {
        access(keyPath: \.branchContainer)
        return branchContainer?.activeBranch ?? id
    }

    var isConcurrent: Bool {
        access(keyPath: \.branchContainer)
        return branchContainer?.isConcurrent == true
    }

    var activeLocalScope: RouteScope {
        path.last?.activeLocalScope
        ?? branchScopes[activeBranch]?.activeLocalScope
        ?? self
    }

    func participates(inBranch branch: AnyHashable) -> Bool {
        return isConcurrent || activeBranch == branch
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
        var container = branchContainer ?? BranchContainerState(selectedBranch: branch, selection: nil)
        var didSet = false
        let update = {
            didSet = container.setActiveBranch(branch)
            self.branchContainer = container
        }
        if activeBranch != branch { withMutation(keyPath: \.branchContainer, update) }
        else { update() }
        return didSet
    }

    func bindBranchSelection(_ selection: AnyRouteBranchSelection) {
        guard var container = branchContainer else { return }
        container.selection = selection
        container.selectedBranch = selection.value()
        let update = { self.branchContainer = container }
        if activeBranch != container.activeBranch || isConcurrent != container.isConcurrent {
            withMutation(keyPath: \.branchContainer, update)
        } else { update() }
    }
}
