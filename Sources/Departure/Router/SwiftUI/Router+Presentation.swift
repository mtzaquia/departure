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
    var id: ObjectIdentifier { ObjectIdentifier(scope) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension RouterEngine {
    struct PresentationKey: Hashable {
        let host: ObjectIdentifier
        let style: RoutePresentationKind
        init(_ host: RouteScope, _ style: RoutePresentationKind) {
            self.host = ObjectIdentifier(host)
            self.style = style
        }
    }

    func routePresentationBinding(from scope: RouteScope?, matching style: RoutePresentationKind,
                                  hostedBy host: RoutePresentationHostID? = nil) -> Binding<PresentedRoute?> {
        let scope = scope ?? root
        // Establish observation before the binding closures are evaluated by SwiftUI.
        _ = tree.routePath(containing: scope)?.scopes
        if scope !== root { _ = scope.path.scopes }
        let expectedID = routePresentation(from: scope, matching: style, hostedBy: host)?.id
        return Binding(
            get: { self.routePresentation(from: scope, matching: style, hostedBy: host) },
            set: { value in
                guard value == nil, let expectedID,
                      let presentation = self.routePresentation(from: scope, matching: style, hostedBy: host),
                      presentation.id == expectedID else { return }
                self.dismissPresentation(presentation)
            }
        )
    }

    func routePresentation(from host: RouteScope, matching style: RoutePresentationKind,
                           hostedBy hostID: RoutePresentationHostID? = nil) -> PresentedRoute? {
        guard !host.hasConflictingPresentationHosts, host.canDrivePresentation(matching: style),
              hostID == nil || host.presentationHostID == hostID else { return nil }
        if let path = tree.routePath(containing: host),
           let scope = path.scopes.first(where: {
               $0.attachedPresentationDeclaration(presentedBy: host, matching: style, hostedBy: hostID) != nil
           }) {
            return PresentedRoute(scope: scope)
        }
        guard host !== root, let outgoing = outgoingPresentation(for: PresentationKey(host, style)),
              outgoing.retainsBinding else { return nil }
        return outgoing.presentation
    }

    func pushPresentationDismissalDisablesAnimations(from scope: RouteScope?, hostedBy hostID: RoutePresentationHostID? = nil) -> Bool {
        let scope = scope ?? root
        guard hostID == nil || scope.presentationHostID == hostID else { return false }
        return outgoingPresentation(for: PresentationKey(scope, .push))?.disablesAnimation == true
    }

    /// Reconciles the exact occurrence removed by its native owner. Destination views
    /// decide whether interactive dismissal is available and which routing commands to issue.
    func nativePresentationDidDismiss(_ scope: RouteScope) {
        guard scope.belongs(to: tree), scope.presentationDeclaration?.presentationKind.isModal == true,
              let retained = scope.routePath.scope(before: scope) else { return }
        performPresentationDismissalUnwind(for: scope, in: retained,
            plan: RouteTree.UnwindPlan(retaining: [retained]))
    }

    private func dismissPresentation(_ presentation: PresentedRoute) {
        let scope = presentation.scope
        guard scope.belongs(to: tree), let declaration = scope.presentationDeclaration else { return }
        if ios17NavigationStackPushWorkaround?.interceptDismissal(of: presentation,
            matching: declaration.presentationKind, in: self) == true { return }
        guard let retained = scope.routePath.scope(before: scope) else { return }
        performPresentationDismissalUnwind(for: scope, in: retained,
            plan: RouteTree.UnwindPlan(retaining: [retained]))
    }
}
