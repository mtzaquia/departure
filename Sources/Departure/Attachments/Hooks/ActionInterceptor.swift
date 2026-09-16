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

/// Intercepts an ``Action`` requested from the declaring route scope.
///
/// Call ``ActionInvocation/callAsFunction()`` to run the intercepted action.
///
/// ```swift
/// .hooks {
///     ActionInterceptor(SaveAction.self) { invocation in
///         try? await invocation()
///     }
/// }
/// ```
public struct ActionInterceptor<A: Action>: HookDeclaration, Sendable {
    let declaration: AnyHookDeclaration

    /// Creates an action interceptor.
    public init(
        _ actionType: A.Type,
        intercept: @escaping @MainActor @Sendable (ActionInvocation<A.Output>) async -> Void
    ) {
        self.declaration = AnyHookDeclaration(
            kind: .actionInterceptor(
                actionType,
                AnyActionInterceptor { router, action, hasRerouted, origin async in
                    guard let action = action as? A else {
                        log.departureWarning(
                            "Action interceptor for `\(String(reflecting: actionType))` received "
                                + "`\(String(reflecting: type(of: action)))`; expected "
                                + "`\(String(reflecting: A.self))`. The action was ignored."
                        )
                        return
                    }

                    let invocation = ActionInvocation<A.Output> {
                        try await router.runAction(action, hasRerouted: hasRerouted, origin: origin)
                    }

                    await intercept(invocation)
                }
            )
        )
    }

    public var _hookDeclarations: [AnyHookDeclaration] {
        [declaration]
    }
}

// MARK: - Supporting types

struct AnyActionInterceptor {
    let invoke: @MainActor (RouterEngine, any Action, Bool, RouteRequestOrigin?) async -> Void

    init(invoke: @escaping @MainActor (RouterEngine, any Action, Bool, RouteRequestOrigin?) async -> Void) {
        self.invoke = invoke
    }
}
