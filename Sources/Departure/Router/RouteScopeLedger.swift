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

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The scope's single source of truth for mounted views and declaration provenance.
/// Environment inheritance supplies a candidate scope, not permission to register in it.
@MainActor
final class RouteScopeLedger {
    enum Ownership: Equatable {
        case pending
        case managed
        case unmanaged
    }

    struct RouteSource {
        let id: AnyHashable?
        let selection: AnyRouteBranchSelection?
        let declarations: [RouteScopeDeclaration]
        let environment: EnvironmentValues
    }

    struct BranchSource {
        let scope: RouteScope
        let environment: EnvironmentValues?
        let presentationHostID: RoutePresentationHostID?
    }

    private(set) var initialID: AnyHashable
    let sourceEnvironment = RouteSourceEnvironment()
    private var baseEnvironment = EnvironmentValues()
    private var routeSources = OrderedStorage<AnyHashable, RouteSource>()
    private var hookSources = OrderedStorage<AnyHashable, [AnyHookDeclaration]>()
    private var branchSources: [AnyHashable: OrderedStorage<ObjectIdentifier, BranchSource>] = [:]

    private(set) var isInstalled = false
    private(set) var hasEverInstalled = false
    private weak var managedView: PlatformView?
    private var managedViewID: UUID?
    private struct WeakAttachment {
        weak var value: RouteScopeAttachment?
    }
    private var attachments: [WeakAttachment] = []
    private var installationWaiters: [CheckedContinuation<Void, Never>] = []
    private var uninstallationWaiters: [CheckedContinuation<Void, Never>] = []

    init(initialID: AnyHashable) {
        self.initialID = initialID
    }

    // The most recently installed or refreshed source replaces the older one as a unit.
    // Keeping earlier sources lets a transient replacement restore them on teardown.
    private var activeRouteSource: RouteSource? { routeSources.values.last }
    var id: AnyHashable { activeRouteSource?.id ?? initialID }
    var selection: AnyRouteBranchSelection? { activeRouteSource?.selection }
    var routeDeclarations: [RouteScopeDeclaration] { activeRouteSource?.declarations ?? [] }
    var hookDeclarations: [AnyHookDeclaration] { hookSources.values.last ?? [] }

    func updateInitialID(_ id: AnyHashable) {
        initialID = id
    }

    func setRouteSource(_ source: RouteSource, for id: AnyHashable) {
        routeSources.setMostRecent(source, for: id)
        refreshSourceEnvironment()
    }

    @discardableResult
    func removeRouteSource(_ id: AnyHashable) -> Bool {
        guard routeSources[id] != nil else { return false }
        routeSources[id] = nil
        refreshSourceEnvironment()
        return true
    }

    func setHookSource(_ declarations: [AnyHookDeclaration], for id: AnyHashable) {
        hookSources.setMostRecent(declarations, for: id)
    }

    @discardableResult
    func removeHookSource(_ id: AnyHashable) -> Bool {
        guard hookSources[id] != nil else { return false }
        hookSources[id] = nil
        return true
    }

    func setBaseEnvironment(_ environment: EnvironmentValues) {
        baseEnvironment = environment
        refreshSourceEnvironment()
    }

    private func refreshSourceEnvironment() {
        sourceEnvironment.update(activeRouteSource?.environment ?? baseEnvironment)
    }

    func activeBranchSource(for branch: AnyHashable) -> BranchSource? {
        branchSources[branch]?.values.last
    }

    func branches(containing scope: RouteScope) -> [AnyHashable] {
        let scopeID = ObjectIdentifier(scope)
        return branchSources.compactMap { branch, sources in
            sources[scopeID] == nil ? nil : branch
        }
    }

    func setBranchSource(_ source: BranchSource, for branch: AnyHashable) {
        var sources = branchSources[branch] ?? OrderedStorage()
        sources.setMostRecent(source, for: ObjectIdentifier(source.scope))
        branchSources[branch] = sources
    }

    @discardableResult
    func removeBranchSource(_ scope: RouteScope, for branch: AnyHashable) -> Bool {
        guard var sources = branchSources[branch], sources[ObjectIdentifier(scope)] != nil else {
            return false
        }
        sources[ObjectIdentifier(scope)] = nil
        branchSources[branch] = sources.values.isEmpty ? nil : sources
        return true
    }

    func installManagedView(_ view: PlatformView, id: UUID) {
        managedView = view
        managedViewID = id
        reconcileAttachments()
    }

    func uninstallManagedView(id: UUID) {
        guard managedViewID == id else { return }
        managedView = nil
        managedViewID = nil
        reconcileAttachments()
    }

    func ownership(of view: PlatformView) -> Ownership {
        guard let managedView, let managedWindow = managedView.window else {
            return .pending
        }
        if let window = view.window, window !== managedWindow { return .unmanaged }

        #if canImport(UIKit)
        guard let managedController = managedView.departureViewController,
              let candidateController = view.departureViewController else { return .pending }
        let managedRoot = managedController.departurePresentationRoot
        let candidateRoot = candidateController.departurePresentationRoot
        if candidateRoot !== managedRoot && candidateRoot.presentingViewController != nil {
            return .unmanaged
        }
        return view.window == nil ? .pending : .managed
        #else
        return view.window == nil ? .pending : .managed
        #endif
    }

    func observe(_ attachment: RouteScopeAttachment) {
        attachments.removeAll { $0.value == nil }
        guard attachments.contains(where: { $0.value === attachment }) == false else { return }
        attachments.append(WeakAttachment(value: attachment))
    }

    func stopObserving(_ attachment: RouteScopeAttachment) {
        attachments.removeAll { $0.value == nil || $0.value === attachment }
    }

    private func reconcileAttachments() {
        attachments.removeAll { $0.value == nil }
        for attachment in attachments {
            attachment.value?.reconcile()
        }
    }

    func install() {
        guard isInstalled == false else { return }
        isInstalled = true
        hasEverInstalled = true
        resume(&installationWaiters)
    }

    func uninstall() {
        guard isInstalled else { return }
        isInstalled = false
        resume(&uninstallationWaiters)
    }

    func waitUntilInstalled() async {
        guard isInstalled == false else { return }
        await withCheckedContinuation { installationWaiters.append($0) }
    }

    func waitUntilUninstalled() async {
        guard isInstalled else { return }
        await withCheckedContinuation { uninstallationWaiters.append($0) }
    }

    private func resume(_ waiters: inout [CheckedContinuation<Void, Never>]) {
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

@MainActor
final class RouteSourceEnvironment {
    private(set) var values = EnvironmentValues()

    func update(_ values: EnvironmentValues) {
        self.values = values
    }
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
