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

/// An equivalent name for the presentation value shared by destination contexts and the environment.
public typealias RoutePresentationState = RoutePresentation

extension RoutePresentation {
    func presenting(_ declaration: AnyRouteDeclaration,
                    effectiveStyle: RoutePresentation.Style? = nil) -> Self {
        let style = effectiveStyle ?? declaration.presentationKind
        return Self(effectivePresentationStyle: style,
                    isWithinSheetRoute: style.isModal ? style == .sheet : isWithinSheetRoute,
                    isGlobalRoute: declaration.isGlobal,
                    declaredStyle: declaration.presentationKind,
                    declaredCompactAdaptation: declaration.presentation.declaredCompactAdaptation)
    }
}

public extension EnvironmentValues {
    /// Live presentation information for this destination and its enclosing modal.
    ///
    /// Departure installs this value automatically before evaluating destination
    /// builders. ``RouteContext/presentation`` supplies the same value directly.
    /// Outside a routed destination, the style is `nil` and both flags are `false`.
    @Entry var routePresentation = RoutePresentation()
}

extension RoutePresentation {
    /// Uses the presenter's traits, rather than a sheet's potentially narrower content.
    func effectiveStyle(inCompactSizeClass compact: Bool) -> Style {
        #if canImport(UIKit)
        if declaredStyle == .sheet, declaredCompactAdaptation == .cover, compact { return .cover(.slide) }
        return declaredStyle
        #else
        return declaredStyle.isModal ? .sheet : declaredStyle
        #endif
    }
}
