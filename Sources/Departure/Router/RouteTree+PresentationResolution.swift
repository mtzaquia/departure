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

extension RouteTree {
    func resolvePresentation(
        of route: any Route, from source: RouteScope? = nil, includingBranches: Bool = true
    ) -> DeclarationBinding<RouterEngine.ResolvedRouteTarget>? {
        guard let candidate = lookupDeclaration(
            for: type(of: route), from: source ?? currentRouteScope, includingBranches: includingBranches
        ) else { return nil }

        return candidate.binding.map { declaration in
            switch candidate.placement {
            case .foreground:
                let presenter = foregroundPresenter(for: route, declaration: declaration)
                return .init(presentingScope: presenter, declaringScope: presenter,
                    declaration: declaration, lookupStrategy: .global)
            case let .scoped(presentingScope, declaringScope, strategy):
                return .init(presentingScope: presentingScope, declaringScope: declaringScope,
                    declaration: declaration, lookupStrategy: strategy)
            }
        }
    }

    func declarationIsCurrent(_ match: RouterEngine.ResolvedRouteTarget) -> Bool {
        let definitions = match.declaration.isGlobal ? root.definitions.globals : match.presentingScope.definitions
        return definitions?.routeBinding(for: match.declaration.routeType)?.declaration == match.declaration
    }

    private func foregroundPresenter(for route: any Route, declaration: AnyRouteDeclaration) -> RouteScope {
        let foreground = currentRouteScope
        let presentingForeground = foreground.ancestry.first { scope in
            // A committed destination can mount through its presenter. An unmounted
            // branch has no presentation origin, so it stops that chain.
            sequence(first: scope) { $0.presentationOrigin }.contains {
                $0.isAvailableForPresentation && $0.presentationHostID != nil
            }
        }
        if presentingForeground == nil {
            log.departureDebug(.globalRouteWithoutPresentationHost(routeType: declaration.routeType))
        }

        // Keep existing occurrences in their slots, including a destination
        // whose native presentation is still mounting.
        let equal = foreground.ancestry.first {
            $0.presentationDeclaration == declaration && $0.route?._isEqual(to: route) == true
        }
        let current = foreground.presentationDeclaration == declaration ? foreground : presentingForeground
        return equal?.presentationOrigin
            ?? (current?.presentationDeclaration == declaration ? current?.presentationOrigin : nil)
            ?? presentingForeground
            ?? foreground
    }

    private func lookupDeclaration(
        for routeType: any Route.Type, from source: RouteScope, includingBranches: Bool
    ) -> PresentationDeclaration? {
        if let binding = root.definitions.globals?.routeBinding(for: routeType) {
            return .init(binding: binding, placement: .foreground)
        }
        // A live scope's ancestors and owned branches stay live throughout this
        // synchronous lookup; no additional membership checks are needed here.
        for scope in source.ancestry {
            if let declaration = lookupScopedDeclaration(at: scope) { return declaration }
        }
        return nil

        // One ordered search reads definitions without constructing intermediate matches.
        // Explicit branch handles omit branch look-forward and sibling fallback.
        func lookupScopedDeclaration(at source: RouteScope) -> PresentationDeclaration? {
            let selectedRoot = source.branchScopes[source.activeBranch]
            let selectedDestination = includingBranches ? selectedRoot?.activeLocalScope : nil
            let locations = [selectedDestination !== selectedRoot ? selectedDestination : nil, source].compactMap { $0 }
            for location in locations {
                let owners = includingBranches && location.branchContainer != nil
                    ? [location.branchScopes[location.activeBranch], location].compactMap { $0 }
                        + location.branchScopes.keys.filter { $0 != location.activeBranch }.compactMap { location.branchScopes[$0] }
                    : [location]
                for owner in owners {
                    guard let binding = owner.definitions.routeBinding(for: routeType) else { continue }
                    let looksForward = location !== source
                    let presentingScope = looksForward ? location : owner
                    let declaringScope = looksForward ? source : (owner.branchID == nil ? owner : owner.parent ?? owner)
                    let strategy: RouterEngine.ResolvedRouteTarget.LookupStrategy = looksForward ? .selectedBranch
                        : source === root ? .rootDeclarations : .currentPath
                    return .init(binding: binding, placement: .scoped(
                        presentingScope: presentingScope, declaringScope: declaringScope, strategy: strategy
                    ))
                }
            }
            return nil
        }
    }
}

private struct PresentationDeclaration {
    enum Placement {
        case foreground
        case scoped(presentingScope: RouteScope, declaringScope: RouteScope,
                    strategy: RouterEngine.ResolvedRouteTarget.LookupStrategy)
    }

    let binding: DeclarationBinding<AnyRouteDeclaration>
    let placement: Placement
}
