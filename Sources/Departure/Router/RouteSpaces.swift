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

struct RouteSpaces {
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
        let spacesToRemove: [RouteSpace]

        init(
            pathTrims: [RoutePathTrim],
            spacesToRemove: [RouteSpace] = []
        ) {
            let merged = pathTrims.filter { trim in
                !spacesToRemove.contains { trim.path.owner?.belongs(to: $0) == true }
            }.mergingByPath()
            let detachedScopeIDs = Set(merged.flatMap(\.removedScopes).map(ObjectIdentifier.init))
            self.pathTrims = merged.filter { trim in
                var ancestor = trim.path.owner
                while let scope = ancestor {
                    if detachedScopeIDs.contains(ObjectIdentifier(scope)) { return false }
                    ancestor = scope.previousScopeInSpace
                }
                return true
            }
            // Descendants leave with their owner. Enumerate them for snapshots and
            // completion, without turning each outgoing path into another mutation.
            let outgoingPaths = self.pathTrims.flatMap { trim in
                [trim] + trim.removedScopes.flatMap { $0.branchPaths() }.map {
                    RoutePathTrim(path: $0, keepThrough: .owner)
                }
            } + spacesToRemove.flatMap { space in
                space.allRoutePaths.map { RoutePathTrim(path: $0, keepThrough: .owner) }
            }
            self.preservedPaths = outgoingPaths.map {
                PreservedRoutePath($0.path, after: $0.keepThrough)
            }.filter { $0.scopes.isEmpty == false }
            self.removedScopes = spacesToRemove.map(\.root) + self.preservedPaths.flatMap(\.scopes)
            self.spacesToRemove = spacesToRemove
        }
    }

    indirect enum UnwindPlanRequest {
        case root(RouteSpace)
        case scoped(routePath: RoutePath, after: RoutePath.Position)
        case space(RouteSpace)
        case combined([UnwindPlanRequest])
    }

    let normalSpace: RouteSpace
    var highSpace: RouteSpace?
    var criticalSpace: RouteSpace?

    var activeSpace: RouteSpace {
        criticalSpace ?? highSpace ?? normalSpace
    }

    var allSpaces: [RouteSpace] {
        [normalSpace, highSpace, criticalSpace].compactMap { $0 }
    }

    func space(for priority: RoutePriority) -> RouteSpace? {
        switch priority {
        case .normal:
            normalSpace

        case .high:
            highSpace

        case .critical:
            criticalSpace
        }
    }

    func space(containing routePath: RoutePath) -> RouteSpace? {
        guard let space = routePath.owner?.space, self.space(for: space.priority) === space, space.contains(routePath) else { return nil }
        return space
    }

    func routePath(containing routeScope: RouteScope) -> RoutePath? {
        guard let space = routeScope.space, self.space(for: space.priority) === space else { return nil }
        return space.routePath(containing: routeScope)
    }

    private func inactiveBranchModalTrims(
        in space: RouteSpace, excluding clearedPaths: [RoutePath]
    ) -> [(path: RoutePath, keepThrough: RoutePath.Position)] {
        var handledPaths = Set(clearedPaths.map(ObjectIdentifier.init))
        var trims: [(path: RoutePath, keepThrough: RoutePath.Position)] = []
        do {
            var lane = space.root.lane
            while let modal = lane.modal {
                if let path = modal.owningPath, path.owner?.branchID != nil,
                   handledPaths.insert(ObjectIdentifier(path)).inserted {
                    trims.append((path, path.positionBefore(modal) ?? .owner))
                }
                lane = modal.lane
            }
        }
        return trims
    }

    func unwindPlan(for request: UnwindPlanRequest) -> UnwindPlan {
        switch request {
        case .root(let space):
            let paths = space.activeBranchPaths()
            let trims = [RoutePathTrim(path: space.rootPath, keepThrough: .owner)]
                + paths.map { RoutePathTrim(path: $0, keepThrough: .owner) }
                + inactiveBranchModalTrims(in: space, excluding: paths).map {
                    RoutePathTrim(path: $0.path, keepThrough: $0.keepThrough)
                }
            return UnwindPlan(pathTrims: trims)
        case let .scoped(path, position):
            return UnwindPlan(pathTrims: [.init(path: path, keepThrough: position)])
        case .space(let space):
            return UnwindPlan(pathTrims: [], spacesToRemove: [space])
        case .combined(let requests):
            let plans = requests.map { unwindPlan(for: $0) }
            return UnwindPlan(pathTrims: plans.flatMap(\.pathTrims),
                spacesToRemove: plans.flatMap(\.spacesToRemove))
        }
    }

    func ancestorUnwindResolution(
        from routePath: RoutePath,
        to target: RouterEngine.UnwindTarget?
    ) -> (path: RoutePath, position: RoutePath.Position)? {
        guard case .id = target else {
            return nil
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

    mutating func setElevatedSpace(_ space: RouteSpace?, for priority: RoutePriority) {
        switch priority {
        case .normal:
            return

        case .high:
            highSpace = space

        case .critical:
            criticalSpace = space
        }
    }

    #if DEBUG
    func validateInvariants() {
        var globallyLocatedScopes = Set<ObjectIdentifier>()

        for space in allSpaces {
            precondition(
                space.rootPath.owner === space.root,
                "A route space's root path must be owned by that space's root scope."
            )
            precondition(
                globallyLocatedScopes.insert(ObjectIdentifier(space.root)).inserted,
                "A route space root cannot occupy another structural location."
            )

            for path in space.allRoutePaths {
                if path !== space.rootPath {
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
                        globallyLocatedScopes.insert(scopeID).inserted,
                        "A route scope cannot belong to multiple structural locations."
                    )
                    precondition(
                        scope.owningPath === path,
                        "A route scope's owning path must match the path that contains it."
                    )

                    guard let declaration = scope.presentationDeclaration,
                          declaration.presentationKind.isModal
                    else {
                        continue
                    }

                    precondition(
                        scope.previousRouteScope?.lane.modal === scope && scope.lane !== scope.previousRouteScope?.lane,
                        "A modal occupies its presenting lane's slot and opens a child lane."
                    )
                }
            }
        }
    }
    #endif
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

extension RouteSpaces {
    enum PresentationTransition {
        case append
        case keepEquivalent(through: RoutePath.Position)
    }

    func presentationTransitionPlan(
        after match: RouterEngine.DeclarationMatch,
        transition: PresentationTransition
    ) -> UnwindPlan {
        var requests: [UnwindPlanRequest] = []

        switch transition {
        case .keepEquivalent(let targetPosition):
            requests.append(.scoped(
                routePath: match.presentationLocation.path,
                after: targetPosition
            ))

        case .append where !match.declaration.presentationKind.isModal:
            requests.append(.scoped(
                routePath: match.presentationLocation.path,
                after: match.presentationLocation.position
            ))

        case .append:
            guard let presentationOrigin = match.presentationLocation.scope else {
                break
            }

            if let modal = presentationOrigin.lane.modal, let path = modal.owningPath {
                requests.append(.scoped(routePath: path, after: path.positionBefore(modal) ?? .owner))
            }
        }

        if match.presentationLocation.path !== match.declarationLocation.path {
            requests.append(.scoped(
                routePath: match.declarationLocation.path,
                after: match.declarationLocation.position
            ))
        }

        return unwindPlan(for: .combined(requests))
    }

    func firstDeclaration(including routeType: any Route.Type, origin: RouteRequestOrigin? = nil) -> DeclarationBinding<RouterEngine.DeclarationMatch>? {
        let origin = origin ?? RouteRequestOrigin(scope: activeSpace.currentRouteScope)
        if let match = scopedDeclaration(including: routeType, origin: origin) { return match }
        // The owner's entry catalog is independent of every live navigation tree.
        // Only elevated definitions are visible across the space boundary.
        guard let binding = normalSpace.root.firstRouteAttachment(for: routeType) else { return nil }
        guard let attachment = binding.declaration else { return .conflict }
        guard attachment.declaration.priority != .normal else { return nil }
        return .declared(RouterEngine.DeclarationMatch(
            presentationLocation: .init(path: normalSpace.rootPath, position: .owner),
            space: normalSpace, declarationLocation: .init(path: normalSpace.rootPath, position: .owner),
            branchID: nil, declaration: attachment.declaration,
            lookupStrategy: .normalRootDeclarations))
    }

    private func declarationMatch(
        _ attachment: RouteScope.RouteAttachmentMatch,
        under routeScope: RouteScope,
        space: RouteSpace,
        declaringPath: RoutePath,
        declaringPosition: RoutePath.Position,
        lookupStrategy: RouterEngine.DeclarationMatch.LookupStrategy
    ) -> RouterEngine.DeclarationMatch {
        if attachment.branchID == nil, let branch = routeScope.branchID, let parent = routeScope.parent,
           let parentPath = space.routePath(containing: parent) {
            return declarationMatch(.init(branchID: branch, declaration: attachment.declaration),
                under: parent, space: space, declaringPath: parentPath,
                declaringPosition: parentPath.position(of: parent) ?? .owner,
                lookupStrategy: lookupStrategy)
        }
        let presentationLocation = routePath(
            for: attachment,
            under: routeScope,
            space: space,
            fallbackPath: declaringPath,
            fallbackPosition: declaringPosition
        )

        return RouterEngine.DeclarationMatch(
            routePath: presentationLocation,
            space: space,
            declaringPath: declaringPath,
            declaringPosition: declaringPosition,
            attachment: attachment,
            lookupStrategy: lookupStrategy
        )
    }

    private func routePath(
        for match: RouteScope.RouteAttachmentMatch,
        under routeScope: RouteScope,
        space: RouteSpace,
        fallbackPath: RoutePath,
        fallbackPosition: RoutePath.Position
    ) -> (path: RoutePath, position: RoutePath.Position) {
        switch match.presentationAnchor {
        case .declarationLocation:
            return (path: fallbackPath, position: fallbackPosition)

        case .branchOwner:
            guard let branchID = match.branchID else {
                return (path: fallbackPath, position: fallbackPosition)
            }

            return routePath(
                forBranch: branchID,
                under: routeScope,
                declaration: match.declaration,
                fallbackPath: fallbackPath,
                fallbackPosition: fallbackPosition
            )

        case .activeLocalScope:
            guard
                let branchID = match.branchID,
                let activeLocalScope = routeScope.branchScopes[branchID]?.activeLocalScope,
                let activeLocalPath = space.routePath(containing: activeLocalScope)
            else {
                return (path: fallbackPath, position: fallbackPosition)
            }

            return (
                path: activeLocalPath,
                position: activeLocalPath.position(of: activeLocalScope) ?? .owner
            )
        }
    }

    private func routePath(
        forBranch branchID: AnyHashable,
        under routeScope: RouteScope,
        declaration: AnyRouteDeclaration,
        fallbackPath: RoutePath,
        fallbackPosition: RoutePath.Position
    ) -> (path: RoutePath, position: RoutePath.Position) {
        guard let branchScope = routeScope.branchScopes[branchID] else {
            return (path: fallbackPath, position: fallbackPosition)
        }

        return (path: branchScope.path, position: .owner)
    }


}

private extension RouteSpaces {
    func scopedDeclaration(including routeType: any Route.Type, origin: RouteRequestOrigin) -> DeclarationBinding<RouterEngine.DeclarationMatch>? {
        guard var source = origin.resolve(in: self) else { return nil }
        while let path = routePath(containing: source), let space = space(containing: path) {
            if origin.branches.isEmpty,
               let binding = source.firstBranchScopeRouteAttachment(for: routeType, in: source.activeBranch) {
                return binding.map { declarationMatch($0, under: source, space: space,
                    declaringPath: path, declaringPosition: path.position(of: source) ?? .owner,
                    lookupStrategy: .normalRootActiveBranchScope) }
            }
            // Plain requests can discover branch maps while climbing out of their
            // local scope. Explicit branch handles keep their chosen search boundary.
            if let binding = source.firstRouteAttachment(for: routeType,
                includingOtherBranches: origin.branches.isEmpty) {
                return binding.map { declarationMatch($0, under: source, space: space,
                    declaringPath: path, declaringPosition: path.position(of: source) ?? .owner,
                    lookupStrategy: source === normalSpace.root ? .normalRootDeclarations : .currentPath(spacePriority: space.priority)) }
            }
            guard let previous = enclosingScope(before: source) else { break }
            source = previous
        }
        return nil
    }
}

extension RouteSpaces {
    /// Navigation ancestry never crosses a priority space boundary.
    func enclosingScope(before scope: RouteScope) -> RouteScope? {
        scope.previousScopeInSpace
    }
}
