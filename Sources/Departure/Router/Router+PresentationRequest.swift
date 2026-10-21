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
    /// Resolution owns admission through routing-state completion. The latest
    /// waiter resumes in its own task; it is not executed by the finishing caller.
    func beginPresentationRequest(_ route: any Route) async -> Bool {
        guard isPresentationRequestInProgress else {
            isPresentationRequestInProgress = true
            return true
        }
        let request = PendingNavigation.Request(route: route)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                request.continuation = continuation
                bufferedPresentationRequest?.resume()
                bufferedPresentationRequest = request
                // Native readiness and deferred host insertion remain latest-only.
                // Supersede the active caller's pending continuation, not its resolver
                // or a committed unwind's teardown and completion.
                replacePendingRoute(nil)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.bufferedPresentationRequest === request else { return }
                self?.bufferedPresentationRequest = nil
                request.resume()
            }
        }
    }

    func finishPresentationRequest() {
        guard let request = bufferedPresentationRequest else {
            isPresentationRequestInProgress = false
            return
        }
        bufferedPresentationRequest = nil
        // Keep admission reserved across the wake-up so another caller cannot
        // overtake the granted waiter before it resumes and checks its own state.
        request.resume(true)
    }
}
