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

/// Handles a matching route when it unwinds to this scope.
///
/// ```swift
/// .hooks {
///     UnwindHandler(TransactionRoute.self, expecting: TransactionResult.self) { result in
///         refresh()
///     }
/// }
/// ```
public struct UnwindHandler<R: Route>: HookDeclaration, Sendable {
    let declaration: AnyHookDeclaration

    /// Creates an unwind handler.
    public init<Payload>(
        _ routeType: R.Type,
        expecting payloadType: Payload.Type,
        handle: @escaping @MainActor @Sendable (Payload) -> Void
    ) {
        self.declaration = AnyHookDeclaration(
            kind: .unwindHandler(
                routeType,
                AnyUnwindHandler { route, payload, declaringScopeID in
                    guard let payload = payload as? Payload else {
                        log.departureWarning(
                            """
                            Unwind handler payload mismatch for \(String(describing: routeType)):
                            hook scope \(String(describing: declaringScopeID)) expected \(Payload.self), got \(payload.map { String(describing: type(of: $0)) } ?? "nil").
                            """
                        )
                        return
                    }

                    handle(payload)
                }
            )
        )
    }

    /// Creates an unwind handler that ignores any payload sent with the unwind request.
    public init(
        _ routeType: R.Type,
        handle: @escaping @MainActor @Sendable () -> Void
    ) {
        self.declaration = AnyHookDeclaration(
            kind: .unwindHandler(
                routeType,
                AnyUnwindHandler { _, _, _ in
                    handle()
                }
            )
        )
    }

    public var _hookDeclarations: [AnyHookDeclaration] {
        [declaration]
    }
}

// MARK: - Supporting types

struct AnyUnwindHandler {
    let invoke: @MainActor (any Route, Any?, AnyHashable) -> Void

    init(invoke: @escaping @MainActor (any Route, Any?, AnyHashable) -> Void) {
        self.invoke = invoke
    }
}
