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
    struct BufferedPresentationRequest {
        let id: UUID
        let route: any Route
        let continuation: CheckedContinuation<Bool, Never>
    }

    /// Reserves the presentation pipeline before route resolution can suspend.
    /// A buffered caller resumes in its own task, retaining its cancellation state.
    func beginPresentationRequest(_ route: any Route) async -> Bool {
        guard isPresentationRequestInProgress else {
            isPresentationRequestInProgress = true
            return true
        }

        let requestID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard Task.isCancelled == false else {
                    continuation.resume(returning: false)
                    return
                }

                bufferedPresentationRequest?.continuation.resume(returning: false)
                bufferedPresentationRequest = BufferedPresentationRequest(
                    id: requestID,
                    route: route,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelBufferedPresentationRequest(id: requestID)
            }
        }
    }

    func finishPresentationRequest() {
        guard let request = bufferedPresentationRequest else {
            isPresentationRequestInProgress = false
            return
        }

        bufferedPresentationRequest = nil
        // Keep the pipeline reserved until the granted caller resumes. A newer caller
        // must buffer instead of overtaking the request whose turn has just been granted.
        request.continuation.resume(returning: true)
    }

    private func cancelBufferedPresentationRequest(id: UUID) {
        guard let request = bufferedPresentationRequest, request.id == id else { return }
        bufferedPresentationRequest = nil
        request.continuation.resume(returning: false)
    }
}
