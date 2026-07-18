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

import SwiftUI

struct WindowDestinationBuilder {
    let hasWindowDestination: Bool
    private let buildDestination: (RouteView, EnvironmentValues) -> AnyView

    init<Wrapped: View>(@ViewBuilder _ build: @escaping (RouteView, EnvironmentValues) -> Wrapped) {
        self.init(isProvided: true, build)
    }

    private init<Wrapped: View>(
        isProvided: Bool,
        @ViewBuilder _ build: @escaping (RouteView, EnvironmentValues) -> Wrapped
    ) {
        self.hasWindowDestination = isProvided
        self.buildDestination = { destination, environment in
            AnyView(build(destination, environment))
        }
    }

    func build(_ destination: RouteView, _ environment: EnvironmentValues) -> AnyView {
        if hasWindowDestination == false {
            MissingWindowDestinationWarning.emitIfNeeded()
        }

        return buildDestination(destination, environment)
    }

    static let passthrough = WindowDestinationBuilder(isProvided: false) { destination, _ in
        destination
    }
}

extension EnvironmentValues {
    @Entry var windowDestinationBuilder = WindowDestinationBuilder.passthrough
}

private enum MissingWindowDestinationWarning {
    private static var wasEmitted = false

    static func emitIfNeeded() {
        guard wasEmitted == false else {
            return
        }

        wasEmitted = true
        log.departureWarning(
            "Detached route presentation is missing a `windowDestination` closure on `WithRouter`. "
                + "Add one to forward custom environment values."
        )
    }
}
