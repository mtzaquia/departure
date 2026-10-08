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

import SwiftUI

struct PresentedRoute: Identifiable, Hashable {
    let scope: RouteScope
    let declaration: AnyRouteDeclaration
    let sourceEnvironment: EnvironmentValues
    init(scope: RouteScope, declaration: AnyRouteDeclaration, sourceEnvironment: EnvironmentValues = EnvironmentValues()) {
        self.scope = scope
        self.declaration = declaration
        self.sourceEnvironment = sourceEnvironment
    }
    var id: AnyHashable { ObjectIdentifier(scope) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ResolvedRoutePresentation {
    let presentation: PresentedRoute
    let routePath: RoutePath
    let isLive: Bool
}

extension RouterEngine {
    enum PresentationTarget {
        case local(RouteScope, RoutePresentationHostID?)
        case priority(RoutePriority)
    }

    struct PresentationKey: Hashable {
        let host: ObjectIdentifier
        let style: RoutePresentationKind
        init(_ host: RouteScope, _ style: RoutePresentationKind) {
            self.host = ObjectIdentifier(host)
            self.style = style
        }
    }

    func presentationBinding(for target: PresentationTarget, matching style: RoutePresentationKind? = nil) -> Binding<PresentedRoute?> {
        // Establish observation before the binding closures are evaluated by SwiftUI.
        switch target {
        case let .local(scope, _):
            _ = spaces.routePath(containing: scope)?.scopes
            if scope !== root { _ = scope.path.scopes }
        case let .priority(priority):
            _ = spaces.space(for: priority)?.rootPath.scopes
        }
        let expectedID = resolvePresentation(for: target, matching: style)?.presentation.id
        return Binding(
            get: { self.resolvePresentation(for: target, matching: style)?.presentation },
            set: { value in
                guard value == nil, let expectedID,
                      self.resolvePresentation(for: target, matching: style)?.presentation.id == expectedID else { return }
                self.dismissPresentation(for: target, matching: style)
            }
        )
    }

    func routePresentationBinding(from scope: RouteScope?, matching style: RoutePresentationKind, hostedBy host: RoutePresentationHostID? = nil) -> Binding<PresentedRoute?> {
        presentationBinding(for: .local(scope ?? root, host), matching: style)
    }
    func elevatedRoutePresentationBinding(priority: RoutePriority, matching style: RoutePresentationKind) -> Binding<PresentedRoute?> {
        presentationBinding(for: .priority(priority), matching: style)
    }
    func routePresentation(from scope: RouteScope, matching style: RoutePresentationKind, hostedBy host: RoutePresentationHostID? = nil) -> PresentedRoute? {
        resolvePresentation(for: .local(scope, host), matching: style)?.presentation
    }
    func elevatedRoutePresentation(priority: RoutePriority, matching style: RoutePresentationKind) -> PresentedRoute? {
        resolvePresentation(for: .priority(priority), matching: style)?.presentation
    }

    private func resolvePresentation(for target: PresentationTarget, matching style: RoutePresentationKind?) -> ResolvedRoutePresentation? {
        switch target {
        case let .priority(priority):
            guard let space = spaces.space(for: priority),
                  priority != .normal, let metadata = space.root.presentation,
                  style == nil || metadata.declaration.presentationKind == style else { return nil }
            return ResolvedRoutePresentation(presentation: PresentedRoute(scope: space.root, declaration: metadata.declaration,
                sourceEnvironment: metadata.sourceEnvironment.values), routePath: space.rootPath, isLive: true)

        case let .local(host, hostID):
            guard let style, host.canDrivePresentation(matching: style),
                  hostID == nil || host.presentationHostID == hostID else { return nil }
            if let path = spaces.routePath(containing: host),
               let scope = path.scopes.first(where: { $0.attachedPresentationDeclaration(presentedBy: host, matching: style, hostedBy: hostID) != nil }),
               let declaration = scope.presentationDeclaration,
               shouldHostLocally(declaration, in: path) {
                return ResolvedRoutePresentation(presentation: PresentedRoute(scope: scope, declaration: declaration,
                    sourceEnvironment: host.sourceEnvironment), routePath: path, isLive: true)
            }
            guard host !== root, let outgoing = unwindPresentationSnapshot?.presentations[PresentationKey(host, style)],
                  outgoing.retainsBinding else { return nil }
            return outgoing.projection
        }
    }

    func pushPresentationDismissalDisablesAnimations(from scope: RouteScope?, hostedBy hostID: RoutePresentationHostID? = nil) -> Bool {
        let scope = scope ?? root
        guard hostID == nil || scope.presentationHostID == hostID else { return false }
        return unwindPresentationSnapshot?.presentations[PresentationKey(scope, .push)]?.disablesAnimation == true
    }

    func shouldHostLocally(_ declaration: AnyRouteDeclaration, in path: RoutePath) -> Bool {
        guard let space = path.owner?.space else { return false }
        return declaration.priority <= space.priority
    }

    func dismissPresentation(from scope: RouteScope, matching style: RoutePresentationKind, hostedBy hostID: RoutePresentationHostID?) {
        dismissPresentation(for: .local(scope, hostID), matching: style)
    }
    func dismissElevatedPresentation(priority: RoutePriority, matching style: RoutePresentationKind) {
        dismissPresentation(for: .priority(priority), matching: style)
    }

    private func dismissPresentation(for target: PresentationTarget, matching style: RoutePresentationKind?) {
        guard let projection = resolvePresentation(for: target, matching: style), projection.isLive else { return }
        let scope = projection.presentation.scope
        guard isNavigationEligible(scope) else { return }
        if ios17NavigationStackPushWorkaround?.interceptDismissal(of: projection.presentation,
            matching: projection.presentation.declaration.presentationKind, in: self) == true { return }
        let plan: RouteSpaces.UnwindPlan
        let retained: RouteScope?
        switch target {
        case .local:
            guard let position = projection.routePath.positionBefore(scope) else { return }
            plan = spaces.unwindPlan(for: .scoped(routePath: projection.routePath, after: position))
            retained = projection.routePath.scope(at: position)
        case let .priority(priority):
            guard let space = spaces.space(for: priority) else { return }
            plan = spaces.unwindPlan(for: .space(space))
            retained = nil
        }
        performPresentationDismissalUnwind(for: scope, in: retained, plan: plan)
    }
}
