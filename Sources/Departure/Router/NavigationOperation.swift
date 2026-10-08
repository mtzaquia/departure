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

import Observation
import Foundation

extension RouterEngine {
    /// One accepted transition owns its plan, outgoing views and continuation anchor.
    /// A branch awaiting its host retains this same operation after native teardown;
    /// completion releases the plan so that only the pending presentation remains.
    @Observable
    final class NavigationOperation {
        struct Presentation {
            let route: any Route
            let match: DeclarationMatch
        }

        struct Outgoing {
            let projection: ResolvedRoutePresentation
            let retainsBinding: Bool
            let disablesAnimation: Bool
        }

        @ObservationIgnored var plan: RouteSpaces.UnwindPlan?
        @ObservationIgnored var presentation: Presentation?
        var outgoing: [PresentationKey: Outgoing] = [:]
        var removedScopes: [RouteScope] { plan?.removedScopes ?? [] }

        init(plan: RouteSpaces.UnwindPlan? = nil, presentation: Presentation? = nil) {
            self.plan = plan
            self.presentation = presentation
        }
    }

    /// The global latest request slot may await either coordination or a branch host.
    enum PendingNavigation {
        final class Request {
            let route: any Route
            let stage: RouteRequestStage
            let origin: RouteRequestOrigin
            var continuation: CheckedContinuation<Void, Never>?
            var execution: Task<Void, Never>?

            init(route: any Route, stage: RouteRequestStage, origin: RouteRequestOrigin) {
                self.route = route
                self.stage = stage
                self.origin = origin
            }

            func resume() {
                let continuation = self.continuation
                self.continuation = nil
                continuation?.resume()
            }
        }

        case request(Request)
        case presentation(NavigationOperation)

        var operation: NavigationOperation? {
            if case let .presentation(operation) = self { return operation }
            return nil
        }

        var route: (any Route)? {
            switch self {
            case .request(let request): request.route
            case .presentation(let operation): operation.presentation?.route
            }
        }
    }
}
