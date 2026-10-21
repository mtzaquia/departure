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

public extension View {
    /// Connects presentation at this view to the current mapped scope.
    func routing() -> some View { modifier(RoutingModifier()) }

    /// Connects a branch's content to its predefined scope.
    func routing<Branch: Hashable & Sendable>(_ branch: Branch) -> some View {
        modifier(BranchRoutingModifier(branch: AnyHashable(branch)))
    }

    /// Connects a branch container's presentation and selection to its mapped scope.
    /// Use exactly one selection binding per container. Its `Branch` values must
    /// be representable by the binding's selection type.
    func routing<Selection: Hashable & Sendable>(branch selection: Binding<Selection>) -> some View {
        modifier(RoutingModifier(selection: AnyRouteBranchSelection(selection)))
    }
}

extension View {
    func routingAutomatically(nativePresentation: NativePresentationLifetime? = nil,
                              windowDestinationBuilder: WindowDestinationBuilder? = nil) -> some View {
        modifier(RoutingModifier(automatic: true, nativePresentation: nativePresentation,
                                 windowDestinationBuilder: windowDestinationBuilder))
    }
}

private struct RoutingModifier: ViewModifier {
    @RouterEnvironment private var router
    @Environment(\.routeScope) private var scope
    @Environment(\.self) private var environment
    var automatic = false
    var selection: AnyRouteBranchSelection?
    weak var nativePresentation: NativePresentationLifetime?
    var windowDestinationBuilder: WindowDestinationBuilder?
    @State private var hostID = RoutePresentationHostID()
    @State private var attachment = RouteScopeAttachment(kind: .routing)

    func body(content: Content) -> some View {
        let owns = scope?.presentationHostID == hostID
        let pushHostIdentity = scope?.branchID.map {
            router.ios17NavigationStackPushWorkaround?.pushHostIdentity(for: $0, in: scope?.parent, router: router) ?? true
        } ?? true
        let styles = owns ? scope?.definitions.presentationStyles ?? [] : []
        content
            .modifier(ReplacePresentationStyleModifier(presentationHostID: hostID, isEnabled: styles.contains(.replace)))
            .background {
                Color.clear.frame(width: 0, height: 0)
                    .routePresentationStyleModifiers(for: styles, hostedBy: hostID, pushHostIdentity: pushHostIdentity)
            }
            .onLifecycleEvent { view, id, event in
                if automatic, let scope {
                    if let windowDestinationBuilder { router.windowDestinationBuilder = windowDestinationBuilder }
                    // Keep the shared anchor at the outer routing boundary: modal creation
                    // must not wait for nested navigation backgrounds to materialize.
                    router.handleHostEvent(event, scope: scope, view: view, id: id)
                    nativePresentation?.handleDestinationEvent(event, of: ObjectIdentifier(scope))
                }
                attachment.handle(event, id: id, target: scope, view: view,
                    apply: { scope in
                        scope.bindRoutingHost(hostID, automatic: automatic, environment: environment, selection: selection)
                        reconcileSelection(in: scope)
                    }, remove: { scope in
                        scope.unbindRoutingHost(hostID)
                        reconcileSelection(in: scope, restoring: true)
                    })
            }
            .onChange(of: selection?.value(), initial: true) { _, _ in
                guard let scope else { return }
                reconcileSelection(in: scope, deferred: false)
            }
    }

    private func reconcileSelection(in scope: RouteScope, restoring: Bool = false, deferred: Bool = true) {
        guard selection != nil, scope.needsBranchSelectionSynchronization else { return }
        let router = router, owner = hostID
        if !deferred {
            router.synchronizeBranchSelection(ownedBy: owner, in: scope, restoring: restoring)
            return
        }
        // Native updates can be inside SwiftUI's transaction; reconcile the live
        // registration after leaving that callback, without retaining a departed host.
        Task { @MainActor [weak router, weak scope] in
            guard let router, let scope, scope.needsBranchSelectionSynchronization else { return }
            router.synchronizeBranchSelection(ownedBy: owner, in: scope, restoring: restoring)
        }
    }
}

private struct BranchRoutingModifier: ViewModifier {
    let branch: AnyHashable
    @RouterEnvironment private var router
    @Environment(\.routeScope) private var parent
    func body(content: Content) -> some View {
        if let scope = parent?.branchScopes[branch] {
            content
                .routingAutomatically()
                .routeScopeEnvironment(scope, router: router)
        } else {
            content
        }
    }
}
