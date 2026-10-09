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
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@Observable
final class RouteScope: Identifiable {
    @ObservationIgnored var id: AnyHashable

    @ObservationIgnored let route: (any Route)?
    @ObservationIgnored weak var parent: RouteScope?

    @ObservationIgnored var branchID: AnyHashable?
    @ObservationIgnored private(set) var definitions: RouteDefinitions
    @ObservationIgnored var branchContainer: BranchContainerState?
    @ObservationIgnored var branchScopes = OrderedStorage<AnyHashable, RouteScope>()

    // Physical facts belong to the scope; current projections are derived from them.
    private struct Host {
        private struct Anchor { weak var view: PlatformView? }
        let id: UUID
        private let anchor: Anchor?
        var view: PlatformView? { anchor?.view }
        var isAvailable: Bool { anchor.map { $0.view?.window != nil } ?? true }
        init(id: UUID, view: PlatformView?) {
            self.id = id
            anchor = view.map { Anchor(view: $0) }
        }
    }
    private struct RoutingHost {
        let automatic: Bool
        let environment: EnvironmentValues
        let selection: AnyRouteBranchSelection?
    }
    private struct WeakAttachment { weak var value: RouteScopeAttachment? }
    private struct WeakReadiness { weak var value: RouteScopeReadiness? }
    private struct WeakNativePresentation { weak var value: NativePresentationLifetime? }
    private enum PresentationCompletion {
        case host
        case native(WeakNativePresentation)
    }
    @ObservationIgnored private var presentationCompletion: PresentationCompletion = .host
    @ObservationIgnored private var host: Host?
    @ObservationIgnored private var routingHosts = OrderedStorage<RoutePresentationHostID, RoutingHost>()
    @ObservationIgnored private var hookSources: [AnyHashable: [AnyHookDeclaration]] = [:]
    // Overlapping unwinds share callback entry per receiving scope ID for this route instance.
    @ObservationIgnored var unwindHandlerDeliveries: [AnyHashable: Task<Void, Never>] = [:]
    @ObservationIgnored private var attachments: [WeakAttachment] = []
    @ObservationIgnored private var readinessWaits: [WeakReadiness] = []
    @ObservationIgnored private(set) var hasEverInstalled = false
    @ObservationIgnored let sourceEnvironmentReference = RouteSourceEnvironment()

    @ObservationIgnored lazy var path = RoutePath(owner: self)
    @ObservationIgnored private(set) weak var owningPath: RoutePath?
    @ObservationIgnored private(set) weak var previousRouteScope: RouteScope?
    @ObservationIgnored weak var anchorSpace: RouteSpace?
    @ObservationIgnored private lazy var ownedLane = RouteLane(owner: self)
    private(set) var continuation: RouteScope?

    @ObservationIgnored private(set) var presentation: RouteScopePresentation?

    var isInstalledInView: Bool {
        access(keyPath: \.isInstalledInView)
        return host != nil
    }
    var isAvailableForPresentation: Bool {
        access(keyPath: \.isAvailableForPresentation)
        guard let host else { return false }
        // Model-only hosts have no anchor; a destroyed native anchor remains unavailable.
        return host.isAvailable
    }

    /// Modal completion belongs to its native adapter; pushes use managed-host teardown.
    var isAwaitingPresentationEnd: Bool {
        switch presentationCompletion {
        case .host: isInstalledInView
        case .native(let owner): owner.value?.presentation?.route.scope === self
        }
    }
    func trackNativePresentation(_ owner: NativePresentationLifetime) {
        presentationCompletion = .native(WeakNativePresentation(value: owner))
    }
    func nativePresentationDidEnd() { checkReadiness() }
    func isNativePresentationOwned(by owner: NativePresentationLifetime) -> Bool {
        if case .native(let current) = presentationCompletion { return current.value === owner }
        return false
    }

    var hostID: UUID? { host?.id }
    var sourceEnvironment: EnvironmentValues { sourceEnvironmentReference.values }

    var presentationOrigin: RouteScope? {
        presentation?.origin
    }

    var presentationDeclaration: AnyRouteDeclaration? {
        presentation?.declaration
    }

    init(id: AnyHashable, route: (any Route)?, parent: RouteScope? = nil, definitions: RouteDefinitions = .empty) {
        self.route = route
        self.parent = parent
        self.id = id
        self.definitions = definitions
        useDefinitions(definitions)
    }

