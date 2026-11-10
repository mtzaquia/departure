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

/// A compatibility name for ``GlobalMap``, without priority ordering.
///
/// Its sheets and covers remain globally available from ``RootRouteMap`` and
/// present above the foreground flow in the existing window.
@available(*, deprecated, renamed: "GlobalMap")
public typealias HighPriority = GlobalMap

/// A compatibility name for ``GlobalMap``, without priority ordering.
///
/// It has the same global availability and presentation behavior as
/// ``HighPriority``; neither alias takes precedence over the other.
@available(*, deprecated, renamed: "GlobalMap")
public typealias CriticalPriority = GlobalMap

/// Legacy priority values retained for source compatibility.
///
/// These values no longer affect presentation, navigation, or dismissal.
@available(*, deprecated, message: "Priority spaces are no longer supported. Declare shared sheets and covers in GlobalMap.")
public enum RoutePriority: Int, Comparable, Hashable, Sendable {
    /// The legacy default value; all presentation metadata now reports this value.
    case `default`
    /// A legacy value with no routing effect.
    case high
    /// A legacy value with no routing effect.
    case critical

    /// Preserves the legacy numeric ordering without affecting routing.
    public nonisolated static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension RoutePresentation {
    /// Returns `.default` for every destination, including global routes.
    ///
    /// Priority is no longer part of presentation behavior. Use ``isGlobalRoute`` to
    /// determine whether the matched declaration belongs to a global map.
    @available(*, deprecated, message: "Always returns .default. Use isGlobalRoute to identify global declarations.")
    public var priority: RoutePriority { .default }
}

extension RootRouter {
    /// Captures the current foreground scope without priority filtering.
    ///
    /// This compatibility accessor is equivalent to ``current``. Use ``root``
    /// when an external entry point needs the permanent application root.
    @available(*, deprecated, message: "Use root for external navigation or current for foreground navigation. This accessor returns current.")
    public var `default`: Router { current }

    /// Warns that priority spaces no longer exist and leaves navigation unchanged.
    /// - Parameter priority: A legacy value that is ignored.
    /// - Returns: Always `false`.
    @available(*, deprecated, message: "No effect. Use a scoped router's unwind(_:) or resetToRoot() to dismiss routes.")
    @discardableResult
    public func dismissSpace(_ priority: RoutePriority) async -> Bool {
        LegacyPriorityDismissalWarning.ownerSpace.emit()
        return false
    }

    /// Warns that priority spaces no longer exist and leaves navigation unchanged.
    /// - Returns: Always `false`.
    @available(*, deprecated, message: "No effect. Use root.resetToRoot() to dismiss the application's navigation.")
    @discardableResult
    public func dismissSpaces() async -> Bool {
        LegacyPriorityDismissalWarning.allSpaces.emit()
        return false
    }
}

extension Router {
    /// Warns that priority spaces no longer exist and leaves navigation unchanged.
    /// - Returns: Always `false`, including when this router's scope is no longer live.
    @available(*, deprecated, message: "No effect. Use unwind(_:) or resetToRoot() to dismiss routes.")
    @discardableResult
    public func dismissSpace() async -> Bool {
        LegacyPriorityDismissalWarning.scopedSpace.emit()
        return false
    }
}

extension WithRouter {
    /// Creates the routing host while ignoring the legacy detached-window customizer.
    ///
    /// All destinations now inherit the presenting SwiftUI hierarchy in the existing
    /// window. The `windowDestination` closure is neither stored nor evaluated.
    /// Move shared configuration above this host or into destination builders.
    ///
    /// - Parameters:
    ///   - routes: Definitions shared by this routing owner.
    ///   - router: An optional owner handle for app-level navigation.
    ///   - content: The application's root content.
    ///   - windowDestination: A legacy customizer that is ignored.
    @available(*, deprecated, message: "windowDestination is ignored. Configure the existing view hierarchy or destination builders instead.")
    public init<WindowContent: View>(
        routes: RootRouteMap,
        router: RootRouter? = nil,
        @ViewBuilder _ content: () -> Content,
        @ViewBuilder windowDestination: @escaping (RouteView, EnvironmentValues) -> WindowContent
    ) {
        self.init(routes: routes, router: router, content: content)
    }
}

enum LegacyPriorityDismissalWarning: String, CaseIterable {
    case scopedSpace = "Router.dismissSpace()"
    case ownerSpace = "RootRouter.dismissSpace(_:)"
    case allSpaces = "RootRouter.dismissSpaces()"

    var renderedMessage: String {
        let trace = DepartureLogTrace.id.map { "[\($0)]" } ?? ""
        return "[compatibility]\(trace) ⊘ \(rawValue) has no effect because priority spaces no longer exist. "
            + "Use a scoped router's unwind(_:) or resetToRoot(); navigation is unchanged and false is returned."
    }

    func emit() {
        log.departureWarning(renderedMessage)
    }
}
