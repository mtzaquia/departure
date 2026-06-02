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

extension Router {
    func performAction<A: Action>(_ action: A) async {
#if DEBUG
        log.departureDebug("Action requested: \(action.departureDebugDescription).")
#endif
        await performAction(action, hasRerouted: false)
    }

    @discardableResult
    func runAction<A: Action>(_ action: A, hasRerouted: Bool) async throws -> A.Output {
        do {
            let currentRoute = currentRouteScope.currentRoute.map { type(of:$0) }
#if DEBUG
            log.departureDebug(
                "Action running: \(action.departureDebugDescription) in currentRoute: \(currentRoute.map { String(reflecting: $0) } ?? "nil")."
            )
#endif
            let output = try await action.attemptAction(in: ActionContext(currentRoute: currentRoute))
#if DEBUG
            log.departureDebug("Action completed: \(action.departureDebugDescription).")
#endif
            return output
        } catch let error {
            switch error {
            case .reroute where hasRerouted:
#if DEBUG
                log.departureDebug(
                    "Action reroute dropped: \(action.departureDebugDescription) already rerouted once."
                )
#endif
                throw CancellationError()

            case let .reroute(route):
#if DEBUG
                log.departureDebug(
                    "Action reroute requested: \(action.departureDebugDescription) -> \(route.departureDebugDescription)."
                )
#endif
                Task {
                    await requestRoute(route)
                    await performAction(action, hasRerouted: true)
                }
                
                throw CancellationError()

            case let .invocationError(error):
#if DEBUG
                log.departureDebug(
                    "Action failed: \(action.departureDebugDescription) error: \(String(describing: error))."
                )
#endif
                throw error
            }
        }
    }
}

private extension Router {
    func performAction<A: Action>(_ action: A, hasRerouted: Bool) async {
        if let interceptor = currentRouteScope.firstInterceptor(for: A.self) {
#if DEBUG
            log.departureDebug(
                "Action intercepted: \(action.departureDebugDescription) by \(currentRouteScope.departureDebugDescription)."
            )
#endif
            await interceptor.invoke(self, action, hasRerouted)
#if DEBUG
            log.departureDebug("Action interceptor finished: \(action.departureDebugDescription).")
#endif
            return
        }

#if DEBUG
        log.departureDebug(
            "Action has no interceptor: \(action.departureDebugDescription). Running directly from \(currentRouteScope.departureDebugDescription)."
        )
#endif

        // A top-level action dispatch is fire-and-forget. Interceptors can
        // capture invocation failures by catching errors from `invocation()`.
        do {
            _ = try await runAction(action, hasRerouted: hasRerouted)
        } catch {
#if DEBUG
            log.departureDebug(
                "Action direct invocation ended without delivery: \(action.departureDebugDescription), error: \(String(describing: error))."
            )
#endif
        }
    }
}

private extension RouteScope {
    func firstInterceptor(for actionType: (some Action).Type) -> AnyActionInterceptor? {
        for attachment in self.hookAttachments {
            if let candidateInterceptor = attachment.interceptor(for: actionType) {
                return candidateInterceptor
            }
        }

        return nil
    }
}
