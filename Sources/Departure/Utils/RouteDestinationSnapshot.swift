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

struct RouteDestinationSnapshot {
    let route: PresentedRoute
    let destination: AnyView

    init(route: PresentedRoute, nativePresentation: NativePresentationLifetime? = nil) {
        self.route = route
        self.destination = AnyView(RouteView(scope: route.scope, nativePresentation: nativePresentation))
    }

    init(route: PresentedRoute, destinationBuilder: WindowDestinationBuilder, nativePresentation: NativePresentationLifetime? = nil) {
        self.route = route
        let destination = destinationBuilder.build(
            RouteView(scope: route.scope, nativePresentation: nativePresentation),
            route.sourceEnvironment
        )
        if destinationBuilder.hasWindowDestination, let nativePresentation {
            // A custom wrapper may conditionally omit RouteView, or retain itself after
            // RouteView tears down. Both sources feed the same monotonic admission state;
            // native dismissal still belongs to the modal adapter.
            self.destination = AnyView(destination.onLifecycleEvent { [weak nativePresentation] _, _, event in
                nativePresentation?.handleDestinationEvent(event, of: route.id)
            })
        } else {
            self.destination = destination
        }
    }
}

extension RouteDestinationSnapshot: Identifiable {
    var id: PresentedRoute.ID {
        route.id
    }
}
