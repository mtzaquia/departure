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

/// Installs a ``Router`` and the root route scope.
///
/// ```swift
/// WithRouter {
///     AppView()
/// }
/// ```
public struct WithRouter<Content: View>: View {
    @State var router: Router
    @ViewBuilder let content: Content

    /// The hosted content.
    public var body: some View {
        content
            .environment(\.routeScope, router.root)
            .environment(\.routing, RoutingAction(router: router))
            .background {
                HighPrioritySheetHost()
                HighPriorityCoverSlideHost()
                HighPriorityCoverFadeHost()
            }
            .environment(router)
    }

    /// Creates a router host.
    ///
    /// Pass a ``Router`` when app code needs to keep an explicit reference.
    public init(router: Router? = nil, @ViewBuilder content: () -> Content) {
        self._router = State(wrappedValue: router ?? Router())
        self.content = content()
    }
}
