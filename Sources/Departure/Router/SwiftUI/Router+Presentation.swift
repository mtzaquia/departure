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
    let sourceEnvironment: EnvironmentValues
    init(scope: RouteScope, sourceEnvironment: EnvironmentValues = EnvironmentValues()) {
        self.scope = scope
        self.sourceEnvironment = sourceEnvironment
    }
    var id: AnyHashable { ObjectIdentifier(scope) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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
        let expectedID = resolvePresentation(for: target, matching: style)?.id
        return Binding(
            get: { self.resolvePresentation(for: target, matching: style) },
            set: { value in
                guard value == nil, let expectedID,
                      self.resolvePresentation(for: target, matching: style)?.id == expectedID else { return }
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
        resolvePresentation(for: .local(scope, host), matching: style)
    }
    func elevatedRoutePresentation(priority: RoutePriority, matching style: RoutePresentationKind) -> PresentedRoute? {
        resolvePresentation(for: .priority(priority), matching: style)
    }

    private func resolvePresentation(for target: PresentationTarget, matching style: RoutePresentationKind?) -> PresentedRoute? {
        switch target {
        case let .priority(priority):
            guard let space = spaces.space(for: priority),
                  priority != .default, let metadata = space.root.presentation,
                  style == nil || metadata.declaration.presentationKind == style else { return nil }
            return PresentedRoute(scope: space.root, sourceEnvironment: metadata.sourceEnvironment.values)

        case let .local(host, hostID):
            guard !host.hasConflictingPresentationHosts, let style, host.canDrivePresentation(matching: style),
                  hostID == nil || host.presentationHostID == hostID else { return nil }
            if let path = spaces.routePath(containing: host),
               let scope = path.scopes.first(where: { $0.attachedPresentationDeclaration(presentedBy: host, matching: style, hostedBy: hostID) != nil }),
               shouldHostLocally(scope) {
                return PresentedRoute(scope: scope, sourceEnvironment: host.sourceEnvironment)
            }
            guard host !== root, let outgoing = outgoingPresentation(for: PresentationKey(host, style)),
                  outgoing.retainsBinding else { return nil }
            return outgoing.presentation
        }
    }

    func pushPresentationDismissalDisablesAnimations(from scope: RouteScope?, hostedBy hostID: RoutePresentationHostID? = nil) -> Bool {
        let scope = scope ?? root
        guard hostID == nil || scope.presentationHostID == hostID else { return false }
        return outgoingPresentation(for: PresentationKey(scope, .push))?.disablesAnimation == true
    }

    func shouldHostLocally(_ scope: RouteScope) -> Bool {
        guard let declaration = scope.presentationDeclaration, let space = scope.space else { return false }
        return declaration.priority <= space.priority
    }

    /// A native owner ending an exact live occurrence is authoritative even when covered.
    /// Generic destination-view teardown has no navigation authority.
    func nativePresentationDidDismiss(_ scope: RouteScope) {
        guard spaces.routePath(containing: scope) != nil, let space = scope.space,
              scope.presentationDeclaration?.presentationKind.isModal == true else { return }
        let plan: RouteSpaces.UnwindPlan
        let retained: RouteScope?
        if scope === space.root {
            guard space.priority != .default else { return }
            plan = RouteSpaces.UnwindPlan(removing: [space])
            retained = nil
        } else {
            guard let previous = scope.routePath.scope(before: scope) else { return }
            plan = RouteSpaces.UnwindPlan(retaining: [previous])
            retained = previous
        }
        performPresentationDismissalUnwind(for: scope, in: retained, plan: plan, nativeOwner: true)
    }

    private func dismissPresentation(for target: PresentationTarget, matching style: RoutePresentationKind?) {
        guard let presentation = resolvePresentation(for: target, matching: style) else { return }
        let scope = presentation.scope
        guard isNavigationEligible(scope), let declaration = scope.presentationDeclaration else { return }
        if ios17NavigationStackPushWorkaround?.interceptDismissal(of: presentation,
            matching: declaration.presentationKind, in: self) == true { return }
        let plan: RouteSpaces.UnwindPlan
        let retained: RouteScope?
        switch target {
        case .local:
            guard let previous = scope.routePath.scope(before: scope) else { return }
            plan = RouteSpaces.UnwindPlan(retaining: [previous])
            retained = previous
        case let .priority(priority):
            guard let space = spaces.space(for: priority) else { return }
            plan = RouteSpaces.UnwindPlan(removing: [space])
            retained = nil
        }
        performPresentationDismissalUnwind(for: scope, in: retained, plan: plan)
    }
}
