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

@resultBuilder
public enum RouteDeclarationBuilder {
    public static func buildBlock(_ components: [RouteScopeDeclaration]...) -> [RouteScopeDeclaration] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [RouteScopeDeclaration]?) -> [RouteScopeDeclaration] { component ?? [] }
    public static func buildEither(first component: [RouteScopeDeclaration]) -> [RouteScopeDeclaration] { component }
    public static func buildEither(second component: [RouteScopeDeclaration]) -> [RouteScopeDeclaration] { component }
    public static func buildArray(_ components: [[RouteScopeDeclaration]]) -> [RouteScopeDeclaration] { components.flatMap { $0 } }
    public static func buildExpression(_ expression: some RouteDeclaration) -> [RouteScopeDeclaration] { [.init(routes: expression._routeDeclarations)] }
    public static func buildExpression(_ expression: RouteMap) -> [RouteScopeDeclaration] { expression.scopeDeclarations }
    public static func buildExpression(_ expression: ModalRouteMap) -> [RouteScopeDeclaration] { expression.scopeDeclarations }
    public static func buildExpression(_ expression: Branches) -> [RouteScopeDeclaration] { expression.declarations }
}

/// Builds elevated space entries. Only modal declarations can start a space;
/// each modal's child builder accepts the complete route declaration language.
@resultBuilder
public enum ModalRouteDeclarationBuilder {
    public static func buildBlock(_ components: [RouteScopeDeclaration]...) -> [RouteScopeDeclaration] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [RouteScopeDeclaration]?) -> [RouteScopeDeclaration] { component ?? [] }
    public static func buildEither(first component: [RouteScopeDeclaration]) -> [RouteScopeDeclaration] { component }
    public static func buildEither(second component: [RouteScopeDeclaration]) -> [RouteScopeDeclaration] { component }
    public static func buildArray(_ components: [[RouteScopeDeclaration]]) -> [RouteScopeDeclaration] { components.flatMap { $0 } }
    public static func buildExpression(_ expression: Sheet) -> [RouteScopeDeclaration] { [.init(routes: expression._routeDeclarations)] }
    public static func buildExpression(_ expression: Cover) -> [RouteScopeDeclaration] { [.init(routes: expression._routeDeclarations)] }
    public static func buildExpression(_ expression: ModalRouteMap) -> [RouteScopeDeclaration] { expression.scopeDeclarations }
}

/// Composes modal entries for a high or critical space.
///
/// Only sheets, covers, and other modal maps are accepted at this level.
/// Each entry's child builder accepts the full route declaration language.
public struct ModalRouteMap: Sendable {
    let declarations: [RouteScopeDeclaration]
    let destinations: [AnyRouteDestination]

    var scopeDeclarations: [RouteScopeDeclaration] {
        (destinations.isEmpty ? [] : [.init(destinations: destinations)]) + declarations
    }

    /// Creates reusable modal declarations and destination contributions.
    ///
    /// Composition does not add a navigation scope. Destination values contribute
    /// to one catalog for the complete root tree, with no map-specific overrides.
    ///
    /// - Parameters:
    ///   - declarations: Sheets, covers, and modal maps to compose.
    ///   - destinations: Typed builders and destination collections for this map.
    public init(
        @ModalRouteDeclarationBuilder _ declarations: () -> [RouteScopeDeclaration],
        @RouteDestinationBuilder destinations: () -> [AnyRouteDestination] = { [] }
    ) {
        self.declarations = declarations()
        self.destinations = destinations()
    }
}

/// Builds a branch group using only ``Branch`` declarations.
@resultBuilder
public enum BranchDeclarationBuilder {
    public static func buildBlock(_ components: [RouteScopeDeclaration]...) -> [RouteScopeDeclaration] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [RouteScopeDeclaration]?) -> [RouteScopeDeclaration] { component ?? [] }
    public static func buildEither(first component: [RouteScopeDeclaration]) -> [RouteScopeDeclaration] { component }
    public static func buildEither(second component: [RouteScopeDeclaration]) -> [RouteScopeDeclaration] { component }
    public static func buildArray(_ components: [[RouteScopeDeclaration]]) -> [RouteScopeDeclaration] { components.flatMap { $0 } }
    public static func buildExpression<S>(_ expression: Branch<S>) -> [RouteScopeDeclaration] { expression.routeScopeDeclarations }
}

/// Composable definitions. Inserting a map contributes declarations without creating a scope.
public struct RouteMap: Sendable {
    let declarations: [RouteScopeDeclaration]
    let destinations: [AnyRouteDestination]
    var scopeDeclarations: [RouteScopeDeclaration] {
        (destinations.isEmpty ? [] : [.init(destinations: destinations)]) + declarations
    }
    /// Creates declarations and optionally names their receiving scope for ID-based unwinding.
    ///
    /// A scope accepts one explicit ID across its containing declaration and composed maps.
    /// Conflicting IDs report a diagnostic and disable that scope's explicit unwind target.
    ///
    /// Destination values contribute to one catalog for the complete root tree.
    /// Reusing a value is allowed; distinct destination values for the same route
    /// type conflict across all composed maps, including the root's contributions.
    ///
    /// - Parameters:
    ///   - id: An optional unwind name for the receiving scope.
    ///   - declarations: Routes, branches, and maps contributed to the receiving scope.
    ///   - destinations: Typed builders and destination collections for this contribution.
    public init(
        id: AnyHashable? = nil,
        @RouteDeclarationBuilder _ declarations: () -> [RouteScopeDeclaration],
        @RouteDestinationBuilder destinations: () -> [AnyRouteDestination] = { [] }
    ) {
        self.declarations = (id.map { [.init(scopeID: $0)] } ?? []) + declarations()
        self.destinations = destinations()
    }
}

