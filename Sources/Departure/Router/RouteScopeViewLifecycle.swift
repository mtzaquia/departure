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

final class RouteScopeViewLifecycle {
    private(set) var isInstalled = false

    private var installationWaiters: [CheckedContinuation<Void, Never>] = []
    private var uninstallationWaiters: [CheckedContinuation<Void, Never>] = []

    func install() {
        guard isInstalled == false else {
            return
        }

        isInstalled = true
        resume(&installationWaiters)
    }

    func uninstall() {
        guard isInstalled else {
            return
        }

        isInstalled = false
        resume(&uninstallationWaiters)
    }

    func waitUntilInstalled() async {
        guard isInstalled == false else {
            return
        }

        await withCheckedContinuation { continuation in
            installationWaiters.append(continuation)
        }
    }

    func waitUntilUninstalled() async {
        guard isInstalled else {
            return
        }

        await withCheckedContinuation { continuation in
            uninstallationWaiters.append(continuation)
        }
    }

    private func resume(_ waiters: inout [CheckedContinuation<Void, Never>]) {
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}
