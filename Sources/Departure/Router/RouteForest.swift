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

struct RouteForest {
    struct PreservedRoutePath {
        let routePath: RoutePath
        let scopes: [RouteScope]

        init(_ routePath: RoutePath, after position: RoutePath.Position) {
            self.routePath = routePath
            self.scopes = routePath.scopesRemovedAfter(position)
        }
    }

    struct RootUnwindPlan {
        let removedScopes: [RouteScope]
        let branchPaths: [RoutePath]
        let inactiveBranchModalTrims: [(path: RoutePath, keepThrough: RoutePath.Position)]
        let preservedPaths: [PreservedRoutePath]
    }

    let normalTree: RouteTree
    var highTree: RouteTree?
    var criticalTree: RouteTree?

    var activeTree: RouteTree {
        criticalTree ?? highTree ?? normalTree
    }

    private var elevatedTrees: [RouteTree] {
        allTrees.reversed().filter { $0.priority != .normal }
    }

    var allTrees: [RouteTree] {
        [normalTree, highTree, criticalTree].compactMap { $0 }
    }

    private var declarationSearchTrees: [RouteTree] {
        allTrees.reversed().filter { $0.priority <= activeTree.priority }
    }

    func tree(for priority: RoutePriority) -> RouteTree? {
        switch priority {
        case .normal:
            normalTree

        case .high:
            highTree

        case .critical:
            criticalTree
        }
    }

    func tree(containing routePath: RoutePath) -> RouteTree? {
        allTrees.first { $0.contains(routePath) }
    }

    func elevatedTree(
        containingPath path: RoutePath,
        position: RoutePath.Position,
        minimumPriority: RoutePriority
    ) -> RouteTree? {
        elevatedTrees.first {
            $0.priority >= minimumPriority
            && $0.contains(path: path, position: position)
        }
    }

    func routePath(containing routeScope: RouteScope) -> RoutePath? {
        allTrees.lazy.compactMap { $0.routePath(containing: routeScope) }.first
    }

    private func inactiveBranchModalTrims(
        excluding clearedPaths: [RoutePath]
    ) -> [(path: RoutePath, keepThrough: RoutePath.Position)] {
        allTrees.flatMap { $0.allBranchPaths() }.compactMap { branchPath in
            guard clearedPaths.contains(where: { $0 === branchPath }) == false else {
                return nil
            }

            guard let modalScope = branchPath.scopes.first(where: {
                $0.hostDeclaration?.presentationKind != .push
            }) else {
                return nil
            }

            return (
                path: branchPath,
                keepThrough: branchPath.positionBefore(modalScope) ?? .owner
            )
        }
    }

    func rootUnwindPlan() -> RootUnwindPlan {
        let rootPath = normalTree.rootPath
        let rootRemovedScopes = rootPath.scopesRemovedAfter(.owner)
        var branchPaths = normalTree.activeBranchPaths()
        branchPaths.appendUnique(contentsOf: rootRemovedScopes.flatMap {
            normalTree.allBranchPaths(under: $0)
        })

        for elevatedTree in elevatedTrees {
            branchPaths.appendUnique(contentsOf: [elevatedTree.rootPath])
            branchPaths.appendUnique(contentsOf: elevatedTree.allBranchPaths())
        }

        let branchRemovedScopes = branchPaths.flatMap {
            $0.scopesRemovedAfter(.owner)
        }
        let inactiveBranchModalTrims = inactiveBranchModalTrims(excluding: branchPaths)
        let inactiveBranchRemovedScopes = inactiveBranchModalTrims.flatMap {
            $0.path.scopesRemovedAfter($0.keepThrough)
        }
        let removedScopes = rootRemovedScopes + branchRemovedScopes + inactiveBranchRemovedScopes

        let preservedPaths = (
            [PreservedRoutePath(rootPath, after: .owner)]
            + branchPaths.map { PreservedRoutePath($0, after: .owner) }
            + inactiveBranchModalTrims.map { PreservedRoutePath($0.path, after: $0.keepThrough) }
        ).filter { $0.scopes.isEmpty == false }

        return RootUnwindPlan(
            removedScopes: removedScopes,
            branchPaths: branchPaths,
            inactiveBranchModalTrims: inactiveBranchModalTrims,
            preservedPaths: preservedPaths
        )
    }

