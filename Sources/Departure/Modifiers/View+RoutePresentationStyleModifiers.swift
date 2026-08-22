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

extension View {
    /// Installs the presentation hosts for the styles present in `declarations`.
    ///
    /// Each style occupies an independent, stable background slot. The slot's host is present only
    /// while that style is declared — notably `navigationDestination` (push) is never attached when
    /// no push exists, so scopes that never push don't require a surrounding `NavigationStack`.
    func routePresentationStyleModifiers(
        for declarations: [RouteScopeDeclaration],
        hostedBy presentationHostID: RoutePresentationHostID
    ) -> some View {
        self
            .background {
                if declarations.containsPresentationKind(.push) {
                    presentationHost
                        .modifier(PushPresentationStyleModifier(presentationHostID: presentationHostID))
                }
            }
            .background {
                if declarations.containsPresentationKind(.sheet) {
                    presentationHost
                        .modifier(SheetPresentationStyleModifier(presentationHostID: presentationHostID))
                }
            }
            .background {
                if declarations.containsPresentationKind(.cover(.slide)) {
                    presentationHost
                        .modifier(CoverSlidePresentationStyleModifier(presentationHostID: presentationHostID))
                }
            }
            .background {
                if declarations.containsPresentationKind(.cover(.fade)) {
                    presentationHost
                        .modifier(CoverFadePresentationStyleModifier(presentationHostID: presentationHostID))
                }
            }
    }

    private var presentationHost: some View {
        Color.clear.frame(width: 0, height: 0)
    }
}
