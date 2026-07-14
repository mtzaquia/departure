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

// MARK: - Route Attachment Lookup

extension RouteScope {
    struct RouteAttachmentMatch {
        let branchID: AnyHashable?
        let declaration: AnyRouteDeclaration
    }

    var routeAttachments: [AnyRouteDeclaration] {
        let visible = branchContainer == nil
            ? declarations.local.routeAttachments
            : declarations.declarations(forBranch: activeBranch).routeAttachments + declarations.local.routeAttachments
        let adopted = branchID
            .flatMap { branchID in
                parent?
                    .adoptedRouteAttachments(forBranch: branchID)
            } ?? []

        return visible + adopted
    }

    var hookAttachments: [AnyHookDeclaration] {
        guard branchContainer != nil else {
            return declarations.local.hookAttachments
        }

        return declarations
            .declarations(forBranch: activeBranch)
            .hookAttachments
    }

    func adoptedRouteAttachments(forBranch branchID: AnyHashable) -> [AnyRouteDeclaration] {
        declarations
            .declarations(forBranch: branchID)
            .routeAttachments
            .filter { $0.drivesPresentation == false }
            .drivingPresentation(true)
    }

    func firstRouteAttachment(for routeType: (some Route).Type) -> RouteAttachmentMatch? {
        if branchContainer != nil,
           let declaration = declarations.declarations(forBranch: activeBranch).routeAttachment(for: routeType) {
            return RouteAttachmentMatch(branchID: activeBranch, declaration: declaration)
        }

        if let declaration = declarations.local.routeAttachment(for: routeType) {
            return RouteAttachmentMatch(branchID: nil, declaration: declaration)
        }

        if let branchID,
           let declaration = parent?
            .adoptedRouteAttachments(forBranch: branchID)
            .first(where: { attachment in
                routeType == attachment.routeType
            }) {
            return RouteAttachmentMatch(branchID: nil, declaration: declaration)
        }

        if branchContainer != nil {
            for branchID in declarations.branchIDs where branchID != activeBranch {
                guard let declaration = declarations.declarations(forBranch: branchID).routeAttachment(for: routeType) else {
                    continue
                }

                return RouteAttachmentMatch(branchID: branchID, declaration: declaration)
            }
        }

        return nil
    }

    func firstBranchScopeRouteAttachment(
        for routeType: (some Route).Type,
        in branch: AnyHashable
    ) -> RouteAttachmentMatch? {
        guard
            let branchScope = branchScopes[branch]?.activeLocalScope,
            branchScope !== self,
            let match = branchScope.firstRouteAttachment(for: routeType)
        else {
            return nil
        }

        return RouteAttachmentMatch(branchID: branch, declaration: match.declaration)
    }
}

// MARK: - Declaration Installation

extension RouteScope {
    func installRouteDeclarations(
        sourceID: AnyHashable = AnyHashable("default"),
        id: AnyHashable?,
        branchSelection: AnyRouteBranchSelection?,
        routeDeclarations: [RouteScopeDeclaration],
        sourceEnvironment: EnvironmentValues? = nil
    ) {
        let hookDeclarations = declarations.allHookAttachments
        declarationInstallation.installRouteSource(
            sourceID: sourceID,
            id: id,
            sourceEnvironment: sourceEnvironment ?? EnvironmentValues()
        )

        configureBranchContainer(
            branchSelection: branchSelection,
            routeDeclarations: routeDeclarations
        )
        self.declarations = makeDeclarationStore(
            from: routeDeclarations,
            activeBranch: activeBranch,
            hookDeclarations: hookDeclarations
        )
        log.departureDebug(.routeDeclarationsInstalled(scope: self, declarationCount: routeDeclarations.count))
    }

    @discardableResult
    func uninstallRouteDeclarations(sourceID: AnyHashable) -> Bool {
        guard declarationInstallation.uninstallRouteSource(sourceID: sourceID) else {
            return false
        }

        branchContainer = nil
        declarations = DeclarationStore()
        log.departureDebug(.routeDeclarationsUninstalled(scope: self))
        return true
    }