    func ancestorUnwindResolution(
        from routePath: RoutePath,
        to target: Router.UnwindTarget?
    ) -> (path: RoutePath, position: RoutePath.Position)? {
        guard case .id = target else {
            return nil
        }

        if let routeTree = tree(containing: routePath), routeTree.priority != .normal {
            for lowerTree in allTrees.reversed() where lowerTree.priority < routeTree.priority {
                for candidatePath in [lowerTree.currentRoutePath, lowerTree.rootPath] {
                    switch candidatePath.unwindResolution(to: target) {
                    case let .keepPathThrough(position):
                        return (candidatePath, position)

                    case .noRouteToUnwind, .targetNotFound:
                        break
                    }
                }
            }
        }

        var scope = routePath.owner?.parent
        while let ancestorScope = scope {
            if let ancestorPath = self.routePath(containing: ancestorScope) {
                switch ancestorPath.unwindResolution(to: target) {
                case let .keepPathThrough(position):
                    return (ancestorPath, position)

                case .noRouteToUnwind, .targetNotFound:
                    break
                }
            }

            scope = ancestorScope.parent
        }

        return nil
    }

    mutating func setElevatedTree(_ tree: RouteTree?, for priority: RoutePriority) {
        switch priority {
        case .normal:
            return

        case .high:
            highTree = tree

        case .critical:
            criticalTree = tree
        }
    }

    mutating func clearElevatedTrees() {
        highTree = nil
        criticalTree = nil
    }
}

private extension [RoutePath] {
    mutating func appendUnique(contentsOf routePaths: [RoutePath]) {
        for routePath in routePaths where contains(where: { $0 === routePath }) == false {
            append(routePath)
        }
    }
}

extension RouteForest {
    func firstDeclaration(including routeType: any Route.Type) -> Router.DeclarationMatch? {
        for tree in declarationSearchTrees {
            if let match = firstDeclaration(in: tree.currentRoutePath, tree: tree, including: routeType) {
                return match
            }

            if tree.currentRoutePath !== tree.rootPath,
               let match = firstDeclaration(in: tree.rootPath, tree: tree, including: routeType) {
                return match
            }
        }

        let root = normalTree.root
        if let match = root.firstBranchScopeRouteAttachment(for: routeType, in: root.activeBranch) {
            let routePath = routePath(for: match, under: root, fallbackPath: normalTree.rootPath, fallbackPosition: .owner)
            return Router.DeclarationMatch(
                routePath: routePath,
                tree: normalTree,
                declaringPath: normalTree.rootPath,
                declaringPosition: .owner,
                attachment: match
            )
        }

        if let match = root.firstRouteAttachment(for: routeType) {
            let routePath = routePath(for: match, under: root, fallbackPath: normalTree.rootPath, fallbackPosition: .owner)
            return Router.DeclarationMatch(
                routePath: routePath,
                tree: normalTree,
                declaringPath: normalTree.rootPath,
                declaringPosition: .owner,
                attachment: match
            )
        }

        return nil
    }

    private func firstDeclaration(
        in searchPath: RoutePath,
        tree: RouteTree,
        including routeType: any Route.Type
    ) -> Router.DeclarationMatch? {
        for scope in searchPath.scopes.reversed() {
            let position = RoutePath.Position.scope(scope)

            if let match = scope.firstBranchScopeRouteAttachment(for: routeType, in: scope.activeBranch) {
                let routePath = routePath(
                    for: match,
                    under: scope,
                    fallbackPath: searchPath,
                    fallbackPosition: position
                )
                return Router.DeclarationMatch(
                    routePath: routePath,
                    tree: tree,
                    declaringPath: searchPath,
                    declaringPosition: position,
                    attachment: match
                )
            }

            if let match = scope.firstRouteAttachment(for: routeType) {
                return Router.DeclarationMatch(
                    routePath: (path: searchPath, position: position),
                    tree: tree,
                    declaringPath: searchPath,
                    declaringPosition: position,
                    attachment: match
                )
            }
        }

        guard let owner = searchPath.owner, owner !== tree.root else {
            return nil
        }

        if let match = owner.firstRouteAttachment(for: routeType) {
            return Router.DeclarationMatch(
                routePath: (path: searchPath, position: .owner),
                tree: tree,
                declaringPath: searchPath,
                declaringPosition: .owner,
                attachment: match
            )
        }

        return nil
    }

    private func routePath(
        for match: RouteScope.RouteAttachmentMatch,
        under routeScope: RouteScope,
        fallbackPath: RoutePath,
        fallbackPosition: RoutePath.Position
    ) -> (path: RoutePath, position: RoutePath.Position) {
        guard let branchID = match.branchID else {
            return (path: fallbackPath, position: fallbackPosition)
        }

        return routePath(forBranch: branchID, under: routeScope, declaration: match.declaration)
    }

    func routePath(
        forBranch branchID: AnyHashable,
        under routeScope: RouteScope,
        declaration: AnyRouteDeclaration
    ) -> (path: RoutePath, position: RoutePath.Position) {
        guard let branchScope = routeScope.branchScopes[branchID] else {
            return (path: routePath(containing: routeScope) ?? normalTree.rootPath, position: .owner)
        }

        guard declaration.presentationKind != .push else {
            return (path: branchScope.path, position: .owner)
        }

        return (
            path: branchScope.path,
            position: branchScope.path.lastPosition
        )
    }
}
