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

final class RouteTree {
    struct PreservedRoutePath {
        let routePath: RoutePath
        let scopes: [RouteScope]
    }

    struct UnwindPlan {
        let removedScopes: [RouteScope]
        let retainedScopes: [RouteScope]
        let preservedPaths: [PreservedRoutePath]

        init(retaining scopes: [RouteScope] = []) {
            var retained: [RouteScope] = []
            for scope in scopes {
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
            }
            self.preservedPaths = outgoingPaths.filter { !$0.scopes.isEmpty }
            self.removedScopes = self.preservedPaths.flatMap(\.scopes)
        }
    }

    let root: RouteScope
    var rootPath: RoutePath { root.path }

    init(
        root: RouteScope
    ) {
        self.root = root
        precondition(root.anchorTree == nil, "A navigation tree owns its root.")
        root.anchorTree = self
    }

    var currentRouteScope: RouteScope {
        guard let modal = currentModalScope else { return root.activeLocalScope }
        return (modal.routePath.last ?? modal).activeLocalScope
    }
    var currentRoutePath: RoutePath { currentRouteScope.routePath }

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

    var currentModalScope: RouteScope? {
        var lane = root.lane
        var foreground: RouteScope?
        while let modal = lane.modal {
            // A deselected branch may retain its outgoing native modal until
            // teardown. Its lane slot remains occupied, but it is no longer a
            // foreground anchor for a new global request or route-phase lookup.
            guard modal.ancestry.allSatisfy({ scope in
                guard let branch = scope.branchID, let owner = scope.previousScopeInTree else { return true }
                return owner.participates(inBranch: branch)
            }) else { break }
            foreground = modal
            lane = modal.lane
        }
        return foreground
    }

    func rootUnwindPlan() -> UnwindPlan {
        let paths = activeBranchPaths()
        var retained = [root] + paths.compactMap(\.owner)
        var handledPaths = Set(paths.map(ObjectIdentifier.init))
        var lane = root.lane
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

    func tree(containing path: RoutePath) -> RouteTree? {
        contains(path) ? self : nil
    }

    func validateInvariants() {
        var globallyLocatedScopes = Set<ObjectIdentifier>()

        precondition(
            rootPath.owner === root,
            "A navigation tree's root path must be owned by that tree's root scope."
        )
        precondition(
            globallyLocatedScopes.insert(ObjectIdentifier(root)).inserted,
            "A navigation tree root cannot occupy another structural location."
        )

        for path in allRoutePaths {
            if path !== rootPath {
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

extension RouteTree {
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
        let origin = origin ?? RouteRequestOrigin(scope: currentRouteScope)
        if let originScope = origin.resolve(in: self) {
            for source in originScope.ancestry {
                guard routePath(containing: source) != nil else { break }
                if let binding = resolveDefinitions(at: source, includingBranches: origin.branches.isEmpty) { return binding }
            }
        }
        return nil

        // One ordered search reads definitions without constructing intermediate matches.
        // Explicit branch handles omit branch look-forward and sibling fallback.
        func resolveDefinitions(at source: RouteScope, includingBranches: Bool,
                                includingSelectedDestination: Bool = true) -> DeclarationBinding<RouterEngine.ResolvedRouteTarget>? {
            guard let tree = source.tree else { return nil }
            let selectedRoot = source.branchScopes[source.activeBranch]
            let selectedDestination = includingBranches && includingSelectedDestination ? selectedRoot?.activeLocalScope : nil
            let locations = [selectedDestination !== selectedRoot ? selectedDestination : nil, source].compactMap { $0 }
            for location in locations where location.tree != nil {
                let owners = includingBranches && location.branchContainer != nil
                    ? [location.branchScopes[location.activeBranch], location].compactMap { $0 }
                        + location.branchScopes.keys.filter { $0 != location.activeBranch }.compactMap { location.branchScopes[$0] }
                    : [location]
                for owner in owners {
                    guard let binding = owner.definitions.routeBinding(for: routeType) else { continue }
                    let looksForward = location !== source
                    let presentingScope = looksForward ? location : owner
                    let declaringScope = looksForward ? source : (owner.branchID == nil ? owner : owner.parent ?? owner)
                    let strategy: RouterEngine.ResolvedRouteTarget.LookupStrategy = looksForward ? .defaultRootActiveBranchScope
                        : source === root ? .defaultRootDeclarations : .currentPath
                    return binding.map { .init(tree: tree, presentingScope: presentingScope,
                        declaringScope: declaringScope, declaration: $0, lookupStrategy: strategy) }
                }
            }
            return nil
        }
    }
}
