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

/// Type-erased route presentation metadata.
public struct AnyRouteDeclaration: Sendable, Hashable {
    enum Kind: Hashable, Sendable {
        case push
        case sheet(priority: RoutePriority, providesNavigation: Bool)
        case cover(priority: RoutePriority, transition: Cover.Transition, providesNavigation: Bool)
    }

    let routeType: any Route.Type
    let kind: Kind
    let drivesPresentation: Bool

    init(
        routeType: any Route.Type,
        kind: Kind,
        drivesPresentation: Bool = true
    ) {
        self.routeType = routeType
        self.kind = kind
        self.drivesPresentation = drivesPresentation
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.routeType == rhs.routeType
        && lhs.kind == rhs.kind
        && lhs.drivesPresentation == rhs.drivesPresentation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(routeType))
        hasher.combine(kind)
        hasher.combine(drivesPresentation)
    }
}

enum RoutePresentationKind: Hashable, Sendable {
    case push
    case sheet
    case cover(Cover.Transition)

    static let modalKinds: [RoutePresentationKind] = [.sheet] + Cover.Transition.allCases.map(RoutePresentationKind.cover)
}

extension AnyRouteDeclaration {
    var priority: RoutePriority {
        switch kind {
        case .push: .normal
        case let .sheet(priority, _), let .cover(priority, _, _): priority
        }
    }

    var presentationKind: RoutePresentationKind {
        switch kind {
        case .push: .push
        case .sheet: .sheet
        case let .cover(_, transition, _): .cover(transition)
        }
    }

    var providesNavigation: Bool {
        switch kind {
        case .push: false
        case let .sheet(_, providesNavigation), let .cover(_, _, providesNavigation):
            providesNavigation
        }
    }

    func drivingPresentation(_ value: Bool) -> Self {
        .init(routeType: routeType, kind: kind, drivesPresentation: value)
    }
}

/// A group of route declarations attached to a route scope.
public struct RouteScopeDeclaration: Sendable, Hashable {
    let branch: AnyHashable?
    let routes: [AnyRouteDeclaration]

    init(routes: [AnyRouteDeclaration]) {
        self.branch = nil
        self.routes = routes
    }

    init<Branch: Hashable>(branch: Branch, routes: [AnyRouteDeclaration]) {
        self.branch = AnyHashable(branch)
        self.routes = routes
    }
}

extension [RouteScopeDeclaration] {
    func containsPresentationKind(_ kind: RoutePresentationKind) -> Bool {
        flatMap(\.routes).contains {
            $0.drivesPresentation && $0.presentationKind == kind
        }
    }
}

/// A value accepted by ``SwiftUICore/View/routes(id:_:)``.
///
/// ``Push``, ``Sheet``, and ``Cover`` conform to this protocol.
public protocol RouteDeclaration {
    var _routeDeclarations: [AnyRouteDeclaration] { get }
}

/// Presentation priority for ``Sheet`` and ``Cover`` declarations.
///
/// ```swift
/// Cover(LoginRoute.self, priority: .high)
/// ```
public enum RoutePriority: Hashable, Sendable {
    /// Presents from the declaring scope.
    ///
    /// - Important: Normal-priority requests are ignored while a high-priority context is
    ///   active, unless they are declared inside that context.
    case normal

    /// Presents above normal-priority routes.
    ///
    /// - Important: High-priority requests from normal content replace the active
    ///   high-priority context. From inside that context, they behave as local navigation.
    case high
}
