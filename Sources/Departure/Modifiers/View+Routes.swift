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
    func routingAutomatically() -> some View { modifier(RoutingModifier(automatic: true)) }
}

private struct RoutingModifier: ViewModifier {
    @RouterEnvironment private var router
    @Environment(\.routeScope) private var scope
    @Environment(\.self) private var environment
    var automatic = false
    var selection: AnyRouteBranchSelection?
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
                    .onLifecycleEvent { view, _, event in
                        switch event {
                        case .installedInWindow, .updated(isInstalledInWindow: true):
                            guard let view else { return }
                            attachment.update(target: scope, view: view,
                                apply: { scope in
                                    scope.bindRoutingHost(hostID, automatic: automatic, environment: environment, selection: selection)
                                    if selection != nil {
                                        // Representable updates run inside SwiftUI's view update.
                                        // Revalidate the attachment before synchronizing on the next turn.
                                        Task { @MainActor in
                                            router.synchronizeBranchSelection(ownedBy: hostID, in: scope)
                                        }
                                    }
                                },
                                remove: { scope in
                                    scope.unbindRoutingHost(hostID)
                                    if selection != nil {
                                        Task { @MainActor in router.restoreBranchSelection(in: scope) }
                                    }
                                })
                        case .updated(isInstalledInWindow: false): break
                        case .dismantled, .deinitialized:
                            attachment.detach()
                        }
                    }
            }
            .onChange(of: selection?.value(), initial: true) { _, _ in
                guard let scope else { return }
                router.synchronizeBranchSelection(ownedBy: hostID, in: scope)
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
                .onLifecycleEvent { view, id, event in
                    switch event {
                    case .installedInWindow, .updated(isInstalledInWindow: true):
                        guard let view else { return }
                        router.hostDidAttach(scope, view: view, id: id)
                    case .updated(isInstalledInWindow: false): break
                    case .dismantled, .deinitialized:
                        router.hostDidDetach(scope, id: id)
                    }
                }
        } else {
            content
        }
    }
}