    @discardableResult
    func installHookDeclarations(
        sourceID: AnyHashable = AnyHashable("default"),
        hookDeclarations: [AnyHookDeclaration]
    ) -> Bool {
        declarationInstallation.installHookSource(sourceID: sourceID)
        var scopeDeclarations = ScopeDeclarations()

        for hookDeclaration in hookDeclarations {
            let inserted = scopeDeclarations.appendHook(hookDeclaration)
            guard inserted == false else {
                continue
            }

            logDuplicateHookDeclaration(hookDeclaration, branchID: activeBranch)
        }

        let didChangeDeclarations: Bool
        if branchContainer != nil {
            didChangeDeclarations = declarations.declarations(forBranch: activeBranch).hookIdentities
                != scopeDeclarations.hookIdentities
            declarations.setHooks(scopeDeclarations.hookAttachments, forBranch: activeBranch)
        } else {
            didChangeDeclarations = declarations.local.hookIdentities != scopeDeclarations.hookIdentities
            declarations.local.setHooks(scopeDeclarations.hookAttachments)
        }

        if didChangeDeclarations {
            log.departureDebug(.hookDeclarationsInstalled(scope: self, hookCount: hookDeclarations.count))
        }
        return didChangeDeclarations
    }

    func uninstallHookDeclarations(sourceID: AnyHashable) {
        guard declarationInstallation.uninstallHookSource(sourceID: sourceID) else {
            return
        }

        if branchContainer != nil {
            declarations.removeHooks(forBranch: activeBranch)
        } else {
            declarations.local.removeHooks()
        }
        log.departureDebug(.hookDeclarationsUninstalled(scope: self))
    }
}

// MARK: - Private Helpers

private extension RouteScope {
    func configureBranchContainer(
        branchSelection: AnyRouteBranchSelection?,
        routeDeclarations: [RouteScopeDeclaration]
    ) {
        let hasBranchDeclarations = routeDeclarations.contains {
            $0.branch != nil
        }

        guard branchSelection != nil || hasBranchDeclarations else {
            branchContainer = nil
            return
        }

        branchContainer = BranchContainerState(
            defaultBranch: defaultBranchID(hasSelection: branchSelection != nil),
            selection: branchSelection
        )
    }

    func makeDeclarationStore(
        from routeDeclarations: [RouteScopeDeclaration],
        activeBranch: AnyHashable,
        hookDeclarations: [AnyHookDeclaration]
    ) -> DeclarationStore {
        var branchIDs = [activeBranch]
        branchIDs.append(
            contentsOf: routeDeclarations.compactMap(\.branch)
        )

        var declarationStore = branchContainer == nil
            ? DeclarationStore()
            : DeclarationStore(branchIDs: branchIDs)

        for declaration in routeDeclarations {
            let declarationBranch = branchContainer == nil ? nil : declaration.branch
            let duplicateBranch = declarationBranch ?? activeBranch

            for route in declaration.routes {
                let inserted: Bool
                if let declarationBranch {
                    inserted = declarationStore.appendRoute(route, toBranch: declarationBranch)
                } else {
                    inserted = declarationStore.local.appendRoute(route)
                }

                if inserted == false {
                    logDuplicateRouteDeclaration(route.routeType, branchID: duplicateBranch)
                }
            }
        }

        if hookDeclarations.isEmpty == false {
            if branchContainer != nil {
                declarationStore.setHooks(hookDeclarations, forBranch: activeBranch)
            } else {
                declarationStore.local.setHooks(hookDeclarations)
            }
        }

        return declarationStore
    }

    func logDuplicateRouteDeclaration(
        _ routeType: any Route.Type,
        branchID: AnyHashable
    ) {
        log.departureWarning(
            """
            Duplicate route declaration for \(String(reflecting: routeType)) in scope \(String(describing: id)), branch \(String(describing: branchID)). The first declaration will be used.
            """
        )
    }

    func logDuplicateHookDeclaration(
        _ hookDeclaration: AnyHookDeclaration,
        branchID: AnyHashable
    ) {
        switch hookDeclaration.kind {
        case let .actionInterceptor(actionType, _):
            log.departureWarning(
                """
                Duplicate action interceptor for \(String(reflecting: actionType)) in scope \(String(describing: id)), branch \(String(describing: branchID)). The first interceptor will be used.
                """
            )

        case let .unwindHandler(routeType, _):
            log.departureWarning(
                """
                Duplicate unwind handler for \(String(reflecting: routeType)) in scope \(String(describing: id)), branch \(String(describing: branchID)). The first handler will be used.
                """
            )
        }
    }

}
