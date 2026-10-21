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

struct RoutePresentationHostID: Hashable, Sendable {
    private let value = UUID()
}

/// One route occurrence in a map, with presentation metadata and child definitions.
///
/// A declaration can describe a route type without supplying a destination builder.
public struct AnyRouteDeclaration: Sendable, Hashable, RouteDeclaration {
    let identity: UUID
    let routeType: any Route.Type
    let presentation: RoutePresentation
    let scopeID: AnyHashable?
    let children: [RouteScopeDeclaration]
    let childScope: RouteDefinitions?
    let destination: AnyRouteDestination?

    init(_ route: any Route.Type, presentation: RoutePresentation, id: AnyHashable? = nil, children: [RouteScopeDeclaration] = []) {
        precondition(presentation.style.isModal || presentation.priority == .default,
                     "Only modal declarations can start a priority space.")
        identity = UUID()
        routeType = route
        self.presentation = presentation
        scopeID = id
        self.children = children
        childScope = nil
        destination = nil
    }

    private init(copy: Self, destination: AnyRouteDestination?, presentation: RoutePresentation? = nil, identity: UUID? = nil, childScope: RouteDefinitions? = nil) {
        self.identity = identity ?? copy.identity
        routeType = copy.routeType
        self.presentation = presentation ?? copy.presentation
        scopeID = copy.scopeID
        children = copy.children
        self.childScope = childScope ?? copy.childScope
        self.destination = destination
    }

    func compiled(destinations: RouteDestinationBindings) -> Self {
        Self(copy: self, destination: destinations.binding(for: routeType)?.declaration,
             identity: UUID(), childScope: RouteDefinitions(children, id: scopeID, destinations: destinations))
    }

    func withPriority(_ priority: RoutePriority) -> Self {
        precondition(presentation.style.isModal || priority == .default,
                     "Root priority builders accept only modal presentations.")
        return Self(copy: self, destination: destination, presentation: .init(style: presentation.style, priority: priority))
    }

    public var _routeDeclarations: [AnyRouteDeclaration] { [self] }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }
    public nonisolated func hash(into hasher: inout Hasher) { hasher.combine(identity) }

    var priority: RoutePriority { presentation.priority }
    var presentationKind: RoutePresentationKind { presentation.style }
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
        case destinations([AnyRouteDestination])
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
    init(destinations: [AnyRouteDestination]) {
        content = .destinations(destinations)
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
        switch content {
        case .routes(let routes):
            return Self(routes: routes.map { $0.withPriority(priority) })
        case .destinations:
            return self
        default:
            preconditionFailure("Root priority groups accept only modal route declarations.")
        }
    }
}

public protocol RouteDeclaration {
    var _routeDeclarations: [AnyRouteDeclaration] { get }
}
