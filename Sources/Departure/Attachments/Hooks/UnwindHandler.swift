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
///     UnwindHandler(TransactionRoute.self) { route in
///         refresh()
///     }
/// }
/// ```
@_spi(WIP) public struct UnwindHandler<R: Route>: HookDeclaration, Sendable {
    let declaration: AnyHookDeclaration

    /// Creates an unwind handler.
    public init(
        _ routeType: R.Type,
        handle: @escaping @MainActor @Sendable (R) -> Void
    ) {
        self.declaration = AnyHookDeclaration(
            kind: .unwindHandler(
                routeType,
                AnyUnwindHandler { route in
                    guard let route = route as? R else {
                        log.departureWarning(
                            """
                            Unwind handler type mismatch for \(String(describing: routeType)):
                            expected \(R.self), got \(type(of: route))."
                            """
                        )
                        return
                    }

                    handle(route)
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
    let invoke: @MainActor (any Route) -> Void

    init(invoke: @escaping @MainActor (any Route) -> Void) {
        self.invoke = invoke
    }
}
