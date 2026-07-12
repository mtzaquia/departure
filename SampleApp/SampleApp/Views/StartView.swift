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
    @State private var storage = Storage.shared

    var body: some View {
        ZStack {
            LabBackground()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 32)
                        .fill(LabPalette.indigo.gradient)
                        .frame(width: 112, height: 112)
                        .rotationEffect(.degrees(8))
                        .shadow(color: LabPalette.indigo.opacity(0.3), radius: 24, y: 14)

                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("DEPARTURE LAB")
                        .font(.caption.weight(.bold))
                        .tracking(2.4)
                        .foregroundStyle(LabPalette.indigo)
                    Text("Every route. One cockpit.")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Explore pushes, sheets, covers, branches, priorities, actions, and unwinds—with live routing diagnostics always in view.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                LabPanel("Live telemetry") {
                    LabStatus(
                        label: "Root unwind handlers",
                        value: "Root unwind hooks: \(storage.rootUnwindHookCount)",
                        symbol: "arrow.uturn.backward.circle.fill"
                    )
                    .accessibilityIdentifier(SampleAppAccessibility.rootHookStatus)
                }
                .frame(maxWidth: 360)

                VStack(spacing: 10) {
                    Button("Launch route lab") {
                        Task { await router.present(LandingRoute()) }
                    }
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                    .labPrimaryButton()
                    .accessibilityIdentifier(SampleAppAccessibility.startButton)

                    Button("About this sample", systemImage: "info.circle") {
                        Task { await router.present(StartInfoRoute()) }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .accessibilityIdentifier(SampleAppAccessibility.startShowInfoButton)
                }
                .frame(maxWidth: 360)

                Spacer()
            }
            .padding(24)
        }
        .routes(id: SampleAppAccessibility.startScopeID) {
            Cover(LandingRoute.self, providesNavigation: false)
            Sheet(StartInfoRoute.self, providesNavigation: false)
        }
        .hooks {
            UnwindHandler(AuthenticationSettingsRoute.self) {
                Storage.shared.rootUnwindHookCount += 1
            }
        }
    }
}

struct StartInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LabBackground()
            LabModalCard(
                "A living routing spec",
                subtitle: "Everything used by automation is visible and useful here too.",
                symbol: "sparkles"
            ) {
                Text("Each action demonstrates a public Departure capability. Status cards expose the active route phase, presentation environment, payloads, and hook delivery in real time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(SampleAppAccessibility.startInfoText)

                Button("Done") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .labPrimaryButton()
                    .accessibilityIdentifier(SampleAppAccessibility.startInfoDismissButton)
            }
        }
    }
}
