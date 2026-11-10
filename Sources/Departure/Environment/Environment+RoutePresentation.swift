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

/// The current destination's presentation and enclosing modal state.
///
/// Read this value with `@Environment(\.routePresentation)`. Departure updates it
/// when a sheet adapts as size classes change. Each environment read is a snapshot;
/// storing a copy does not subscribe that copy to later changes.
public struct RoutePresentationState: Hashable, Sendable {
    /// The destination's current style, or `nil` outside a routed destination.
    ///
    /// A sheet with ``Sheet/CompactAdaptation/cover`` reports `.cover(.slide)`
    /// when either of its presenter's size classes is compact. Pushed and replaced
    /// destinations report `.push` and `.replace`, even inside a modal.
    /// On macOS, both sheet and cover routes use native sheets and report `.sheet`.
    public let effectivePresentationStyle: RoutePresentation.Style?

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

    init(effectivePresentationStyle: RoutePresentation.Style? = nil,
         isWithinSheetRoute: Bool = false, isGlobalRoute: Bool = false) {
        self.effectivePresentationStyle = effectivePresentationStyle
        self.isWithinSheetRoute = isWithinSheetRoute
        self.isGlobalRoute = isGlobalRoute
    }

    func presenting(_ declaration: AnyRouteDeclaration,
                    effectiveStyle: RoutePresentation.Style? = nil) -> Self {
        let style = effectiveStyle ?? declaration.presentationKind
        return Self(effectivePresentationStyle: style,
                    isWithinSheetRoute: style.isModal ? style == .sheet : isWithinSheetRoute,
                    isGlobalRoute: declaration.isGlobal)
    }
}

public extension EnvironmentValues {
    /// Live presentation information for this destination and its enclosing modal.
    ///
    /// Departure installs this value automatically before evaluating destination
    /// builders. It is also available through ``RouteContext/environment``.
    /// Outside a routed destination, the style is `nil` and both flags are `false`.
    @Entry var routePresentation = RoutePresentationState()
}

extension RoutePresentation {
    /// Uses the presenter's traits, rather than a sheet's potentially narrower content.
    func effectiveStyle(inCompactSizeClass compact: Bool) -> Style {
        #if canImport(UIKit)
        if style == .sheet, compactAdaptation == .cover, compact { return .cover(.slide) }
        return style
        #else
        return style.isModal ? .sheet : style
        #endif
    }
}
