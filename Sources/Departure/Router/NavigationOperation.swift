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
    /// explicit stages prevent completed teardown from retaining a captured plan.
    @Observable
    final class NavigationOperation {
        struct Presentation {
            let route: any Route
            let match: ResolvedRouteTarget
        }

        struct Outgoing {
            let projection: ResolvedRoutePresentation
            let retainsBinding: Bool
            let disablesAnimation: Bool
        }

        enum Stage {
            case preparingUnwind(RouteSpaces.UnwindPlan)
            case preparingPresentation(RouteSpaces.UnwindPlan, Presentation)
            case unwinding(RouteSpaces.UnwindPlan, destination: RouteScope?)
            case unwindingForPresentation(RouteSpaces.UnwindPlan, Presentation)
            case awaitingHost(Presentation)
            case finished(RouteScope?)
        }

        @ObservationIgnored private(set) var stage: Stage
        @ObservationIgnored private var completion: CheckedContinuation<RouteScope?, Never>?
        var outgoing: [PresentationKey: Outgoing] = [:]

        var plan: RouteSpaces.UnwindPlan? {
            switch stage {
            case .preparingUnwind(let plan), .preparingPresentation(let plan, _),
                 .unwinding(let plan, _), .unwindingForPresentation(let plan, _): plan
            case .awaitingHost, .finished: nil
            }
        }

        var presentation: Presentation? {
            switch stage {
            case .preparingPresentation(_, let presentation),
                 .unwindingForPresentation(_, let presentation), .awaitingHost(let presentation): presentation
            case .preparingUnwind, .unwinding, .finished: nil
            }
        }

        var removedScopes: [RouteScope] { plan?.removedScopes ?? [] }

        private var destination: RouteScope? {
            switch stage {
            case .unwinding(_, let scope), .finished(let scope): scope
            default: nil
            }
        }

        init(plan: RouteSpaces.UnwindPlan, presentation: Presentation? = nil) {
            if let presentation { stage = .preparingPresentation(plan, presentation) }
            else { stage = .preparingUnwind(plan) }
        }

        init(awaitingHost presentation: Presentation) { stage = .awaitingHost(presentation) }

        /// Committing twice must not reapply a captured plan to a changed tree.
        func commit() -> RouteSpaces.UnwindPlan? {
            switch stage {
            case .preparingUnwind(let plan):
                stage = .unwinding(plan, destination: nil)
                return plan
            case .preparingPresentation(let plan, let presentation):
                stage = .unwindingForPresentation(plan, presentation)
                return plan
            default: return nil
            }
        }

        func discardPresentation() {
            switch stage {
            case .preparingPresentation(let plan, _): stage = .preparingUnwind(plan)
            case .unwindingForPresentation(let plan, _): stage = .unwinding(plan, destination: nil)
            case .awaitingHost: stage = .finished(nil)
            default: break
            }
            resumeCompletion()
        }

        func finishTeardown(awaitingHost: Bool) {
            if awaitingHost, let presentation { stage = .awaitingHost(presentation) }
            else { stage = .finished(destination) }
            resumeCompletion()
        }

        func completePresentation(at scope: RouteScope) {
            if let plan { stage = .unwinding(plan, destination: scope) }
            else { stage = .finished(scope) }
            resumeCompletion()
        }

        /// Teardown can finish before branch installation. The original caller
        /// stays attached to this operation through that native staging boundary.
        func waitForPresentation() async -> RouteScope? {
            if case .finished(let scope) = stage { return scope }
            return await withCheckedContinuation { completion = $0 }
        }

        private func resumeCompletion() {
            guard case .finished(let scope) = stage else { return }
            let continuation = completion
            completion = nil
            continuation?.resume(returning: scope)
        }

    }

    /// The global latest request slot may await either coordination or a branch host.
    enum PendingNavigation {
        final class Request {
            let route: any Route
            var continuation: CheckedContinuation<Bool, Never>?

            init(route: any Route) {
                self.route = route
            }

            func resume(_ ready: Bool = false) {
                let continuation = self.continuation
                self.continuation = nil
                continuation?.resume(returning: ready)
            }
        }

        case request(Request)
        case presentation(NavigationOperation)

        var request: Request? {
            if case let .request(request) = self { return request }
            return nil
        }

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
