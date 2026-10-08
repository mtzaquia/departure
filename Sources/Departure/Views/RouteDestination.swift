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

/// Associates domain route data with a feature view, without a retroactive conformance.
public struct RouteDestination<R: Route>: Sendable {
    let build: @MainActor @Sendable (R, RouteContext) -> AnyView
    public init<Content: View>(_ route: R.Type, @ViewBuilder destination: @escaping @MainActor @Sendable (R, RouteContext) -> Content) {
        build = { AnyView(destination($0, $1)) }
    }
}

/// Information about how this destination was presented.
public struct RoutePresentation: Hashable, Sendable {
    public enum Style: Hashable, Sendable {
        case push, replace, sheet, cover(Cover.Transition)
        var isModal: Bool {
            switch self { case .sheet, .cover: true; case .push, .replace: false }
        }
    }
    public let style: Style
    public let priority: RoutePriority
}

/// Values for this destination's own scope, refreshed as its environment changes.
public struct RouteContext {
    public let router: Router
    public let unwindRoute: UnwindRouteAction
    public let presentation: RoutePresentation
    public let environment: EnvironmentValues
}
