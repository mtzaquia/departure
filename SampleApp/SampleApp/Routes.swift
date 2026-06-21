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

import Departure
import SwiftUI

struct LandingRoute: Route {
    func destination() -> some View {
        LandingView()
    }
}

struct StartInfoRoute: Route {
    func destination() -> some View {
        StartInfoView()
    }
}

struct LoginRoute: Route {
    let nextRoute: (any Route)?

    func destination() -> some View {
        LoginView(nextRoute: nextRoute)
    }
}

struct LoginReplacementRoute: Route {
    func destination() -> some View {
        LoginReplacementView()
    }
}

struct LoginDetailRoute: Route {
    func destination() -> some View {
        LoginDetailView()
    }
}

struct LoginNoticeRoute: Route {
    func destination() -> some View {
        LoginNoticeView()
    }
}

struct ProfileRoute: Route {
    func resolveRoute() async -> RouteResolution {
        Storage.shared.isLoggedIn ? .allow : .reroute(LoginRoute(nextRoute: ProfileRoute()))
    }

    func destination() -> some View {
        ProfileView()
    }
}

@Observable
final class AuthenticationSettingsRouteState {
    var attachesLocalRoute = false
}

struct AuthenticationSettingsRoute: Route {
    let state: AuthenticationSettingsRouteState

    init(state: AuthenticationSettingsRouteState = AuthenticationSettingsRouteState()) {
        self.state = state
    }

    func destination() -> some View {
        AuthenticationSettingsView(state: state)
    }
}

struct TopLevelSheetRoute: Route {
    func destination() -> some View {
        TopLevelSheetView()
    }
}

struct TopLevelSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.samplePresentationSource) private var samplePresentationSource

    var body: some View {
        VStack(spacing: 16) {
            Text("Top-level sheet")
                .font(.headline)
                .accessibilityIdentifier(SampleAppAccessibility.topLevelSheetText)

            Text("Presented from: \(samplePresentationSource)")
                .accessibilityIdentifier(SampleAppAccessibility.topLevelSheetPresentationSource)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.topLevelSheetDismissButton)
        }
        .padding()
    }
}

struct AppearanceSettingsRoute: Route {
    func destination() -> some View {
        AppearanceSettingsView()
    }
}

struct AlertRoute: Route {
    func destination() -> some View {
        AlertView()
    }
}

struct MessageRoute: Route {
    func destination() -> some View {
        MessageView()
    }
}

struct DismissProbeRoute: Route {
    func destination() -> some View {
        DismissProbeView()
    }
}

struct DismissProbeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Dismiss probe")
                .font(.headline)
                .accessibilityIdentifier(SampleAppAccessibility.dismissProbeText)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.dismissProbeDismissButton)
        }
        .padding()
    }
}

struct DroppedRoute: Route {
    func resolveRoute() async -> RouteResolution {
        .drop
    }

    func destination() -> some View {
        Text("Dropped route should not appear.")
            .accessibilityIdentifier(SampleAppAccessibility.droppedRouteText)
    }
}

struct UndeclaredRoute: Route {
    func destination() -> some View {
        Text("Undeclared route should not appear.")
            .accessibilityIdentifier(SampleAppAccessibility.undeclaredRouteText)
    }
}
