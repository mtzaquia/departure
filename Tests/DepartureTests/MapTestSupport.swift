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
@testable import Departure

// Unit scenarios compile definitions and bind selection before routing operations,
// without requiring a mounted platform view.
@MainActor
extension RouteScope {
    static let testSelectionOwner = RoutePresentationHostID()

    func bindTestBranchSelection(_ selection: AnyRouteBranchSelection) {
        bindRoutingHost(Self.testSelectionOwner, automatic: false, selection: selection)
        bindBranchSelection(selection)
    }

    func define(_ declarations: [RouteScopeDeclaration], concurrent: Bool? = nil) {
        // Legacy fixtures express their one container as individual branch records.
        let branches = declarations.filter { $0.branch != nil }
        let definitions: [RouteScopeDeclaration] = declarations.filter { $0.branch == nil }.map { declaration -> RouteScopeDeclaration in
            guard let concurrent, case let .branches(_, children) = declaration.content else { return declaration }
            return RouteScopeDeclaration(branches: children, concurrent: concurrent)
        } + (branches.isEmpty ? [] : [RouteScopeDeclaration(branches: branches, concurrent: concurrent ?? false)])
        useDefinitions(RouteDefinitions(definitions))
    }
    @discardableResult
    func defineTestMap(sourceID: AnyHashable = "fixture", id: AnyHashable? = nil, selection: AnyRouteBranchSelection? = nil, concurrent: Bool? = nil, definitions: [RouteScopeDeclaration]) -> Bool {
        if let id { self.id = id }
        define(definitions, concurrent: concurrent)
        if let selection {
            if branchContainer == nil { branchContainer = BranchContainerState(selectedBranch: selection.value()) }
            bindTestBranchSelection(selection)
        }
        return true
    }
    @discardableResult
    func attachTestBranch(_ scope: RouteScope, for branch: AnyHashable, presentationHostID: RoutePresentationHostID? = nil) -> Bool {
        let didChange = branchScopes[branch] !== scope
        if didChange, let compiled = branchScopes[branch] {
            // These legacy scenarios supply an explicit branch map in place of
            // the compiled fixture branch. Fill only missing keys from that map;
            // constructing this test topology must not invent duplicate declarations.
            let explicitTypes = Set(scope.routeAttachments.map { ObjectIdentifier($0.routeType) })
            let inherited = compiled.routeAttachments.filter { !explicitTypes.contains(ObjectIdentifier($0.routeType)) }
            scope.useDefinitions(RouteDefinitions([RouteScopeDeclaration(routes: scope.routeAttachments + inherited)]))
            for id in compiled.branchScopes.keys where scope.branchScopes[id] == nil {
                scope.branchScopes[id] = compiled.branchScopes[id]
                scope.branchScopes[id]?.parent = scope
            }
        }
        branchScopes[branch] = scope
        scope.parent = self
        scope.branchID = branch
        if let presentationHostID { scope.bindRoutingHost(presentationHostID, automatic: false) }
        return didChange
    }
    func detachTestBranch(_ scope: RouteScope, for branch: AnyHashable) {
        guard branchScopes[branch] === scope else { return }
        branchScopes[branch] = nil
        scope.parent = nil
        // Its structural branch identity survives detachment, as it does in outgoing trees.
    }
}

@MainActor
extension RouterEngine {
    func bindTestBranchSelection(_ selection: AnyRouteBranchSelection, in scope: RouteScope) {
        scope.bindRoutingHost(RouteScope.testSelectionOwner, automatic: false, selection: selection)
        synchronizeBranchSelection(ownedBy: RouteScope.testSelectionOwner, in: scope)
    }
    func routeScopeDidInstallInView(_ scope: RouteScope) { hostDidAttach(scope, view: nil, id: UUID()) }
    func routeScopeDidLeaveView(_ scope: RouteScope) {
        if let id = scope.hostID { hostDidDetach(scope, id: id) }
    }
}

// Fixture construction uses the same topology operations as production mutations.
@MainActor
extension RoutePath {
    func replaceTestPath(_ scopes: [RouteScope]) {
        if let owner { keepThrough(owner) }
        for scope in scopes { append(scope) }
    }
}

@MainActor
extension RouterEngine {
    var hasOutgoingPresentations: Bool {
        navigationOperations.contains { !$0.outgoing.isEmpty }
    }

    // Tests inspect the exact destination returned by the production readiness gate.
    @discardableResult
    func requestRoute(_ route: some Route, origin: RouteRequestOrigin? = nil) async -> RouteScope? {
        await requestRouteWhenReady(route, origin: origin)
    }
}

@MainActor
extension RouteScope {
    @discardableResult
    func waitUntilUninstalled() async -> Bool {
        // Committed teardown owns its lifetime even if the requesting task cancels.
        await RouteScopeReadiness.wait(in: self, cancellable: false) { !self.isInstalledInView }
    }
}