    /// Installs the owner's compiled map before any views mount.
    func useDefinitions(_ definitions: RouteDefinitions) {
        self.definitions = definitions
        switch definitions.scopeID {
        case .declared(let id): self.id = id
        case .conflict: self.id = UUID()
        case nil: break
        }
        guard let container = definitions.branchContainer?.declaration else { return }
        for branch in container.branches.keys where branchScopes[branch] == nil {
            guard let definition = container.branches[branch]?.declaration else { continue }
            let scope = RouteScope(id: branch, route: nil, parent: self, definitions: definition)
            scope.branchID = branch
            branchScopes[branch] = scope
            if branchContainer == nil {
                branchContainer = BranchContainerState(selectedBranch: branch)
            }
        }
    }
}

// MARK: - Derived State

extension RouteScope {
    var currentRoute: (any Route)? {
        route ?? parent?.currentRoute
    }

    var routePresentation: RoutePresentation? {
        presentation.map { RoutePresentation(style: $0.declaration.presentationKind, priority: $0.priority) }
    }

    func attachPresentation(
        to origin: RouteScope,
        declaration: AnyRouteDeclaration,
        priority: RoutePriority? = nil
    ) {
        precondition(presentation == nil && owningPath == nil,
                     "A destination's presentation is fixed before it enters navigation state.")
        presentation = RouteScopePresentation(
            origin: origin,
            declaration: declaration,
            priority: priority ?? declaration.priority
        )
    }
}

// MARK: - Presentation Environment

extension RouteScope {
    func updateSourceEnvironment(_ sourceEnvironment: EnvironmentValues) {
        sourceEnvironmentReference.update(sourceEnvironment)
    }
}

// MARK: - X/Y/Z Ownership

extension RouteScope {
    var lane: RouteLane {
        if presentationDeclaration?.presentationKind.isModal == true { return ownedLane }
        return previousRouteScope?.lane ?? parent?.lane ?? ownedLane
    }

    var space: RouteSpace? { anchorSpace ?? previousRouteScope?.space ?? parent?.space }
    var routePath: RoutePath { owningPath ?? path }
    var pathDepth: Int { previousRouteScope.map { $0.pathDepth + 1 } ?? parent?.pathDepth ?? 0 }
    var previousScopeInSpace: RouteScope? { previousRouteScope ?? parent }

    // Includes this scope and follows X/Z ancestry within its space, including outgoing trees.
    var ancestry: some Sequence<RouteScope> {
        sequence(first: self) { $0.previousScopeInSpace }
    }

    func belongs(to space: RouteSpace) -> Bool {
        if self === space.root { return anchorSpace === space }
        if let branchID, let parent {
            return parent.branchScopes[branchID] === self && parent.belongs(to: space)
        }
        guard owningPath != nil, let previousRouteScope,
              previousRouteScope.belongs(to: space) else { return false }
        return previousRouteScope.continuation === self
    }

    func next(in path: RoutePath) -> RouteScope? {
        if let continuation, continuation.owningPath === path { return continuation }
        return nil
    }

    func append(_ scope: RouteScope, in path: RoutePath) {
        precondition(path === path.owner?.path, "Each root or branch has one canonical X path.")
        precondition(scope !== self && scope.anchorSpace == nil && scope.branchID == nil,
                     "Only a destination instance can extend an X path.")
        precondition(scope.owningPath == nil, "A route instance has exactly one owning path.")
        precondition(next(in: path) == nil, "Append begins at the end of its X path.")
        let isModal = scope.presentationDeclaration?.presentationKind.isModal == true
        precondition(continuation == nil && (!isModal || lane.modal == nil),
                     "The owning X continuation or Y modal slot must be vacant.")
        scope.previousRouteScope = self
        scope.owningPath = path
        continuation = scope
        if isModal { lane.present(scope) }
    }

    func removeContinuation(in path: RoutePath) {
        if continuation?.owningPath === path { continuation = nil }
    }

}

// MARK: - Physical Hosting

extension RouteScope {
    enum Ownership: Equatable { case pending, managed, unmanaged }

    @discardableResult
    func attachHost(_ view: PlatformView?, id: UUID) -> Bool {
        let becameReady = host == nil
        withMutation(keyPath: \.isAvailableForPresentation) {
            if becameReady {
                withMutation(keyPath: \.isInstalledInView) { host = Host(id: id, view: view) }
                hasEverInstalled = true
            } else {
                host = Host(id: id, view: view)
            }
        }
        reconcileAttachments()
        checkReadiness()
        return becameReady
    }

