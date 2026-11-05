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
/// WithRouter(routes: AppRoutes.root) {
///     AppView()
/// }
/// ```
public struct WithRouter<Content: View>: View {
    @State private var router: RouterEngine
    @ViewBuilder private let content: Content

    public var body: some View {
        content
            .routingAutomatically()
            .routeScopeEnvironment(router.root, router: router)
            .environment(\.routerEngine, router)
    }

    /// Creates the application's routing host with local and global declarations.
    /// - Parameters:
    ///   - routes: Definitions shared by this routing owner.
    ///   - router: An optional owner handle for app-level navigation.
    ///   - content: The application's root content.
    public init(routes: RootRouteMap, router: RootRouter? = nil, @ViewBuilder content: () -> Content) {
        let engine = router?.engine ?? RouterEngine(routes: routes)
        engine.configureMap(routes)
        self._router = State(wrappedValue: engine)
        self.content = content()
    }
}
