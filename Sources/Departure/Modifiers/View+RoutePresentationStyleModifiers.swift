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
    /// Hosts are attached conditionally so a style's host is never present unless that style is
    /// declared — notably `navigationDestination` (push) is only attached when a push is declared,
    /// so scopes that never push don't require a surrounding `NavigationStack`.
    ///
    /// - Important: Because the conditionals produce `_ConditionalContent`, the set of hosts
    ///   changing tears down and rebuilds this subtree. Callers must install this in a layer
    ///   detached from the scope's route-declaration installation lifecycle (e.g. a `background`);
    ///   otherwise the churn uninstalls freshly installed declarations.
    func routePresentationStyleModifiers(
        for declarations: [RouteScopeDeclaration]
    ) -> some View {
        self
            .applyIf(declarations.containsPresentationKind(.push)) {
                $0.modifier(PushPresentationStyleModifier())
            }
            .applyIf(declarations.containsPresentationKind(.sheet)) {
                $0.modifier(SheetPresentationStyleModifier())
            }
            .applyIf(declarations.containsPresentationKind(.cover(.slide))) {
                $0.modifier(CoverSlidePresentationStyleModifier())
            }
            .applyIf(declarations.containsPresentationKind(.cover(.fade))) {
                $0.modifier(CoverFadePresentationStyleModifier())
            }
    }
}
