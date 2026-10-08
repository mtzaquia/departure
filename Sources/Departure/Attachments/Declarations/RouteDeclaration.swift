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

struct RoutePresentationHostID: Hashable, Sendable {
    private let value = UUID()
}

/// One occurrence in a map, with its destination and child definitions.
public struct AnyRouteDeclaration: Sendable, Hashable, RouteDeclaration {
    enum Kind: Hashable, Sendable {
        case push
        case replace
        case sheet(priority: RoutePriority)
        case cover(priority: RoutePriority, transition: Cover.Transition)
    }
    let identity: UUID
    let routeType: any Route.Type
    let kind: Kind
    let scopeID: AnyHashable?
    let children: [RouteScopeDeclaration]
    let childScope: RouteDefinitions?
    let build: @MainActor @Sendable (any Route, RouteContext) -> AnyView

    init<R: Route>(_ destination: RouteDestination<R>, kind: Kind, id: AnyHashable? = nil, children: [RouteScopeDeclaration] = []) {
        identity = UUID()
        routeType = R.self
        self.kind = kind
        scopeID = id
        self.children = children
        childScope = nil
        build = { route, context in
            // Lookup checks the domain type before choosing this occurrence.
            destination.build(route as! R, context)
        }
    }

    private init(copy: Self, kind: Kind, identity: UUID? = nil, childScope: RouteDefinitions? = nil) {
        self.identity = identity ?? copy.identity
        routeType = copy.routeType
        self.kind = kind
        scopeID = copy.scopeID
        children = childScope == nil ? copy.children : []
        self.childScope = childScope ?? copy.childScope
        build = copy.build
    }

    func compiled() -> Self {
        Self(copy: self, kind: kind, identity: UUID(), childScope: childScope ?? RouteDefinitions(children, id: scopeID))
    }

    func withPriority(_ priority: RoutePriority) -> Self {
        switch kind {
        case .sheet: return Self(copy: self, kind: .sheet(priority: priority))
        case let .cover(_, transition): return Self(copy: self, kind: .cover(priority: priority, transition: transition))
        case .push, .replace:
            precondition(priority == .default, "Root priority builders accept only modal presentations.")
            return self
        }
    }

    public var _routeDeclarations: [AnyRouteDeclaration] { [self] }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }
    public nonisolated func hash(into hasher: inout Hasher) { hasher.combine(identity) }

    var priority: RoutePriority {
        switch kind {
        case .push, .replace: .default
        case let .sheet(priority), let .cover(priority, _): priority
        }
    }
    var presentationKind: RoutePresentationKind {
        switch kind {
        case .push: .push
        case .replace: .replace
        case .sheet: .sheet
        case let .cover(_, transition): .cover(transition)
        }
    }
}

typealias RoutePresentationKind = RoutePresentation.Style

/// Priority of a presentation. Elevated presentations are anchored at the routing root.
public enum RoutePriority: Int, Comparable, Hashable, Sendable {
    /// The permanent application flow, covered while an elevated space exists.
    case `default`
    /// A modal space presented above the default flow.
    case high
    /// The highest-priority modal space.
    case critical
    public nonisolated static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A declaration group in a map. Branch groups preserve their own child definitions.
public struct RouteScopeDeclaration: Sendable, Hashable {
    enum Content: Sendable, Hashable {
        case scopeID(AnyHashable)
        case routes([AnyRouteDeclaration])
        case branch(AnyHashable, children: [RouteScopeDeclaration])
        case branches(concurrent: Bool, children: [RouteScopeDeclaration])
    }
    let content: Content
    var branch: AnyHashable? {
        if case let .branch(value, _) = content { return value }
        return nil
    }
    var routes: [AnyRouteDeclaration] {
        if case let .routes(routes) = content { return routes }
        return []
    }
    init(routes: [AnyRouteDeclaration]) {
        content = .routes(routes)
    }
    init<Selection: Hashable>(branch: Selection, children: [RouteScopeDeclaration]) {
        content = .branch(AnyHashable(branch), children: children)
    }
    init(branches: [RouteScopeDeclaration], concurrent: Bool) {
        content = .branches(concurrent: concurrent, children: branches)
    }
    init(scopeID: AnyHashable) {
        content = .scopeID(scopeID)
    }
    func withPriority(_ priority: RoutePriority) -> Self {
        guard case let .routes(routes) = content else {
            preconditionFailure("Root priority builders accept only modal route declarations.")
        }
        return Self(routes: routes.map { $0.withPriority(priority) })
    }
}

public protocol RouteDeclaration {
    var _routeDeclarations: [AnyRouteDeclaration] { get }
}
