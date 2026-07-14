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

/// Tracks scopes with route declarations installed by SwiftUI without retaining them.
final class RouteDeclarationScopeRegistry {
    private struct Entry {
        weak var scope: RouteScope?
        let sourceID: AnyHashable
    }

    private var scopesByRouteType: [ObjectIdentifier: [Entry]] = [:]

    func install(
        _ scope: RouteScope,
        sourceID: AnyHashable,
        declarations: [RouteScopeDeclaration]
    ) {
        // A scope has one active route-declaration source. Replacing it must also discard types
        // recorded for the previous source so the registry reflects the declaration store.
        removeEntries(for: scope)

        let routeTypeIDs = Set(
            declarations
                .flatMap(\.routes)
                .map(\.routeType)
                .map(ObjectIdentifier.init)
        )

        for routeTypeID in routeTypeIDs {
            scopesByRouteType[routeTypeID, default: []].append(
                Entry(scope: scope, sourceID: sourceID)
            )
        }
    }

    func uninstall(_ scope: RouteScope, sourceID: AnyHashable) {
        removeEntries(for: scope, sourceID: sourceID)
    }

    func firstScope(
        declaring routeType: any Route.Type,
        outside routeForest: RouteForest
    ) -> RouteScope? {
        let routeTypeID = ObjectIdentifier(routeType)
        guard var entries = scopesByRouteType[routeTypeID] else {
            return nil
        }

        entries.removeAll { $0.scope == nil }
        if entries.isEmpty {
            scopesByRouteType[routeTypeID] = nil
            return nil
        }

        scopesByRouteType[routeTypeID] = entries
        return entries.compactMap(\.scope).first {
            routeForest.routePath(containing: $0) == nil
        }
    }

    private func removeEntries(for scope: RouteScope, sourceID: AnyHashable? = nil) {
        for routeTypeID in Array(scopesByRouteType.keys) {
            scopesByRouteType[routeTypeID]?.removeAll {
                $0.scope == nil || ($0.scope === scope && (sourceID == nil || $0.sourceID == sourceID))
            }

            if scopesByRouteType[routeTypeID]?.isEmpty == true {
                scopesByRouteType[routeTypeID] = nil
            }
        }
    }
}
