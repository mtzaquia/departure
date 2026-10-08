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

final class RouteSpace {
    let priority: RoutePriority
    let root: RouteScope
    var rootPath: RoutePath { root.path }

    init(
        priority: RoutePriority,
        root: RouteScope
    ) {
        self.priority = priority
        self.root = root
        precondition(root.anchorSpace == nil, "A priority space owns its own root.")
        root.anchorSpace = self
    }

    var currentRoutePath: RoutePath {
        let activeScope = rootPath.last?.activeLocalScope ?? root.activeLocalScope

        // A branch root owns its navigation path rather than appearing inside it. Once that path
        // contains a presented scope, the active scope's `owningPath` identifies the same path.
        if activeScope.branchID != nil {
            return activeScope.path
        }

        return activeScope.owningPath ?? rootPath
    }

    var currentRouteScope: RouteScope {
        currentRoutePath.last?.activeLocalScope
        ?? currentRoutePath.owner?.activeLocalScope
        ?? root.activeLocalScope
    }

    func contains(_ path: RoutePath) -> Bool { path.owner?.belongs(to: self) == true }

    func routePath(containing scope: RouteScope) -> RoutePath? {
        guard scope.belongs(to: self) else { return nil }
        return scope.routePath
    }

    func activeBranchPaths() -> [RoutePath] {
        root.branchPaths(includingInactive: false)
    }

    func allBranchPaths() -> [RoutePath] {
        root.branchPaths()
    }

    var allRoutePaths: [RoutePath] {
        [rootPath] + allBranchPaths()
    }

    var currentModalScope: RouteScope? { root.lane.deepestModal }

}