/// All definitions for a routing owner, including optional elevated root presentations.
/// Only this map declares elevated entries. Nested maps and route children declare
/// local navigation within their destination's owning space. An eligible scoped
/// router may request a higher-priority entry from this owner's root catalog.
public struct RootRouteMap: Sendable {
    let scopeID: AnyHashable?
    let declarations: [RouteScopeDeclaration]
    let destinations: [AnyRouteDestination]
    var scopeDeclarations: [RouteScopeDeclaration] {
        (destinations.isEmpty ? [] : [.init(destinations: destinations)]) + declarations
    }
    /// Creates the default flow, root priority groups, and shared destination builders.
    ///
    /// ``HighPriority`` and ``CriticalPriority`` are accepted only in this root
    /// builder. All destinations contributed by this map and its composed maps
    /// form one catalog. Each route type accepts one destination value; repeating
    /// that value is allowed. Different values conflict and disable that type
    /// throughout the tree. Destination views are evaluated only when rendered.
    ///
    /// - Parameters:
    ///   - id: An explicit unwind name for the default root scope.
    ///   - routes: The default declarations and optional elevated priority groups.
    ///   - destinations: Destination builders and collections available to this tree.
    public init(
        id: AnyHashable? = nil,
        @RootRouteDeclarationBuilder _ routes: () -> [RouteScopeDeclaration],
        @RouteDestinationBuilder destinations: () -> [AnyRouteDestination] = { [] }
    ) {
        scopeID = id
        declarations = routes()
        self.destinations = destinations()
    }
}

/// Builds root declarations, including high and critical priority entry groups.
///
/// Ordinary map and route child builders do not accept priority groups.
@resultBuilder
public enum RootRouteDeclarationBuilder {
    /// Combines root declaration groups.
    public static func buildBlock(_ components: [RouteScopeDeclaration]...) -> [RouteScopeDeclaration] { components.flatMap { $0 } }
    /// Includes an optional root declaration group.
    public static func buildOptional(_ component: [RouteScopeDeclaration]?) -> [RouteScopeDeclaration] { component ?? [] }
    /// Includes the first selected conditional group.
    public static func buildEither(first component: [RouteScopeDeclaration]) -> [RouteScopeDeclaration] { component }
    /// Includes the second selected conditional group.
    public static func buildEither(second component: [RouteScopeDeclaration]) -> [RouteScopeDeclaration] { component }
    /// Combines root declaration groups produced by a loop.
    public static func buildArray(_ components: [[RouteScopeDeclaration]]) -> [RouteScopeDeclaration] { components.flatMap { $0 } }
    /// Includes ordinary route declarations at the root.
    public static func buildExpression(_ expression: some RouteDeclaration) -> [RouteScopeDeclaration] { [.init(routes: expression._routeDeclarations)] }
    /// Composes a feature map and its destination builders at the root.
    public static func buildExpression(_ expression: RouteMap) -> [RouteScopeDeclaration] { expression.scopeDeclarations }
    /// Composes local modal declarations at the root.
    public static func buildExpression(_ expression: ModalRouteMap) -> [RouteScopeDeclaration] { expression.scopeDeclarations }
    /// Includes the root's branch container.
    public static func buildExpression(_ expression: Branches) -> [RouteScopeDeclaration] { expression.declarations }
    /// Includes root entries for the high priority space.
    public static func buildExpression(_ expression: HighPriority) -> [RouteScopeDeclaration] { expression.declarations }
    /// Includes root entries for the critical priority space.
    public static func buildExpression(_ expression: CriticalPriority) -> [RouteScopeDeclaration] { expression.declarations }
}

/// A group of modal entries for the high priority space, declared at the map root.
///
/// This group is accepted only by ``RootRouteMap``. Its entries can be sheets,
/// covers, or composed ``ModalRouteMap`` values; their children use ordinary local
/// route declarations. Priority groups cannot be nested.
public struct HighPriority: Sendable {
    let declarations: [RouteScopeDeclaration]
    /// Creates high priority modal entry declarations.
    /// - Parameter declarations: Modal entries available from the routing root.
    public init(@ModalRouteDeclarationBuilder _ declarations: () -> [RouteScopeDeclaration]) {
        self.declarations = declarations().map { $0.withPriority(.high) }
    }
}

/// A group of modal entries for the critical priority space, declared at the map root.
///
/// This group is accepted only by ``RootRouteMap``. Its entries can be sheets,
/// covers, or composed ``ModalRouteMap`` values; their children use ordinary local
/// route declarations. Priority groups cannot be nested.
public struct CriticalPriority: Sendable {
    let declarations: [RouteScopeDeclaration]
    /// Creates critical priority modal entry declarations.
    /// - Parameter declarations: Modal entries available from the routing root.
    public init(@ModalRouteDeclarationBuilder _ declarations: () -> [RouteScopeDeclaration]) {
        self.declarations = declarations().map { $0.withPriority(.critical) }
    }
}
