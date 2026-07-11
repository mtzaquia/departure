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
        log.departureDebug(.actionRequested(action: action))
        await performAction(action, hasRerouted: false)
    }

    @discardableResult
    func runAction<A: Action>(_ action: A, hasRerouted: Bool) async throws -> A.Output {
        do {
            let currentRoute: (any Route.Type)? = currentRouteScope.currentRoute.map { type(of: $0) }
            log.departureDebug(.actionRunning(action: action, currentRoute: currentRoute))
            let output = try await action.attemptAction(in: ActionContext(currentRoute: currentRoute))
            log.departureDebug(.actionCompleted(action: action))
            return output
        } catch let error {
            switch error {
            case .reroute where hasRerouted:
                log.departureDebug(.actionRerouteDropped(action: action))
                throw CancellationError()

            case let .reroute(route):
                log.departureDebug(.actionRerouteRequested(action: action, route: route))
                Task {
                    let sourceScope = currentRouteScope
                    await requestRouteWhenReady(route)
                    let targetScope = currentRouteScope

                    if targetScope !== sourceScope || targetScope.isInstalledInView {
                        await waitForRouteScopeToInstall(targetScope)
                    }

                    await performAction(action, hasRerouted: true)
                }
                
                throw CancellationError()

            case let .invocationError(error):
                log.departureDebug(.actionFailed(action: action, error: error))
                throw error
            }
        }
    }
}

private extension Router {
    func waitForRouteScopeToInstall(_ routeScope: RouteScope) async {
        await routeScope.viewLifecycle.waitUntilInstalled()
    }

    func performAction<A: Action>(_ action: A, hasRerouted: Bool) async {
        if let interceptor = currentRouteScope.firstInterceptor(for: A.self) {
            log.departureDebug(.actionIntercepted(action: action, scope: currentRouteScope))
            await interceptor.invoke(self, action, hasRerouted)
            log.departureDebug(.actionInterceptorFinished(action: action))
            return
        }

        log.departureDebug(.actionNoInterceptor(action: action, scope: currentRouteScope))

        // A top-level action dispatch is fire-and-forget. Interceptors can
        // capture invocation failures by catching errors from `invocation()`.
        do {
            _ = try await runAction(action, hasRerouted: hasRerouted)
        } catch {
            log.departureDebug(.actionDirectInvocationEnded(action: action, error: error))
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
