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

extension RouterEngine {
    enum UnwindSelection: Equatable {
        case policy(UnwindTarget)
        case routeType(any Route.Type)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.policy(lhs), .policy(rhs)): lhs == rhs
            case let (.routeType(lhs), .routeType(rhs)): ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
            default: false
            }
        }
    }

    func resolveUnwind(_ selection: UnwindSelection, from source: RouteScope) -> RouteScope? {
        guard let path = spaces.routePath(containing: source), let space = spaces.space(containing: path) else { return nil }
        let ancestry = source.ancestry.prefix {
            $0.space === space && spaces.routePath(containing: $0) != nil
        }
        switch selection {
        case .policy(.current):
            return source
        case .policy(.nearestModal):
            guard let modal = ancestry.first(where: { $0.routePresentation?.style.isModal == true }) else { return nil }
            return modal
        case let .routeType(type):
            guard let match = ancestry.first(where: {
                $0.route.map { ObjectIdentifier(Swift.type(of: $0)) == ObjectIdentifier(type) } == true
            }) else { return nil }
            return match
        }
    }

    @discardableResult
    func unwindAndWait(_ policy: UnwindTarget, payload: Any? = nil, origin: RouteRequestOrigin? = nil) async -> Bool {
        await unwindAndWait(.policy(policy), payload: payload, origin: origin)
    }

    @discardableResult
    func unwindAndWait(_ selection: UnwindSelection, payload: Any? = nil, origin: RouteRequestOrigin? = nil) async -> Bool {
        #if DEBUG
        guard DepartureLogTrace.id != nil else {
            return await DepartureLogTrace.$id.withValue(DepartureLogTrace.nextID(prefix: "u")) {
                await unwindAndWait(selection, payload: payload, origin: origin)
            }
        }
        #endif
        log.departureDebug(.unwindRequested(target: selection))
        guard let source = navigationSource(origin) else { return false }
        guard let target = resolveUnwind(selection, from: source) else {
            log.departureWarning(.unwindRouteTargetMissing(target: selection))
            return false
        }
        return await unwindPrevious(from: target, payload: payload)
    }

    @discardableResult
    func resetToRoot(payload: Any? = nil, origin: RouteRequestOrigin? = nil) async -> Bool {
        #if DEBUG
        guard DepartureLogTrace.id != nil else {
            return await DepartureLogTrace.$id.withValue(DepartureLogTrace.nextID(prefix: "u")) {
                await resetToRoot(payload: payload, origin: origin)
            }
        }
        #endif
        log.departureDebug(.resetToRootRequested)
        guard let source = navigationSource(origin), let space = source.space else { return false }
        let target = space.root
        let plan = spaces.rootUnwindPlan(in: space)
        guard !plan.removedScopes.isEmpty else {
            log.departureDebug(.unwindSkippedNoRoute)
            return false
        }
        log.departureDebug(.unwindAccepted(keepThrough: target, removing: plan.removedScopes.count))
        return await performPlannedUnwind(beginNavigationOperation(plan: plan), notifying: [source],
            payload: payload, in: target, authority: .scope(source), logsCompletion: true)
    }
}
