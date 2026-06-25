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
/// The handler runs after the unwind request is accepted. The router does not wait for the handler
/// body to finish before continuing the unwind. If the handler presents another route, that request
/// is deferred until the active navigation has finished.
///
/// ```swift
/// .hooks {
///     UnwindHandler(TransactionRoute.self, expecting: TransactionResult.self) { result in
///         await refresh()
///     }
/// }
/// ```
public struct UnwindHandler<R: Route>: HookDeclaration, Sendable {
    let declaration: AnyHookDeclaration

    /// Creates an unwind handler.
    ///
    /// If this handler matches a ``Router/unwind(to:payload:)`` request, `handle` is scheduled when
    /// the unwind is accepted. The router does not wait for `handle` to return.
    public init<Payload>(
        _ routeType: R.Type,
        expecting payloadType: Payload.Type,
        handle: @escaping @MainActor @Sendable (Payload) async -> Void
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

                    await handle(payload)
                }
            )
        )
    }

    /// Creates an unwind handler that ignores any payload sent with the unwind request.
    ///
    /// If this handler matches a ``Router/unwind(to:)`` request, `handle` is scheduled when the
    /// unwind is accepted.
    public init(
        _ routeType: R.Type,
        handle: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.declaration = AnyHookDeclaration(
            kind: .unwindHandler(
                routeType,
                AnyUnwindHandler { _, _, _ in
                    await handle()
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
    let invoke: @MainActor (any Route, Any?, AnyHashable) async -> Void

    init(invoke: @escaping @MainActor (any Route, Any?, AnyHashable) async -> Void) {
        self.invoke = invoke
    }
}
