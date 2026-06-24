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

/// Work that runs from the current route scope.
///
/// Use actions for user intent that may need to run locally, be intercepted, or route first.
///
/// ```swift
/// struct ShareTransactionAction: Action {
///     func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
///         guard context.isRunning(in: TransactionRoute.self) else {
///             throw .reroute(TransactionRoute())
///         }
///
///         doSomeWork()
///     }
/// }
/// ```
///
/// - Important: Actions start from the top-most presented scope. They do not crawl backward
///   for hooks.
public protocol Action: Identifiable, Sendable where ID == ObjectIdentifier {
    /// The value returned when an ``ActionInterceptor`` calls ``ActionInvocation/callAsFunction()``.
    associatedtype Output = Void

    /// Runs the action.
    ///
    /// Throw ``ActionInvocationError/reroute(_:)`` when a route is required first.
    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) -> Output
}

public extension Action {
    /// A type-based identity for actions that do not need instance identity.
    nonisolated var id: ObjectIdentifier {
        ObjectIdentifier(Self.self)
    }
}

// MARK: - Supporting types

/// Context passed into ``Action/attemptAction(in:)``.
public struct ActionContext: Sendable {
    private let currentRoute: (any Route.Type)?

    init(currentRoute: (any Route.Type)?) {
        self.currentRoute = currentRoute
    }

    /// Checks whether the action is running in a destination for the given ``Route`` type.
    ///
    /// ```swift
    /// guard context.isRunning(in: TransactionRoute.self) else {
    ///     throw .reroute(TransactionRoute())
    /// }
    /// ```
    public func isRunning(in route: (some Route).Type) -> Bool {
        route == currentRoute
    }
}

/// A callable wrapper passed to ``ActionInterceptor``.
///
/// ```swift
/// ActionInterceptor(SaveAction.self) { invocation in
///     try? await invocation()
/// }
/// ```
public struct ActionInvocation<Output> {
    private let run: @MainActor () async throws -> Output

    init(run: @escaping @MainActor () async throws -> Output) {
        self.run = run
    }

    /// Runs the intercepted action.
    public func callAsFunction() async throws -> Output {
        try await run()
    }
}

/// Control flow from ``Action/attemptAction(in:)``.
public enum ActionInvocationError: Error, @unchecked Sendable {
    /// Requests a route, then retries the action once from the new current scope.
    case reroute(_ route: any Route)

    /// Reports a real failure to the active ``ActionInterceptor``.
    case invocationError(Error)
}
