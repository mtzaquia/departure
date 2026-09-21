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

extension RouterEngine {
    func performAction<A: Action>(_ action: A, origin: RouteRequestOrigin? = nil) async {
        #if DEBUG
        guard DepartureLogTrace.id != nil else {
            await DepartureLogTrace.$id.withValue("a:\(action.id.departureDebugDescription)") {
                await performAction(action, origin: origin)
            }
            return
        }
        #endif

        log.departureDebug(.actionRequested(action: action))
        await performAction(action, hasRerouted: false, origin: origin)
    }

    @discardableResult
    func runAction<A: Action>(
        _ action: A,
        hasRerouted: Bool,
        logsStart: Bool = true,
        origin: RouteRequestOrigin? = nil
    ) async throws -> A.Output {
        guard let source = resolveRequestOrigin(origin)?.scope else { throw CancellationError() }
        do {
            let currentRoute: (any Route.Type)? = source.currentRoute.map { type(of: $0) }
            if logsStart {
                log.departureDebug(.actionRunning(action: action, currentRoute: currentRoute))
            }
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
                    let sourceScope = source
                    let continuationOwner = origin == nil ? nil : (nearestBranchPath(from: source)?.owner ?? root)
                    await requestRouteWhenReady(route, origin: origin)
                    let targetScope = continuationOwner?.activeLocalScope ?? currentRouteScope

                    if targetScope !== sourceScope || targetScope.isInstalledInView {
                        await waitForRouteScopeToInstall(targetScope)
                    }

                    await performAction(action, hasRerouted: true, origin: continuationOwner.map { RouteRequestOrigin(scope: $0.activeLocalScope) })
                }
                
                throw CancellationError()

            case let .invocationError(error):
                log.departureDebug(.actionFailed(action: action, error: error))
                throw error
            }
        }
    }
}

private extension RouterEngine {
    func waitForRouteScopeToInstall(_ routeScope: RouteScope) async {
        await routeScope.ledger.waitUntilInstalled()
    }

    func performAction<A: Action>(_ action: A, hasRerouted: Bool, origin: RouteRequestOrigin? = nil) async {
        guard let source = resolveRequestOrigin(origin)?.scope else { return }
        if let interceptor = source.firstInterceptor(for: A.self) {
            log.departureDebug(.actionIntercepted(action: action, scope: source))
            await interceptor.invoke(self, action, hasRerouted, origin)
            log.departureDebug(.actionInterceptorFinished(action: action))
            return
        }

        let currentRoute: (any Route.Type)? = source.currentRoute.map { type(of: $0) }
        log.departureDebug(.actionNoInterceptor(
            action: action,
            scope: source,
            currentRoute: currentRoute
        ))

        // A top-level action dispatch is fire-and-forget. Interceptors can
        // capture invocation failures by catching errors from `invocation()`.
        do {
            _ = try await runAction(action, hasRerouted: hasRerouted, logsStart: false, origin: origin)
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