    @discardableResult
    func detachHost(id: UUID) -> Bool {
        guard host?.id == id else { return false }
        withMutation(keyPath: \.isAvailableForPresentation) {
            withMutation(keyPath: \.isInstalledInView) { host = nil }
        }
        reconcileAttachments()
        checkReadiness()
        return true
    }

    func hostAvailabilityDidChange(id: UUID) {
        guard host?.id == id else { return }
        withMutation(keyPath: \.isAvailableForPresentation) {}
        reconcileAttachments()
        checkReadiness()
    }

    var presentationHostID: RoutePresentationHostID? {
        access(keyPath: \.presentationHostID)
        return selectedHost(in: routingHosts)
    }

    private func selectedHost(in hosts: OrderedStorage<RoutePresentationHostID, RoutingHost>) -> RoutePresentationHostID? {
        presentationHostBinding(in: hosts)?.declaration
    }

    private func presentationHostBinding(in hosts: OrderedStorage<RoutePresentationHostID, RoutingHost>) -> DeclarationBinding<RoutePresentationHostID>? {
        let explicit = hosts.keys.filter { hosts[$0]?.automatic == false }
        let candidates = explicit.isEmpty ? hosts.keys : explicit
        guard let first = candidates.first else { return nil }
        return candidates.count == 1 ? .declared(first) : .conflict
    }

    var hasConflictingPresentationHosts: Bool {
        if case .conflict? = presentationHostBinding(in: routingHosts) { return true }
        return false
    }

    func bindRoutingHost(_ id: RoutePresentationHostID, automatic: Bool, environment: EnvironmentValues, selection: AnyRouteBranchSelection? = nil) {
        var hosts = routingHosts
        hosts[id] = RoutingHost(automatic: automatic, environment: environment, selection: selection)
        updateRoutingHosts(hosts)
    }

    func unbindRoutingHost(_ id: RoutePresentationHostID) {
        var hosts = routingHosts
        hosts[id] = nil
        updateRoutingHosts(hosts)
    }

    private func updateRoutingHosts(_ hosts: OrderedStorage<RoutePresentationHostID, RoutingHost>) {
        let previouslyConflicted = hasConflictingBranchSelection
        let presentationPreviouslyConflicted = hasConflictingPresentationHosts
        if selectedHost(in: hosts) != selectedHost(in: routingHosts) {
            withMutation(keyPath: \.presentationHostID) { routingHosts = hosts }
        } else {
            routingHosts = hosts
        }
        if let id = selectedHost(in: hosts), let host = hosts[id] {
            sourceEnvironmentReference.update(host.environment)
        }
        if hasConflictingPresentationHosts && !presentationPreviouslyConflicted {
            log.departureWarning(
                "Scope `\(id)` has conflicting presentation hosts. Keep one explicit `.routing()` "
                    + "or `.routing(branch:)` presentation owner in this scope; use `.routing(branchValue)` "
                    + "to enter another branch scope. Automatic hosts are used only without an explicit owner. "
                    + "Presentation is disabled until one owner remains."
            )
        }
        if hasConflictingBranchSelection && !previouslyConflicted {
            log.departureWarning(
                "Scope `\(id)` has multiple `.routing(branch:)` selection owners. "
                    + "Keep exactly one selection binding on this container; "
                    + "use `.routing(branchValue)` on its branch content. "
                    + "Branch selection is disabled until only one owner remains."
            )
        }
    }

    // Selection ownership is a projection of routing attachments, not another registry.
    var hasConflictingBranchSelection: Bool {
        routingHosts.values.lazy.compactMap(\.selection).count > 1
    }

    var branchSelection: AnyRouteBranchSelection? {
        let selections = routingHosts.values.compactMap(\.selection)
        return selections.count == 1 ? selections.first : nil
    }

    func branchSelection(ownedBy id: RoutePresentationHostID) -> AnyRouteBranchSelection? {
        guard !hasConflictingBranchSelection else { return nil }
        return routingHosts[id]?.selection
    }

    func restoreBranchSelection() {
        guard branchContainer != nil else { return }
        for selection in routingHosts.values.compactMap(\.selection) where selection.value() != activeBranch {
            _ = selection.setValue(activeBranch)
        }
    }

