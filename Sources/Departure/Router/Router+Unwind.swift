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

        var dismissesScope: Bool {
            switch self {
            case .routeType, .policy(.current), .policy(.nearestModal): true
            case .policy(.root): false
            }
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.policy(lhs), .policy(rhs)): lhs == rhs
            case let (.routeType(lhs), .routeType(rhs)): ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
            default: false
            }
        }
    }

    /// Captures identities, rather than a plan, so new descendants are included on invocation.
    /// Root resets also capture their requesting scope for handler delivery and authority.
    struct ResolvedUnwind: Equatable {
        let selection: UnwindSelection
        let source: RouteRequestOrigin
        let target: RouteRequestOrigin

        init(_ selection: UnwindSelection, source: RouteScope, target: RouteScope) {
            self.selection = selection
            self.source = RouteRequestOrigin(scope: source)
            self.target = RouteRequestOrigin(scope: target)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.source == rhs.source && lhs.target == rhs.target
                && (lhs.selection == rhs.selection || (lhs.selection.dismissesScope && rhs.selection.dismissesScope))
        }
    }

    func resolveUnwind(_ selection: UnwindSelection, from source: RouteScope) -> ResolvedUnwind? {
        guard let path = spaces.routePath(containing: source), let space = spaces.space(containing: path) else { return nil }
        let ancestry = source.ancestry.prefix {
            $0.space === space && spaces.routePath(containing: $0) != nil
        }
        switch selection {
        case .policy(.current):
            return .init(selection, source: source, target: source)
        case .policy(.nearestModal):
            guard let modal = ancestry.first(where: { $0.routePresentation?.style.isModal == true }) else { return nil }
            return .init(selection, source: modal, target: modal)
        case let .routeType(type):
            guard let match = ancestry.first(where: {
                $0.route.map { ObjectIdentifier(Swift.type(of: $0)) == ObjectIdentifier(type) } == true
            }) else { return nil }
            return .init(selection, source: match, target: match)
        case .policy(.root):
            return .init(selection, source: source, target: space.root)
        }
    }

    @discardableResult
    func unwindAndWait(_ policy: UnwindTarget, payload: Any? = nil, origin: RouteRequestOrigin? = nil) async -> Bool {
        await unwindAndWait(.policy(policy), payload: payload, origin: origin)
    }

    @discardableResult
    func unwindAndWait(_ selection: UnwindSelection, payload: Any? = nil, origin: RouteRequestOrigin? = nil) async -> Bool {
        guard let source = navigationSource(origin) else { return false }
        guard let resolved = resolveUnwind(selection, from: source) else {
            log.departureWarning(.unwindRouteTargetMissing(target: selection))
            return false
        }
        return await unwindAndWait(resolved, payload: payload)
    }

    @discardableResult
    func unwindAndWait(_ resolved: ResolvedUnwind, payload: Any? = nil) async -> Bool {
        #if DEBUG
        guard DepartureLogTrace.id != nil else {
            return await DepartureLogTrace.$id.withValue(DepartureLogTrace.nextID(prefix: "u")) {
                await unwindAndWait(resolved, payload: payload)
            }
        }
        #endif
        log.departureDebug(.unwindRequested(target: resolved.selection))
        guard let source = navigationSource(resolved.source), let target = navigationSource(resolved.target) else { return false }
        if resolved.selection.dismissesScope {
            return await unwindPrevious(from: target, payload: payload)
        }

        guard let space = target.space, target === space.root else { return false }
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
