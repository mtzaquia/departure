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

/// Binds a domain route to a feature view without extending the route type.
///
/// Supply this value in a map's `destinations:` builder, independently of the
/// route's ``Push``, ``Replace``, ``Sheet``, or ``Cover`` declaration.
/// Its builder runs on the main actor with the requested route and the destination's
/// own routing context. Each composed ``RootRouteMap`` accepts one destination value
/// per route type. Reusing that value in multiple maps is allowed; distinct values
/// for the same type conflict throughout the tree. Compose destination values
/// independently of route declarations with ``RouteDestinations``.
///
/// ```swift
/// let profile = RouteDestination(ProfileRoute.self) { route, context in
///     ProfileView(userID: route.userID)
/// }
///
/// let routes = RootRouteMap {
///     Push(ProfileRoute.self)
/// } destinations: {
///     profile
/// }
/// ```
public struct RouteDestination<R: Route>: Sendable {
    let identity = UUID()
    let build: @MainActor @Sendable (R, RouteContext) -> AnyView

    /// Creates a reusable destination builder with its own identity for a route type.
    ///
    /// Copies retain that identity, including when added to destination collections.
    /// Creating another destination value for the same type creates a distinct binding.
    /// Construction is nonisolated and stores the builder without evaluating it.
    /// The builder runs on the main actor when the destination is rendered.
    ///
    /// - Parameters:
    ///   - route: The domain route type bound to this destination.
    ///   - destination: Builds a view from typed route data and the current rendering context.
    public nonisolated init<Content: View>(_ route: R.Type, @ViewBuilder destination: @escaping @MainActor @Sendable (R, RouteContext) -> Content) {
        build = { AnyView(destination($0, $1)) }
    }
}

/// A destination builder whose route type is retained without a generic parameter.
///
/// ``RouteDestinationBuilder`` uses these values to compose builders for different
/// route types. Erasing a destination does not declare a navigation position or
/// evaluate its builder.
public struct AnyRouteDestination: Sendable, Hashable {
    private let identity: UUID
    let routeType: any Route.Type
    let build: @MainActor @Sendable (any Route, RouteContext) -> AnyView

    /// Stores a typed destination for composition with other destination builders.
    /// - Parameter destination: The builder and route type to retain.
    public init<R: Route>(_ destination: RouteDestination<R>) {
        identity = destination.identity
        routeType = R.self
        build = { route, context in
            // A declaration is matched by concrete route type before rendering.
            destination.build(route as! R, context)
        }
    }

    /// Compares the original destination values by identity, independently of route equality.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }
    /// Hashes this destination's identity.
    public nonisolated func hash(into hasher: inout Hasher) { hasher.combine(identity) }
}

/// The current destination's presentation and enclosing modal state.
///
/// Departure supplies the same value through ``RouteContext/presentation`` and
/// `@Environment(\.routePresentation)`. Size-class changes refresh both access paths
/// during view construction. A stored copy is a snapshot.
public struct RoutePresentation: Hashable, Sendable {
    /// The presentation style used for this destination.
    public enum Style: Hashable, Sendable {
        /// Pushes onto a navigation stack.
        case push
        /// Replaces the declaring scope's content without a Back entry.
        case replace
        /// Presents a sheet.
        case sheet
        /// Presents a cover with the declared transition.
        case cover(Cover.Transition)
        var isModal: Bool {
            switch self { case .sheet, .cover: true; case .push, .replace: false }
        }
    }
    /// The destination's current style, or `nil` outside a routed destination.
    ///
    /// A sheet with ``Sheet/CompactAdaptation/cover`` reports `.cover(.slide)`
    /// when either of its presenter's size classes is compact. Pushed and replaced
    /// destinations report `.push` and `.replace`, even inside a modal.
    /// On macOS, both sheet and cover routes use native sheets and report `.sheet`.
    public let effectivePresentationStyle: Style?

    /// Whether the nearest enclosing Departure modal currently appears as a sheet.
    ///
    /// This value passes through pushes, replacements, and branches. A new modal
    /// overrides it: a cover, including an adapted sheet, sets it to `false`.
    public let isWithinSheetRoute: Bool

    /// Whether this destination occurrence was presented from the root global catalog.
    ///
    /// This describes the current route, independently of its enclosing routes.
    /// A local destination pushed inside a global sheet reads `false`.
    public let isGlobalRoute: Bool

    /// The declared style, including a cover's transition.
    ///
    /// An adapted sheet continues to report `.sheet`. Outside a routed destination,
    /// this compatibility accessor returns `.replace`.
    @available(*, deprecated, message: "Use effectivePresentationStyle for the current presentation style, including sheet adaptation.")
    public var style: Style { declaredStyle }

    /// The declared sheet's compact adaptation, or `.none` for other styles.
    @available(*, deprecated, message: "Use effectivePresentationStyle to inspect the current presentation after adaptation.")
    public var compactAdaptation: Sheet.CompactAdaptation { declaredCompactAdaptation }

    /// Whether this occurrence was presented from the root global catalog.
    @available(*, deprecated, renamed: "isGlobalRoute")
    public var isGlobal: Bool { isGlobalRoute }

    let declaredStyle: Style
    let declaredCompactAdaptation: Sheet.CompactAdaptation

    init(effectivePresentationStyle: Style? = nil, isWithinSheetRoute: Bool = false,
         isGlobalRoute: Bool = false, declaredStyle: Style? = nil,
         declaredCompactAdaptation: Sheet.CompactAdaptation = .none) {
        self.effectivePresentationStyle = effectivePresentationStyle
        self.isWithinSheetRoute = isWithinSheetRoute
        self.isGlobalRoute = isGlobalRoute
        self.declaredStyle = declaredStyle ?? effectivePresentationStyle ?? .replace
        self.declaredCompactAdaptation = declaredCompactAdaptation
    }

    init(style: Style, compactAdaptation: Sheet.CompactAdaptation = .none,
         isGlobal: Bool = false) {
        self.init(effectivePresentationStyle: style, isWithinSheetRoute: style == .sheet,
                  isGlobalRoute: isGlobal, declaredStyle: style,
                  declaredCompactAdaptation: compactAdaptation)
    }
}

/// Values supplied by Departure for a destination's own scope during view construction.
///
/// Contexts are created on the main actor. Routing actions retain their scope identity:
/// they do not retarget another destination after that scope leaves navigation state.
/// Read environment values during builder evaluation, including the destination's own
/// routing values. SwiftUI environment changes reevaluate the builder. Copy individual
/// environment values for later use; retained contexts do not provide an environment
/// lookup contract outside view construction.
public struct RouteContext {
    /// The router bound to this destination's scope.
    public let router: Router
    /// Unwinds this exact scope, optionally delivering a payload.
    public let unwindRoute: UnwindRouteAction
    /// The same live presentation value supplied by `EnvironmentValues.routePresentation`.
    ///
    /// This value refreshes when the destination builder is reevaluated, including
    /// after size-class changes. Retained copies remain snapshots.
    public let presentation: RoutePresentation
    /// The environment visible to this destination during the current builder evaluation.
    public let environment: EnvironmentValues
}
