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

struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(\.routePhase) private var routePhase
    @State private var storage = Storage.shared
    @State private var passthroughTapCount = 0

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        LabScreen("Navigation playground", eyebrow: "Home branch", symbol: "point.3.connected.trianglepath.dotted") {
            Text("Welcome home.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SampleAppAccessibility.homeWelcome)

            LabPanel("Live route state") {
                LazyVGrid(columns: columns, spacing: 7) {
                    LabStatus(label: "Route phase", value: "Home route phase: \(routePhaseLabel)", color: routePhase == .active ? LabPalette.mint : LabPalette.amber, symbol: "bolt.fill")
                        .accessibilityIdentifier(SampleAppAccessibility.homeRoutePhase)
                    LabStatus(label: "Shared value", value: storage.emoji, color: LabPalette.blue, symbol: "sparkles")
                        .accessibilityIdentifier(SampleAppAccessibility.homeEmojiValue)
                    LabStatus(label: "Background taps", value: "Behind sheet taps: \(passthroughTapCount)", color: LabPalette.amber, symbol: "hand.tap.fill")
                        .accessibilityIdentifier(SampleAppAccessibility.homePassthroughTapCount)
                    LabStatus(label: "Unwind payloads", value: "Payload hooks: \(storage.homeUnwindPayloads.joined(separator: ", "))", color: LabPalette.coral, symbol: "shippingbox.fill")
                        .accessibilityIdentifier(SampleAppAccessibility.homeUnwindPayloadStatus)
                    LabStatus(label: "Dismiss handler", value: "Dismiss probe hooks: \(storage.dismissProbeUnwindHookCount)", color: LabPalette.indigo, symbol: "checkmark.circle.fill")
                        .accessibilityIdentifier(SampleAppAccessibility.homeDismissProbeHookStatus)
                }
            }

            LabPanel("Presentation scenarios") {
                LazyVGrid(columns: columns, spacing: 8) {
                    LabAction(title: "Tap behind sheet", symbol: "cursorarrow.click.2", color: LabPalette.mint) { passthroughTapCount += 1 }
                        .accessibilityIdentifier(SampleAppAccessibility.homePassthroughBehindButton)
                    action("Fade cover", symbol: "rectangle.inset.filled.and.person.filled", id: SampleAppAccessibility.homeShowMessageButton) { await router.present(MessageRoute()) }
                    action("Nested sheets", symbol: "square.stack.3d.up.fill", id: SampleAppAccessibility.homeShowDismissProbeButton) { await router.present(DismissProbeRoute()) }
                    action("Fade navigation", symbol: "menubar.rectangle", id: SampleAppAccessibility.homeShowNavigationBarFadeButton) { await router.present(NavigationBarFadeOcclusionRoute()) }
                    action("Priority race", symbol: "flag.checkered", color: LabPalette.coral, id: SampleAppAccessibility.homePresentPendingPriorityRaceButton) {
                        await router.present(PendingPriorityRoute())
                        await router.present(TopLevelSheetRoute())
                    }
                    action("Passthrough sheet", symbol: "hand.tap", color: LabPalette.blue, id: SampleAppAccessibility.homePresentHighPriorityPassthroughSheetButton) { await router.present(HighPriorityPassthroughSheetRoute()) }
                    action("Blocking sheet", symbol: "hand.raised.fill", color: LabPalette.amber, id: SampleAppAccessibility.homePresentHighPriorityBlockingSheetButton) { await router.present(HighPriorityBlockingSheetRoute()) }
                }
            }

            Spacer(minLength: 0)
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Profile", systemImage: "person.crop.circle.fill") {
                    Task { await router.present(ProfileRoute()) }
                }
                .accessibilityIdentifier(SampleAppAccessibility.homeProfileButton)
            }
        }
        .hooks {
            UnwindHandler(DismissProbeRoute.self) {
                Storage.shared.dismissProbeUnwindHookCount += 1
                await router.present(MessageRoute())
            }

            UnwindHandler(MessageRoute.self, expecting: String.self) { payload in
                Storage.shared.homeUnwindPayloads.append(payload)
            }
        }
    }

    private func action(
        _ title: String,
        symbol: String,
        color: Color = LabPalette.indigo,
        id: String,
        operation: @escaping @MainActor () async -> Void
    ) -> some View {
        LabAction(title: title, symbol: symbol, color: color) {
            Task { await operation() }
        }
        .accessibilityIdentifier(id)
    }

    private var routePhaseLabel: String { routePhase == .active ? "active" : "inactive" }
}
