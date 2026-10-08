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

    let defaultSpace: RouteSpace
    var highSpace: RouteSpace?
    var criticalSpace: RouteSpace?

    var activeSpace: RouteSpace {
        criticalSpace ?? highSpace ?? defaultSpace
    }

    var allSpaces: [RouteSpace] {
        [defaultSpace, highSpace, criticalSpace].compactMap { $0 }
    }

    func space(for priority: RoutePriority) -> RouteSpace? {
        switch priority {
        case .default:
            defaultSpace

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
        case .default:
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
        after match: RouterEngine.ResolvedRouteTarget,
        transition: PresentationTransition
    ) -> UnwindPlan {
        var requests: [UnwindPlanRequest] = []

        switch transition {
        case .keepEquivalent(let targetPosition):
            requests.append(.scoped(
                routePath: match.presentationPath,
                after: targetPosition
            ))

        case .append where !match.declaration.presentationKind.isModal:
            requests.append(.scoped(
                routePath: match.presentationPath,
                after: match.presentationPosition
            ))

        case .append:
            let presentationOrigin = match.presentingScope

            if let modal = presentationOrigin.lane.modal, let path = modal.owningPath {
                requests.append(.scoped(routePath: path, after: path.positionBefore(modal) ?? .owner))
            }
        }

        if match.presentationPath !== match.declaringPath {
            requests.append(.scoped(
                routePath: match.declaringPath,
                after: match.declaringPosition
            ))
        }

        return unwindPlan(for: .combined(requests))
    }

    func firstDeclaration(including routeType: any Route.Type, origin: RouteRequestOrigin? = nil) -> DeclarationBinding<RouterEngine.ResolvedRouteTarget>? {
        let origin = origin ?? RouteRequestOrigin(scope: activeSpace.currentRouteScope)
        if let match = scopedDeclaration(including: routeType, origin: origin) { return match }
        // The owner's entry catalog is independent of every live navigation tree.
        // Only elevated definitions are visible across the space boundary.
        guard let binding = defaultSpace.root.firstRouteAttachment(for: routeType) else { return nil }
        guard let attachment = binding.declaration else { return .conflict }
        guard attachment.declaration.priority != .default else { return nil }
        return binding
    }
}


private extension RouteSpaces {
    func scopedDeclaration(including routeType: any Route.Type, origin: RouteRequestOrigin) -> DeclarationBinding<RouterEngine.ResolvedRouteTarget>? {
        guard var source = origin.resolve(in: self) else { return nil }
        while let path = routePath(containing: source), let space = space(containing: path) {
            if origin.branches.isEmpty,
               let binding = source.firstBranchScopeRouteAttachment(for: routeType, in: source.activeBranch) {
                return binding
            }
            // Plain requests can discover branch maps while climbing out of their
            // local scope. Explicit branch handles keep their chosen search boundary.
            if let binding = source.firstRouteAttachment(for: routeType,
                includingOtherBranches: origin.branches.isEmpty,
                lookupStrategy: source === defaultSpace.root ? .defaultRootDeclarations : .currentPath(spacePriority: space.priority)) {
                return binding
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
