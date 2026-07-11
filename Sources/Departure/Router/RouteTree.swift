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

final class RouteTree {
    struct ElevatedOrigin {
        weak var scope: RouteScope?
        let declaration: AnyRouteDeclaration
        let sourceEnvironment: RouteSourceEnvironment
    }

    let priority: RoutePriority
    let root: RouteScope
    let rootPath: RoutePath
    let elevatedOrigin: ElevatedOrigin?

    init(
        priority: RoutePriority,
        root: RouteScope,
        rootPath: RoutePath? = nil,
        elevatedOrigin: ElevatedOrigin? = nil
    ) {
        self.priority = priority
        self.root = root
        self.rootPath = rootPath ?? RoutePath(owner: root)
        self.elevatedOrigin = elevatedOrigin
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

    var elevatedRouteScope: RouteScope? {
        guard priority != .normal else {
            return nil
        }

        return rootPath.first
    }

    var activeRouteScopeID: ObjectIdentifier {
        ObjectIdentifier(currentRouteScope)
    }

    func contains(_ routePath: RoutePath) -> Bool {
        routePath === rootPath || contains(routePath, under: root)
    }

    func contains(path: RoutePath, position: RoutePath.Position) -> Bool {
        guard priority != .normal else {
            return false
        }

        if path === rootPath {
            return position != .owner
        }

        return contains(path)
    }

    func routePath(containing routeScope: RouteScope) -> RoutePath? {
        if routeScope === root {
            return rootPath
        }

        if routeScope.branchID != nil {
            return routeScope.path
        }

        if let owningPath = routeScope.owningPath, contains(owningPath) {
            return owningPath
        }

        if rootPath.contains(routeScope) {
            return rootPath
        }

        return routePath(containing: routeScope, under: root)
    }

    func activeBranchPaths() -> [RoutePath] {
        branchPaths(under: root, includesInactiveBranches: false)
    }

    func allBranchPaths() -> [RoutePath] {
        allBranchPaths(under: root)
    }

    var allRoutePaths: [RoutePath] {
        [rootPath] + allBranchPaths()
    }

    func modalDepth(of routeScope: RouteScope) -> Int {
        var depth = 0
        var scope: RouteScope? = routeScope

        while let current = scope, current !== root {
            if let declaration = current.presentationDeclaration,
               declaration.presentationKind != .push {
                depth += 1
            }

            scope = current.previousScopeInTree
        }

        return depth
    }

    func modalScopes(atDepth depth: Int) -> [(path: RoutePath, scope: RouteScope)] {
        allRoutePaths.flatMap { path in
            path.scopes.compactMap { scope in
                guard let declaration = scope.presentationDeclaration,
                      declaration.presentationKind != .push,
                      modalDepth(of: scope) == depth
                else {
                    return nil
                }

                return (path, scope)
            }
        }
    }

    func allBranchPaths(under owner: RouteScope) -> [RoutePath] {
        branchPaths(under: owner, includesInactiveBranches: true)
    }

    private func branchPaths(
        under owner: RouteScope,
        includesInactiveBranches: Bool
    ) -> [RoutePath] {
        var paths: [RoutePath] = []

        for branchScope in branchScopes(under: owner, includesInactiveBranches: includesInactiveBranches) {
            paths.append(branchScope.path)
            paths.append(contentsOf: branchPaths(
                under: branchScope,
                includesInactiveBranches: includesInactiveBranches
            ))
        }

        for scope in scopesOwned(by: owner) {
            paths.append(contentsOf: branchPaths(
                under: scope,
                includesInactiveBranches: includesInactiveBranches
            ))
        }

        return paths
    }

    private func branchScopes(
        under owner: RouteScope,
        includesInactiveBranches: Bool
    ) -> [RouteScope] {
        guard includesInactiveBranches == false else {
            return Array(owner.branchScopes.values)
        }

        return owner.branchScopes[owner.activeBranch].map { [$0] } ?? []
    }

    private func contains(_ routePath: RoutePath, under owner: RouteScope) -> Bool {
        for branchScope in owner.branchScopes.values {
            if routePath === branchScope.path || contains(routePath, under: branchScope) {
                return true
            }
        }

        let ownedScopes = owner === root ? rootPath.scopes : owner.path.scopes
        for scope in ownedScopes where contains(routePath, under: scope) {
            return true
        }

        return false
    }

    private func routePath(containing routeScope: RouteScope, under owner: RouteScope) -> RoutePath? {
        for branchScope in owner.branchScopes.values {
            if branchScope.path.contains(routeScope) {
                return branchScope.path
            }

            if let routePath = self.routePath(containing: routeScope, under: branchScope) {
                return routePath
            }
        }

        let ownedScopes = owner === root ? rootPath.scopes : owner.path.scopes
        for scope in ownedScopes {
            if let routePath = self.routePath(containing: routeScope, under: scope) {
                return routePath
            }
        }

        return nil
    }

    private func scopesOwned(by owner: RouteScope) -> [RouteScope] {
        let ownerPath = routePath(containing: owner) ?? rootPath
        return owner === ownerPath.owner ? ownerPath.scopes : owner.path.scopes
    }
}

extension RouteScope {
    var previousScopeInTree: RouteScope? {
        if let owningPath,
           let index = owningPath.scopes.firstIndex(where: { $0 === self }) {
            guard index > owningPath.scopes.startIndex else {
                return owningPath.owner
            }

            return owningPath.scopes[owningPath.scopes.index(before: index)]
        }

        return parent
    }
}
