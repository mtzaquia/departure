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

/// Builds destination collections from typed builders and other collections.
@resultBuilder
public enum RouteDestinationBuilder {
    /// Combines destination groups in their declaration order.
    public static func buildBlock(_ components: [AnyRouteDestination]...) -> [AnyRouteDestination] { components.flatMap { $0 } }
    /// Includes a destination group when its condition is satisfied.
    public static func buildOptional(_ component: [AnyRouteDestination]?) -> [AnyRouteDestination] { component ?? [] }
    /// Includes the first selected conditional group.
    public static func buildEither(first component: [AnyRouteDestination]) -> [AnyRouteDestination] { component }
    /// Includes the second selected conditional group.
    public static func buildEither(second component: [AnyRouteDestination]) -> [AnyRouteDestination] { component }
    /// Combines destination groups produced by a loop.
    public static func buildArray(_ components: [[AnyRouteDestination]]) -> [AnyRouteDestination] { components.flatMap { $0 } }
    /// Includes a typed destination without evaluating its view builder.
    public static func buildExpression<R: Route>(_ expression: RouteDestination<R>) -> [AnyRouteDestination] { [AnyRouteDestination(expression)] }
    /// Includes a destination that already retains its route type.
    public static func buildExpression(_ expression: AnyRouteDestination) -> [AnyRouteDestination] { [expression] }
    /// Composes an existing collection without evaluating its view builders.
    public static func buildExpression(_ expression: RouteDestinations) -> [AnyRouteDestination] { expression.destinations }
}

/// A reusable collection of feature destination builders, independent of a route map.
///
/// Collections compose typed ``RouteDestination`` values and other collections.
/// Construction stores their builders without evaluating them. Entries retain their
/// destination identities. When a root map is installed, repeated contributions of
/// the same destination value are allowed; different values for one route type
/// conflict across the complete tree.
///
/// ```swift
/// let destinations = RouteDestinations {
///     ProfileFeature.destination
///     SettingsFeature.destinations
/// }
/// ```
public struct RouteDestinations: Sendable {
    let destinations: [AnyRouteDestination]

    /// Creates a collection of destinations without declaring navigation positions.
    /// - Parameter destinations: Typed destination builders and collections to compose.
    public init(@RouteDestinationBuilder _ destinations: () -> [AnyRouteDestination]) {
        self.destinations = destinations()
    }
}
