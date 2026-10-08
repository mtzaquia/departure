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
    public static func buildExpression(_ expression: RouteMap) -> [RouteScopeDeclaration] { expression.declarations }
    public static func buildExpression(_ expression: ModalRouteMap) -> [RouteScopeDeclaration] { expression.declarations }
    public static func buildExpression(_ expression: Branches) -> [RouteScopeDeclaration] { expression.declarations }
    public static func buildExpression<S>(_ expression: Branch<S>) -> [RouteScopeDeclaration] { expression.routeScopeDeclarations }
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
    public static func buildExpression(_ expression: ModalRouteMap) -> [RouteScopeDeclaration] { expression.declarations }
}

/// Composes modal entries for a high or critical space.
///
/// Only sheets, covers, and other modal maps are accepted at this level.
/// Each entry's child builder accepts the full route declaration language.
public struct ModalRouteMap: Sendable {
    let declarations: [RouteScopeDeclaration]

    /// Creates reusable modal declarations without adding a navigation scope.
    public init(@ModalRouteDeclarationBuilder _ declarations: () -> [RouteScopeDeclaration]) {
        self.declarations = declarations()
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
    /// Creates declarations and optionally names their receiving scope for ID-based unwinding.
    ///
    /// A scope accepts one explicit ID across its containing declaration and composed maps.
    /// Conflicting IDs report a diagnostic and disable that scope's explicit unwind target.
    public init(id: AnyHashable? = nil, @RouteDeclarationBuilder _ declarations: () -> [RouteScopeDeclaration]) {
        self.declarations = (id.map { [.init(scopeID: $0)] } ?? []) + declarations()
    }
}

/// All definitions for a routing owner, including optional elevated root presentations.
public struct RootRouteMap: Sendable {
    let scopeID: AnyHashable?
    let declarations: [RouteScopeDeclaration]
    /// Creates the default flow and optional modal entry catalogs for elevated spaces.
    /// - Parameter id: An explicit unwind name for the default root scope.
    public init(
        id: AnyHashable? = nil,
        @RouteDeclarationBuilder _ routes: () -> [RouteScopeDeclaration],
        @ModalRouteDeclarationBuilder highPriority: () -> [RouteScopeDeclaration] = { [] },
        @ModalRouteDeclarationBuilder criticalPriority: () -> [RouteScopeDeclaration] = { [] }
    ) {
        scopeID = id
        declarations = routes()
            + highPriority().map { $0.withPriority(.high) }
            + criticalPriority().map { $0.withPriority(.critical) }
    }
}
