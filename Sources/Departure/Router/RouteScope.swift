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
    struct RouteAttachmentMatch {
        let branchID: AnyHashable
        let declaration: AnyRouteDeclaration
    }

    var id: AnyHashable {
        declarationInstallation.id
    }

    let route: (any Route)?
    weak var parent: RouteScope?

    var branchID: AnyHashable?
    var declarations = DeclarationStore()
    var branchContainer: BranchContainerState?
    var branchScopes: [AnyHashable: RouteScope] = [:]

    let declarationInstallation: DeclarationInstallationState
    private var uninstallObservers: [@MainActor () -> Void] = []

    lazy var path = RoutePath(owner: self)
    weak var owningPath: RoutePath?

    weak var hostScope: RouteScope?
    var hostDeclaration: AnyRouteDeclaration?

    weak var pushChild: RouteScope?
    weak var modalChild: RouteScope?

    #if DEBUG
    var debugKind = DebugKind.root
    #endif

    private(set) var isInstalledInView = false
    var sourceEnvironment: EnvironmentValues {
        declarationInstallation.sourceEnvironment
    }

    init(id: AnyHashable, route: (any Route)?, parent: RouteScope? = nil) {
        self.route = route
        self.parent = parent
        self.declarationInstallation = DeclarationInstallationState(initialID: id)
    }
}

// MARK: - Derived State

extension RouteScope {
    var currentRoute: (any Route)? {
        route ?? parent?.currentRoute
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

// MARK: - Lifecycle

extension RouteScope {
    func installInView() {
        isInstalledInView = true
    }

    func uninstallFromView() {
        isInstalledInView = false

        uninstallObservers.forEach { $0() }
        uninstallObservers.removeAll()
    }

    func onUninstallFromView(_ observer: @escaping @MainActor () -> Void) {
        guard isInstalledInView else {
            observer()
            return
        }

        uninstallObservers.append(observer)
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

final class DeclarationInstallationState {
    let initialID: AnyHashable
    private(set) var id: AnyHashable
    private(set) var sourceEnvironment = EnvironmentValues()

    private var routeSourceID: AnyHashable?
    private var hookSourceID: AnyHashable?

    fileprivate init(initialID: AnyHashable) {
        self.initialID = initialID
        self.id = initialID
    }

    func installRouteSource(
        sourceID: AnyHashable,
        id: AnyHashable?,
        sourceEnvironment: EnvironmentValues
    ) {
        routeSourceID = sourceID
        updateSourceEnvironment(sourceEnvironment)

        if let id {
            self.id = id
        }
    }

    func uninstallRouteSource(sourceID: AnyHashable) -> Bool {
        guard routeSourceID == sourceID else {
            return false
        }

        routeSourceID = nil
        id = initialID
        updateSourceEnvironment(EnvironmentValues())
        return true
    }

    func installHookSource(sourceID: AnyHashable) {
        hookSourceID = sourceID
    }

    func uninstallHookSource(sourceID: AnyHashable) -> Bool {
        guard hookSourceID == sourceID else {
            return false
        }

        hookSourceID = nil
        return true
    }

    func updateSourceEnvironment(_ sourceEnvironment: EnvironmentValues) {
        self.sourceEnvironment = sourceEnvironment
    }
}
