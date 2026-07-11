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
import SwiftUI

final class RouteScope: Identifiable {
    var id: AnyHashable {
        declarationInstallation.id
    }

    let route: (any Route)?
    weak var parent: RouteScope?

    var branchID: AnyHashable?
    var declarations = DeclarationStore()
    var branchContainer: BranchContainerState?
    var branchScopes: [AnyHashable: RouteScope] = [:]

    let declarationInstallation: RouteScopeDeclarationInstallation
    let viewLifecycle = RouteScopeViewLifecycle()

    lazy var path = RoutePath(owner: self)
    weak var owningPath: RoutePath?

    private(set) var presentation: RouteScopePresentation?

    #if DEBUG
    var debugKind = DebugKind.root
    #endif

    var isInstalledInView: Bool {
        viewLifecycle.isInstalled
    }
    var sourceEnvironment: EnvironmentValues {
        sourceEnvironmentReference.values
    }

    var sourceEnvironmentReference: RouteSourceEnvironment {
        declarationInstallation.sourceEnvironment
    }

    var presentationOrigin: RouteScope? {
        presentation?.origin
    }

    var presentationDeclaration: AnyRouteDeclaration? {
        presentation?.declaration
    }

    init(id: AnyHashable, route: (any Route)?, parent: RouteScope? = nil) {
        self.route = route
        self.parent = parent
        self.declarationInstallation = RouteScopeDeclarationInstallation(initialID: id)
    }
}

// MARK: - Derived State

extension RouteScope {
    var currentRoute: (any Route)? {
        route ?? parent?.currentRoute
    }

    func attachPresentation(
        to origin: RouteScope,
        declaration: AnyRouteDeclaration
    ) {
        presentation = RouteScopePresentation(
            origin: origin,
            declaration: declaration
        )
    }
}

// MARK: - Declaration Installation State

extension RouteScope {
    func updateSourceEnvironment(_ sourceEnvironment: EnvironmentValues) {
        declarationInstallation.updateSourceEnvironment(sourceEnvironment)
    }

    func defaultBranchID(hasSelection: Bool) -> AnyHashable {
        hasSelection
            ? branchContainer?.defaultBranch ?? declarationInstallation.initialID
            : id
    }
}

#if DEBUG
extension RouteScope {
    enum DebugKind {
        case root
        case branch
    }
}
#endif
