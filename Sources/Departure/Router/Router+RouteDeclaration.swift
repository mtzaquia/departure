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

extension Router {
    func requestRoute(_ route: some Route) async {
#if DEBUG
        log.departureDebug("route requested | route=\(route.departureDebugDescription)")
#endif

        let resolvedRoute: (any Route)?

        let resolutionResult: RouteResolution = await route.resolveRoute()
        switch resolutionResult {
        case .allow:
            resolvedRoute = route

        case .reroute(let newRoute):
#if DEBUG
            log.departureDebug(
                "route rerouted | from=\(route.departureDebugDescription) | to=\(newRoute.departureDebugDescription)"
            )
#endif
            resolvedRoute = newRoute

        case .drop:
#if DEBUG
            log.departureDebug("route dropped | reason=resolution")
#endif
            resolvedRoute = nil
        }

        guard let resolvedRoute else { return }

        let resolvedRouteType = type(of: resolvedRoute)
        guard let matchedDeclaration = firstDeclaration(including: resolvedRouteType) else {
#if DEBUG
            log.departureDebug(
                "route dropped | reason=no declaration | type=\(String(reflecting: resolvedRouteType))"
            )
#endif
            return // Cannot find matching route, dropped.
        }

        let requestedPriority = matchedDeclaration.declaration.priority
        let hasHighPrioritySegment = highPrioritySegmentStartIndex != nil
        let declarationIsInHighPrioritySegment = matchedDeclaration.pathIndex.map { pathIndex in
            highPrioritySegmentStartIndex.map { pathIndex >= $0 } ?? false
        } ?? false

#if DEBUG
        log.departureDebug(
            "route matched | route=\(resolvedRoute.departureDebugDescription) | \(matchedDeclaration.departureDebugDescription) | highPriorityStart=\(String(describing: highPrioritySegmentStartIndex))"
        )
#endif

        switch (requestedPriority, hasHighPrioritySegment, declarationIsInHighPrioritySegment) {
        case (.normal, true, false):
#if DEBUG
            log.departureDebug(
                "route blocked | route=\(resolvedRoute.departureDebugDescription) | reason=normal priority before active high-priority segment"
            )
#endif
            return // Normal priority route attached before an existing high-priority segment is dropped.

        case (.normal, _, _), (.high, _, true):
#if DEBUG
            log.departureDebug("route accepted | action=append | route=\(resolvedRoute.departureDebugDescription)")
#endif
            await appendRoute(resolvedRoute, after: matchedDeclaration)
            return

        case (.high, _, false):
#if DEBUG
            log.departureDebug(
                "route accepted | action=replace high-priority segment | route=\(resolvedRoute.departureDebugDescription)"
            )
#endif
            replaceHighPrioritySegment(with: resolvedRoute, after: matchedDeclaration)
            return
        }
    }
}

extension Router {
    struct DeclarationMatch {
        var pathIndex: [RouteScope].Index?
        var branchID: AnyHashable
        var declaration: AnyRouteDeclaration

#if DEBUG
        var departureDebugDescription: String {
            "match=declaration | pathIndex=\(String(describing: pathIndex)) | branch=\(branchID.departureDebugDescription) | declaration=\(declaration.departureDebugDescription)"
        }
#endif
    }

    func firstDeclaration(including routeType: any Route.Type) -> DeclarationMatch? {
        for index in path.indices.reversed() {
            if let match = path[index].firstRouteAttachment(for: routeType) {
                return DeclarationMatch(
                    pathIndex: index,
                    branchID: match.branchID,
                    declaration: match.declaration
                )
            }
        }

        if let match = root.firstRouteAttachment(for: routeType) {
            return DeclarationMatch(
                branchID: match.branchID,
                declaration: match.declaration
            )
        }

        return nil
    }
}
