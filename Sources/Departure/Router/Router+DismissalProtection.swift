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

extension RouterEngine {
    /// Protection follows the same model projection exposed as routePhase.
    var protectedScopes: [RouteScope] {
        tree.allRoutePaths.flatMap(\.scopes).filter {
            $0.presentationDeclaration?.isDismissalProtected == true && routePhase(for: $0) == .active
        }
    }

    func permitsLocalCommand(from source: RouteScope) -> Bool {
        protectedScopes.allSatisfy { protected in
            source.ancestry.contains { $0 === protected }
        }
    }

    func permitsRemoval(_ plan: RouteTree.UnwindPlan, explicitlyDismissing target: RouteScope? = nil) -> Bool {
        let removed = Set(plan.removedScopes.map(ObjectIdentifier.init))
        return protectedScopes.allSatisfy { protected in
            protected === target || !protected.ancestry.contains { removed.contains(ObjectIdentifier($0)) }
        }
    }

    func permitsPresentation(_ match: ResolvedRouteTarget) -> Bool {
        if match.declaration.isGlobal { return true }
        return protectedScopes.allSatisfy { protected in
            match.presentingScope.ancestry.contains { $0 === protected }
                && match.declaringScope.ancestry.contains { $0 === protected }
        }
    }

    func declarationIsCurrent(_ match: ResolvedRouteTarget) -> Bool {
        let definitions = match.declaration.isGlobal ? root.definitions.globals : match.presentingScope.definitions
        return definitions?.routeBinding(for: match.declaration.routeType)?.declaration == match.declaration
    }

    func declaration(for route: any Route, origin: RouteRequestOrigin) -> DeclarationBinding<ResolvedRouteTarget>? {
        let type = type(of: route)
        if let global = root.definitions.globals?.routeBinding(for: type) {
            return global.map { declaration in
                let foreground = currentRouteScope
                @MainActor func target(at anchor: RouteScope) -> ResolvedRouteTarget {
                    ResolvedRouteTarget(tree: tree, presentingScope: anchor, declaringScope: anchor,
                        declaration: declaration, lookupStrategy: .global)
                }
                // Reuse an equal occurrence in the foreground ancestry, just as
                // local routing does. Reaching the global catalog itself never
                // requires cutting navigation back to the application root.
                if let equal = foreground.ancestry.first(where: {
                    $0.presentationDeclaration == declaration && $0.route?._isEqual(to: route) == true
                }), let presenter = equal.presentationOrigin {
                    let match = target(at: presenter)
                    if permitsRemoval(tree.presentationUnwindPlan(after: match, retaining: equal)) { return match }
                }
                // A new value for the currently presented global replaces that
                // occurrence in its existing slot, retaining the invoking flow.
                if foreground.presentationDeclaration == declaration, let presenter = foreground.presentationOrigin {
                    let match = target(at: presenter)
                    if permitsRemoval(tree.presentationUnwindPlan(after: match)) { return match }
                }
                // A protected foreground cannot be removed incidentally, even to
                // reuse another global. The global exception can still place a
                // fresh occurrence above it and let phase determine protection.
                return target(at: foreground)
            }
        }
        // Covered callers may request a declaration belonging to the protected
        // foreground. Their own ancestor maps must not override that declaration.
        for protected in protectedScopes {
            if let match = tree.firstDeclaration(including: type, origin: RouteRequestOrigin(scope: protected)),
               let declaration = match.declaration, permitsPresentation(declaration) {
                return match
            }
        }
        return tree.firstDeclaration(including: type, origin: origin)
    }

    func permitsNativeDismissal(of scope: RouteScope) -> Bool {
        guard tree.routePath(containing: scope) != nil,
              let retained = scope.routePath.scope(before: scope) else { return false }
        return permitsRemoval(RouteTree.UnwindPlan(retaining: [retained]), explicitlyDismissing: scope)
    }

    func protectsNativePresentation(_ scope: RouteScope) -> Bool {
        protectedScopes.contains { protected in protected.ancestry.contains { $0 === scope } }
    }
}
