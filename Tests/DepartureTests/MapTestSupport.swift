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

// Unit scenarios compile definitions before issuing routing operations. Selection and
// environment are explicit test inputs instead of requiring a mounted platform view.
extension RouteScope {
    func define(_ declarations: [RouteScopeDeclaration]) { useDefinitions(RouteDefinitions(declarations)) }
    @discardableResult
    func defineTestMap(sourceID: AnyHashable = "fixture", id: AnyHashable? = nil, selection: AnyRouteBranchSelection? = nil, definitions: [RouteScopeDeclaration], environment: EnvironmentValues? = nil) -> Bool {
        if let id { self.id = id }
        if let environment { updateSourceEnvironment(environment) }
        define(definitions)
        if let selection {
            if branchContainer == nil { branchContainer = BranchContainerState(selectedBranch: selection.value(), selection: selection, concurrent: selection.concurrent) }
            branchContainer?.selection = selection
            branchContainer?.selectedBranch = selection.value()
            branchContainer?.concurrent = selection.concurrent
        }
        return true
    }
    @discardableResult
    func attachTestBranch(_ scope: RouteScope, for branch: AnyHashable, environment: EnvironmentValues? = nil, presentationHostID: RoutePresentationHostID? = nil) -> Bool {
        let didChange = branchScopes[branch] !== scope
        if didChange, let compiled = branchScopes[branch] {
            scope.useDefinitions(RouteDefinitions([RouteScopeDeclaration(routes: scope.routeAttachments + compiled.routeAttachments)]))
            for id in compiled.branchScopes.keys where scope.branchScopes[id] == nil {
                scope.branchScopes[id] = compiled.branchScopes[id]
                scope.branchScopes[id]?.parent = scope
            }
        }
        branchScopes[branch] = scope
        scope.parent = self
        scope.branchID = branch
        #if DEBUG
        scope.debugKind = .branch
        #endif
        if let presentationHostID { scope.bindRoutingHost(presentationHostID, automatic: false, environment: scope.sourceEnvironment) }
        if let environment { scope.updateSourceEnvironment(environment) }
        return didChange
    }
    func detachTestBranch(_ scope: RouteScope, for branch: AnyHashable) {
        guard branchScopes[branch] === scope else { return }
        branchScopes[branch] = nil
        scope.parent = nil
        scope.branchID = nil
    }
}

extension RouterEngine {
    func routeScopeDidInstallInView(_ scope: RouteScope) { hostDidAttach(scope, view: nil, id: UUID()) }
    func routeScopeDidLeaveView(_ scope: RouteScope) {
        if let id = scope.hostID { hostDidDetach(scope, id: id) }
    }
}

// Fixture construction uses the same topology operations as production mutations.
extension RoutePath {
    func replaceTestPath(_ scopes: [RouteScope]) {
        keepThrough(.owner)
        for scope in scopes { append(scope) }
    }
}
