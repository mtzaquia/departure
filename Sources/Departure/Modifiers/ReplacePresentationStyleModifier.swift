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

/// Renders a structural route slot without adding a navigation or modal entry.
struct ReplacePresentationStyleModifier: ViewModifier {
    let presentationHostID: RoutePresentationHostID
    let isEnabled: Bool

    @Environment(RouterEngine.self) private var router
    @Environment(\.routeScope) private var routeScope

    func body(content: Content) -> some View {
        let slot = router.routePresentationBinding(
            from: routeScope,
            matching: .replace,
            hostedBy: presentationHostID
        )
        let presentation = isEnabled ? slot.wrappedValue : nil

        renderedContent(content, presentation: presentation)
            .onChange(of: isEnabled) { _, enabled in
                guard !enabled, routeScope != nil else { return }
                slot.wrappedValue = nil
            }
    }

    @ViewBuilder
    private func renderedContent(_ content: Content, presentation: RoutePresentation?) -> some View {
        if let presentation {
            RouteView(scope: presentation.scope, providesNavigation: false)
                .id(presentation.id)
        } else {
            content
        }
    }
}
