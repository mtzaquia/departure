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

/// Handles a matching route when it unwinds.
///
/// Unwinds can be requested with ``UnwindRouteAction`` from ``UnwindRoute`` for
/// captured route-scope dismissal, or with ``Router/unwind(_:)`` and
/// ``Router/unwind(_:payload:)`` for explicit router-level targets.
/// Explicit whole-space removal and native Back or dismissal also notify handlers.
/// Presenting a route never notifies them: ancestor crawlback, equality reuse,
/// and replacement can remove destinations without being an unwind request.
///
/// Lookup starts at the surviving landing scope and climbs to its space root.
/// If no handler matches there, lookup continues from each surviving lower
/// priority space's current scope, nearest priority first. A conflicting handler
/// stops lookup. Covered scopes can receive notification without gaining routing authority.
///
/// Native and explicit unwinds enter the handler after acceptance and before the
/// path changes. The router continues once the handler suspends; it does not wait
/// for the asynchronous body to finish. A presentation requested by the handler
/// waits until the active navigation has finished, then rechecks source membership
/// and priority coverage. It is dropped if a higher space still covers its source.
///
/// Handlers in one scope compose by route and expected payload type. Duplicate keys
/// report a warning and are disabled until only one declaration remains.
/// For a provided payload, an exact type match takes precedence; otherwise, a sole
/// compatible typed handler can receive it. Multiple compatible keys without an
/// exact match warn and stop lookup. Payload-free handlers receive only payload-free
/// unwinds, including native dismissal; they never consume a provided payload.
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
    /// If this handler matches an ``UnwindRouteAction/callAsFunction(payload:)`` or
    /// ``Router/unwind(_:payload:)`` request, `handle` is scheduled when the unwind is accepted.
    /// Delivery starts before the path changes. The router does not wait for `handle` to return.
    /// An optional `nil` passed to the payload overload is still a typed payload.
    public init<Payload>(
        _ routeType: R.Type,
        expecting payloadType: Payload.Type,
        handle: @escaping @MainActor @Sendable (Payload) async -> Void
    ) {
        self.declaration = AnyHookDeclaration(
            kind: .unwindHandler(
                routeType,
                AnyUnwindHandler(payloadType: payloadType, acceptsPayload: { $0 is Payload }) { route, payload, declaringScopeID in
                    guard let payload = payload as? Payload else {
                        log.departureInfo(
                            "Unwind handler for `\(String(reflecting: routeType))` in scope "
                                + "`\(String(describing: declaringScopeID))` received payload "
                                + "`\(payload.map { String(reflecting: type(of: $0)) } ?? "nil")`; "
                                + "expected `\(String(reflecting: Payload.self))`. The handler was skipped."
                        )
                        return
                    }

                    await handle(payload)
                }
            )
        )
    }

    /// Creates an unwind handler for payload-free unwind requests.
    ///
    /// If this handler matches an ``UnwindRouteAction/callAsFunction()`` or
    /// ``Router/unwind(_:)`` request, `handle` is scheduled when the unwind is accepted.
    /// Native dismissal uses the same before-commit timing.
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
    let payloadType: Any.Type?
    let acceptsPayload: @MainActor (Any?) -> Bool
    let invoke: @MainActor (any Route, Any?, AnyHashable) async -> Void

    init(payloadType: Any.Type? = nil,
         acceptsPayload: @escaping @MainActor (Any?) -> Bool = { $0 == nil },
         invoke: @escaping @MainActor (any Route, Any?, AnyHashable) async -> Void) {
        self.payloadType = payloadType
        self.acceptsPayload = acceptsPayload
        self.invoke = invoke
    }
}
