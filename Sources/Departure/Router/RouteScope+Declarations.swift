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
        enum PresentationAnchor: Equatable {
            case declarationLocation
            case branchOwner
            case activeLocalScope
        }

        let branchID: AnyHashable?
        let declaration: AnyRouteDeclaration
        let presentationAnchor: PresentationAnchor

        init(
            branchID: AnyHashable?,
            declaration: AnyRouteDeclaration,
            presentationAnchor: PresentationAnchor? = nil
        ) {
            self.branchID = branchID
            self.declaration = declaration
            self.presentationAnchor = presentationAnchor
                ?? (branchID == nil ? .declarationLocation : .branchOwner)
        }
    }

    var routeAttachments: [AnyRouteDeclaration] {
        definitions.routeAttachments
    }

    func firstRouteAttachment(for routeType: (some Route).Type, includingOtherBranches: Bool = true) -> RouteAttachmentMatch? {
        if includingOtherBranches, branchContainer != nil,
           let declaration = branchScopes[activeBranch]?.definitions.routeAttachment(for: routeType) {
            return RouteAttachmentMatch(branchID: activeBranch, declaration: declaration)
        }

        if let declaration = definitions.routeAttachment(for: routeType) {
            return RouteAttachmentMatch(branchID: nil, declaration: declaration)
        }

        if includingOtherBranches, branchContainer != nil {
            for branchID in branchScopes.keys where branchID != activeBranch {
                guard let declaration = branchScopes[branchID]?.definitions.routeAttachment(for: routeType) else {
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
            branchScope !== branchScopes[branch],
            let match = branchScope.firstRouteAttachment(for: routeType)
        else {
            return nil
        }

        return RouteAttachmentMatch(
            branchID: branch,
            declaration: match.declaration,
            presentationAnchor: .activeLocalScope
        )
    }

    func attachedPresentationDeclaration(
        presentedBy host: RouteScope,
        matching presentationKind: RoutePresentationKind,
        hostedBy presentationHostID: RoutePresentationHostID?
    ) -> AnyRouteDeclaration? {
        guard
            presentationOrigin === host,
            let declaration = presentationDeclaration,
            declaration.presentationKind == presentationKind,
            presentationHostID == nil || host.presentationHostID == presentationHostID
        else {
            return nil
        }

        return declaration
    }
}
