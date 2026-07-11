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

    struct UnwindPlan {
        let removedScopes: [RouteScope]
        let pathTrims: [RoutePathTrim]
        let preservedPaths: [PreservedRoutePath]
        let clearsElevatedTrees: Bool

        init(
            pathTrims: [RoutePathTrim],
            clearsElevatedTrees: Bool = false
        ) {
            self.pathTrims = pathTrims.mergingByPath()
            self.removedScopes = self.pathTrims.flatMap(\.removedScopes)
            self.preservedPaths = self.pathTrims.map {
                PreservedRoutePath($0.path, after: $0.keepThrough)
            }.filter { $0.scopes.isEmpty == false }
            self.clearsElevatedTrees = clearsElevatedTrees
        }
    }

    indirect enum UnwindPlanRequest {
        case root
        case scoped(routePath: RoutePath, after: RoutePath.Position)
        case combined([UnwindPlanRequest])
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
                $0.presentationDeclaration?.presentationKind != .push
            }) else {
                return nil
            }

            return (
                path: branchPath,
                keepThrough: branchPath.positionBefore(modalScope) ?? .owner
            )
        }
    }

    func unwindPlan(for request: UnwindPlanRequest) -> UnwindPlan {
        switch request {
        case .root:
            return UnwindPlan(
                pathTrims: pathTrims(for: request),
                clearsElevatedTrees: true
            )

        case .scoped:
            return UnwindPlan(pathTrims: pathTrims(for: request))

        case .combined:
            let plans = combinedRequests(for: request).map { unwindPlan(for: $0) }
            return UnwindPlan(
                pathTrims: plans.flatMap(\.pathTrims),
                clearsElevatedTrees: plans.contains(where: \.clearsElevatedTrees)
            )
        }
    }

    private func pathTrims(for request: UnwindPlanRequest) -> [RoutePathTrim] {
        switch request {
        case .root:
            return rootPathTrims()

        case let .scoped(routePath, position):
            return scopedPathTrims(from: routePath, after: position)

        case .combined:
            return combinedRequests(for: request).flatMap { pathTrims(for: $0) }
        }
    }

    private func combinedRequests(for request: UnwindPlanRequest) -> [UnwindPlanRequest] {
        guard case let .combined(requests) = request else {
            return [request]
        }

        return requests
    }

    private func rootPathTrims() -> [RoutePathTrim] {
        let rootPath = normalTree.rootPath
        var branchPaths = normalTree.activeBranchPaths()
        branchPaths.appendUnique(contentsOf: rootPath.scopesRemovedAfter(.owner).flatMap {
            normalTree.allBranchPaths(under: $0)
        })

        for elevatedTree in elevatedTrees {
            branchPaths.appendUnique(contentsOf: [elevatedTree.rootPath])
            branchPaths.appendUnique(contentsOf: elevatedTree.allBranchPaths())
        }

        let inactiveBranchModalTrims = inactiveBranchModalTrims(excluding: branchPaths)
        return [RoutePathTrim(path: rootPath, keepThrough: .owner)]
        + branchPaths.map {
            RoutePathTrim(path: $0, keepThrough: .owner)
        }
        + inactiveBranchModalTrims.map {
            RoutePathTrim(path: $0.path, keepThrough: $0.keepThrough)
        }
    }

    private func scopedPathTrims(
        from routePath: RoutePath,
        after position: RoutePath.Position
    ) -> [RoutePathTrim] {
        let directlyRemovedScopes = routePath.scopesRemovedAfter(position)
        var ownedPaths: [RoutePath] = []

        for removedScope in directlyRemovedScopes {
            for tree in allTrees {
                ownedPaths.appendUnique(contentsOf: tree.allBranchPaths(under: removedScope))
            }
        }

        if position == .owner,
           let clearedTree = tree(containing: routePath),
           clearedTree.priority != .normal,
           directlyRemovedScopes.isEmpty == false {
            for elevatedTree in elevatedTrees where elevatedTree.priority > clearedTree.priority {
                ownedPaths.appendUnique(contentsOf: [elevatedTree.rootPath])
                ownedPaths.appendUnique(contentsOf: elevatedTree.allBranchPaths())
            }
        }

        for elevatedTree in elevatedTrees {
            guard let originScope = elevatedTree.elevatedOrigin?.scope else {
                continue
            }

            guard directlyRemovedScopes.contains(where: { $0 === originScope }) else {
                continue
            }

            ownedPaths.appendUnique(contentsOf: [elevatedTree.rootPath])
            ownedPaths.appendUnique(contentsOf: elevatedTree.allBranchPaths())
        }

        return [RoutePathTrim(path: routePath, keepThrough: position)]
        + ownedPaths.map {
            RoutePathTrim(path: $0, keepThrough: .owner)
        }
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

    #if DEBUG
    func validateInvariants() {
        var globallyLocatedScopes = Set<ObjectIdentifier>()

        for tree in allTrees {
            var modalScopesByDepth: [Int: RouteScope] = [:]
            precondition(
                tree.rootPath.owner === tree.root,
                "A route tree's root path must be owned by that tree's root scope."
            )
            precondition(
                globallyLocatedScopes.insert(ObjectIdentifier(tree.root)).inserted,
                "A route tree root cannot occupy another structural location."
            )

            for path in tree.allRoutePaths {
                var scopesInPath = Set<ObjectIdentifier>()

                if path !== tree.rootPath {
                    guard let branchScope = path.owner,
                          let branchID = branchScope.branchID,
                          let parent = branchScope.parent
                    else {
                        preconditionFailure("Every non-root path must be owned by a registered branch scope.")
                    }

                    precondition(
                        path === branchScope.path,
                        "A branch path must be the path owned by its branch scope."
                    )
                    precondition(
                        parent.branchScopes[branchID] === branchScope,
                        "A branch scope's parent registration must match its branch identity."
                    )
                    precondition(
                        globallyLocatedScopes.insert(ObjectIdentifier(branchScope)).inserted,
                        "A branch scope cannot occupy another structural location."
                    )
                }

                for scope in path.scopes {
                    let scopeID = ObjectIdentifier(scope)
                    precondition(
                        scopesInPath.insert(scopeID).inserted,
                        "A route scope cannot appear more than once in the same route path."
                    )
                    precondition(
                        globallyLocatedScopes.insert(scopeID).inserted,
                        "A route scope cannot belong to multiple structural locations."
                    )
                    precondition(
                        scope.owningPath === path,
                        "A route scope's owning path must match the path that contains it."
                    )

                    guard let declaration = scope.presentationDeclaration,
                          declaration.presentationKind != .push
                    else {
                        continue
                    }

                    let depth = tree.modalDepth(of: scope)
                    precondition(
                        modalScopesByDepth[depth] == nil,
                        "Only one modal may occupy a modal depth in a route tree."
                    )
                    modalScopesByDepth[depth] = scope
                }
            }
        }
    }
    #endif
}

private extension [RoutePath] {
    mutating func appendUnique(contentsOf routePaths: [RoutePath]) {
        for routePath in routePaths where contains(where: { $0 === routePath }) == false {
            append(routePath)
        }
    }
}

private extension [RoutePathTrim] {
    func mergingByPath() -> [RoutePathTrim] {
        var trims: [RoutePathTrim] = []

        for trim in self {
            guard let existingIndex = trims.firstIndex(where: { $0.path === trim.path }) else {
                trims.append(trim)
                continue
            }

            let existing = trims[existingIndex]
            trims[existingIndex] = .init(
                path: existing.path,
                keepThrough: existing.path.shallower(existing.keepThrough, trim.keepThrough)
            )
        }

        return trims
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
