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
    }

    struct UnwindPlan {
        let removedScopes: [RouteScope]
        let retainedScopes: [RouteScope]
        let preservedPaths: [PreservedRoutePath]
        let spacesToRemove: [RouteSpace]

        init(retaining scopes: [RouteScope] = [], removing spaces: [RouteSpace] = []) {
            var retained: [RouteScope] = []
            for scope in scopes where !spaces.contains(where: { scope.routePath.owner?.belongs(to: $0) == true }) {
                if let index = retained.firstIndex(where: { $0.routePath === scope.routePath }) {
                    if scope.pathDepth < retained[index].pathDepth { retained[index] = scope }
                } else {
                    retained.append(scope)
                }
            }
            let detachedScopeIDs = Set(retained.flatMap {
                $0.routePath.scopesRemoved(after: $0)
            }.map(ObjectIdentifier.init))
            self.retainedScopes = retained.filter { retainedScope in
                retainedScope.routePath.owner?.ancestry.contains {
                    detachedScopeIDs.contains(ObjectIdentifier($0))
                } != true
            }
            // Descendants leave with their owner. Capture their outgoing paths
            // for snapshots and completion, without adding another tree mutation.
            let outgoingPaths = self.retainedScopes.flatMap { scope in
                let removed = scope.routePath.scopesRemoved(after: scope)
                return [PreservedRoutePath(routePath: scope.routePath, scopes: removed)]
                    + removed.flatMap { $0.branchPaths() }.map {
                        PreservedRoutePath(routePath: $0, scopes: $0.scopes)
                    }
            } + spaces.flatMap { space in
                space.allRoutePaths.map { PreservedRoutePath(routePath: $0, scopes: $0.scopes) }
            }
            self.preservedPaths = outgoingPaths.filter { !$0.scopes.isEmpty }
            self.removedScopes = spaces.map(\.root) + self.preservedPaths.flatMap(\.scopes)
            self.spacesToRemove = spaces
        }
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

    func rootUnwindPlan(in space: RouteSpace) -> UnwindPlan {
        let paths = space.activeBranchPaths()
        var retained = [space.root] + paths.compactMap(\.owner)
        var handledPaths = Set(paths.map(ObjectIdentifier.init))
        var lane = space.root.lane
        while let modal = lane.modal {
            if let path = modal.owningPath, path.owner?.branchID != nil,
               handledPaths.insert(ObjectIdentifier(path)).inserted,
               let previous = modal.previousRouteScope {
                retained.append(previous)
            }
            lane = modal.lane
        }
        return UnwindPlan(retaining: retained)
    }

    func ancestorUnwindScope(from routePath: RoutePath, withID id: AnyHashable) -> RouteScope? {
        var scope = routePath.owner?.parent
        while let ancestor = scope {
            if let target = self.routePath(containing: ancestor)?.scope(withID: id) { return target }
            scope = ancestor.parent
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

extension RouteSpaces {
    func presentationUnwindPlan(
        after match: RouterEngine.ResolvedRouteTarget,
        retaining equivalent: RouteScope? = nil
    ) -> UnwindPlan {
        var retained: [RouteScope] = []
        if let equivalent {
            retained.append(equivalent)
        } else if !match.declaration.presentationKind.isModal {
            retained.append(match.presentingScope)
        } else if let previous = match.presentingScope.lane.modal?.previousRouteScope {
            retained.append(previous)
        }
        if match.presentationPath !== match.declaringPath { retained.append(match.declaringScope) }
        return UnwindPlan(retaining: retained)
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
        guard let originScope = origin.resolve(in: self) else { return nil }
        for source in originScope.ancestry {
            guard let path = routePath(containing: source), let space = space(containing: path) else { break }
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
        }
        return nil
    }
}
