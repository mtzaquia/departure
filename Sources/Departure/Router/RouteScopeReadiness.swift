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

/// Host completion comes from the scope's canonical event; command eligibility is
/// observed in the live model. Neither wait stores another copy of membership.
final class RouteScopeReadiness {
    private var eligibility: (() -> Bool)?
    private var ready: (() -> Bool)?
    private var continuation: CheckedContinuation<Bool, Never>?
    var isPending: Bool { continuation != nil }

    static func wait(in scope: RouteScope, cancellable: Bool = true,
                     while eligible: (() -> Bool)? = nil, until ready: @escaping () -> Bool) async -> Bool {
        let readiness = RouteScopeReadiness()
        defer { withExtendedLifetime(readiness) {} }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !cancellable || !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                readiness.eligibility = eligible
                readiness.ready = ready
                readiness.continuation = continuation
                scope.observeReadiness(readiness)
                readiness.observeEligibility()
            }
        } onCancel: {
            if cancellable { Task { @MainActor in readiness.finish(false) } }
        }
    }

    private func observeEligibility() {
        guard isPending else { return }
        if let eligibility {
            let eligible = withObservationTracking {
                eligibility()
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in self?.observeEligibility() }
            }
            guard eligible else { finish(false); return }
        }
        checkReadiness()
    }

    func checkReadiness() {
        guard let ready else { return }
        if eligibility?() == false { finish(false) }
        else if ready() { finish(true) }
    }

    private func finish(_ result: Bool) {
        let continuation = continuation
        self.continuation = nil
        eligibility = nil
        ready = nil
        continuation?.resume(returning: result)
    }
}
