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

import Foundation
import SwiftUI

public extension View {
    /// Declares hooks for the current route scope.
    ///
    /// Multiple modifiers in one scope compose distinct action-interceptor and unwind-handler keys.
    /// Updating or removing a modifier changes only its own declarations and captured callbacks.
    /// Interceptors are keyed by action type; unwind handlers by route and expected payload type,
    /// with a separate key for payload-free handlers. Duplicate keys disable that hook and report
    /// a warning until only one declaration remains. Hooks stop participating when their scope
    /// leaves navigation, including while an outgoing view is retained for dismissal.
    ///
    /// ```swift
    /// DetailView()
    ///     .hooks {
    ///         ActionInterceptor(SaveAction.self) { invocation in
    ///             try? await invocation()
    ///         }
    ///     }
    /// ```
    func hooks(
        @HookBuilder _ declarations: () -> [AnyHookDeclaration]
    ) -> some View {
        modifier(
            HooksModifier(
                declarations: declarations()
            )
        )
    }
}

// MARK: - Private

private struct HooksModifier: ViewModifier {
    let declarations: [AnyHookDeclaration]

    @State private var attachment = RouteScopeAttachment(kind: .hooks)

    @Environment(\.routeScope) private var routeScope

    func body(content: Content) -> some View {
        content
            .onLifecycleEvent { lifecycleView, id, event in
                let sourceID = attachment.id
                attachment.handle(event, id: id, target: routeScope, view: lifecycleView,
                    apply: { $0.installHookDeclarations(sourceID: sourceID, hookDeclarations: declarations) },
                    remove: { $0.uninstallHookDeclarations(sourceID: sourceID) })
            }
    }
}
