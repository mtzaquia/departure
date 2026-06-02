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

import os

/// Global Departure configuration.
public enum Departure {
    private nonisolated static let debugLock = OSAllocatedUnfairLock(initialState: false)

    /// Enables Departure engine logs in debug builds.
    ///
    /// ```swift
    /// Departure.debug = true
    /// ```
    public nonisolated static var debug: Bool {
        get { debugLock.withLock { $0 } }
        set { debugLock.withLock { $0 = newValue } }
    }
}

nonisolated let log = Logger(subsystem: "eu.lelfe.departure", category: "Departure")

extension Logger {
#if DEBUG
    func departureDebug(_ message: @autoclosure () -> String) {
        guard Departure.debug else { return }
        let message = message()
        debug("\(message, privacy: .public)")
    }
#endif

    func departureWarning(_ message: @autoclosure () -> String) {
        let message = message()
        warning("\(message, privacy: .public)")
    }
}
