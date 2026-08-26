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

import RouteDomainFixtures
import SwiftUI
import Testing
@testable import Departure

extension FeatureProvidedRoute: RouteViewProviding {
    public func destination() -> some View {
        DestinationBuildProbe(onBuild: destinationDidBuild)
    }
}

@MainActor
@Suite
struct RouteDestinationTests {
    @Test func routeWithoutDestinationUsesFallback() {
        let destination = DomainOnlyRoute().destination()

        #expect(destination is MissingRouteDestination)
    }

    @Test func legacyRouteDestinationRemainsSupported() {
        var buildCount = 0
        let route = LegacyDestinationRoute {
            buildCount += 1
        }

        _ = routeDestination(for: route)

        #expect(buildCount == 1)
    }

    @Test func separatelyProvidedDestinationTakesPrecedence() {
        var buildCount = 0
        let route = FeatureProvidedRoute {
            buildCount += 1
        }

        _ = routeDestination(for: route)

        #expect(buildCount == 1)
    }
}

private struct LegacyDestinationRoute: Route {
    let destinationDidBuild: @MainActor () -> Void

    func destination() -> some View {
        DestinationBuildProbe(onBuild: destinationDidBuild)
    }
}

private struct DestinationBuildProbe: View {
    init(onBuild: @MainActor () -> Void) {
        onBuild()
    }

    var body: some View {
        EmptyView()
    }
}