    // Sources own captured closures. Resolution is derived, so updates and removal
    // cannot leave a second cache or an implicit mount-order winner behind.
    private var hookBindings: [HookDeclarationIdentity: DeclarationBinding<AnyHookDeclaration>] {
        var bindings: [HookDeclarationIdentity: DeclarationBinding<AnyHookDeclaration>] = [:]
        for declarations in hookSources.values {
            for declaration in declarations {
                let identity = declaration.identity
                bindings[identity] = bindings[identity] == nil ? .declared(declaration) : .conflict
            }
        }
        return bindings
    }

    func hookBinding(for identity: HookDeclarationIdentity, in spaces: RouteSpaces) -> DeclarationBinding<AnyHookDeclaration>? {
        guard spaces.routePath(containing: self) != nil else { return nil }
        return hookBindings[identity]
    }

    func installHookDeclarations(sourceID: AnyHashable = "default", hookDeclarations: [AnyHookDeclaration]) {
        let previous = hookBindings
        hookSources[sourceID] = hookDeclarations
        let updated = hookBindings
        for (identity, binding) in updated {
            guard case .conflict = binding else { continue }
            if case .conflict? = previous[identity] { continue }
            log.departureWarning(
                "Conflicting hook declarations for `\(identity)` in scope `\(id)`; "
                    + "the hook is disabled until only one declaration remains."
            )
        }
    }

    func uninstallHookDeclarations(sourceID: AnyHashable) { hookSources[sourceID] = nil }

    func ownership(of view: PlatformView) -> Ownership {
        guard let managedView = host?.view, let managedWindow = managedView.window else { return .pending }
        if let window = view.window, window !== managedWindow { return .unmanaged }
        #if canImport(UIKit)
        guard let managedController = managedView.departureViewController,
              let candidateController = view.departureViewController else { return .pending }
        let managedRoot = managedController.departurePresentationRoot
        let candidateRoot = candidateController.departurePresentationRoot
        if candidateRoot !== managedRoot && candidateRoot.presentingViewController != nil { return .unmanaged }
        #endif
        return view.window == nil ? .pending : .managed
    }

    func observe(_ attachment: RouteScopeAttachment) {
        attachments.removeAll { $0.value == nil }
        if !attachments.contains(where: { $0.value === attachment }) { attachments.append(.init(value: attachment)) }
    }

    func stopObserving(_ attachment: RouteScopeAttachment) {
        attachments.removeAll { $0.value == nil || $0.value === attachment }
    }

    private func reconcileAttachments() {
        attachments.removeAll { $0.value == nil }
        for attachment in attachments { attachment.value?.reconcile() }
    }

    func observeReadiness(_ readiness: RouteScopeReadiness) {
        readinessWaits.removeAll { $0.value?.isPending != true }
        readinessWaits.append(WeakReadiness(value: readiness))
    }

    private func checkReadiness() {
        readinessWaits.removeAll { $0.value?.isPending != true }
        for waiter in readinessWaits { waiter.value?.checkReadiness() }
    }

    @discardableResult
    func waitUntilInstalled(in engine: RouterEngine? = nil) async -> Bool {
        let eligible: (() -> Bool)? = engine.map { engine in { engine.isNavigationEligible(self) } }
        return await RouteScopeReadiness.wait(in: self, while: eligible) { engine == nil ? self.isInstalledInView : self.isAvailableForPresentation }
    }

    @discardableResult
    func waitUntilPresentationEnded() async -> Bool {
        await RouteScopeReadiness.wait(in: self, cancellable: false) { !self.isAwaitingPresentationEnd }
    }

    @discardableResult
    func waitUntilUninstalled() async -> Bool {
        // Committed teardown owns its lifetime even if the requesting task cancels.
        await RouteScopeReadiness.wait(in: self, cancellable: false) { !self.isInstalledInView }
    }

}

final class RouteSourceEnvironment {
    private(set) var values = EnvironmentValues()
    func update(_ values: EnvironmentValues) { self.values = values }
}

#if canImport(UIKit)
private extension UIView {
    var departureViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}

private extension UIViewController {
    var departurePresentationRoot: UIViewController {
        var controller: UIViewController? = self
        var root = self
        while let current = controller {
            root = current
            controller = current.parent
        }
        return root
    }
}
#endif
