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

struct StartView: View {
    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Button("Start", action: {
                    Task {
                        await router.present(LandingRoute())
                    }
                })
                .accessibilityIdentifier(SampleAppAccessibility.startButton)

                Button("Show info") {
                    Task {
                        await router.present(StartInfoRoute())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.startShowInfoButton)
            }
        }
        .routes(id: SampleAppAccessibility.startScopeID) {
            Cover(LandingRoute.self, providesNavigation: false)
            Sheet(StartInfoRoute.self, providesNavigation: false)
        }
    }
}

struct StartInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Start info")
                .font(.headline)
                .accessibilityIdentifier(SampleAppAccessibility.startInfoText)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.startInfoDismissButton)
        }
        .padding()
    }
}
