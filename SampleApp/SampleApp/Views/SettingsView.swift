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

struct SettingsView: View {
    @Environment(Router.self) private var router
    @State private var storage = Storage.shared

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        LabScreen("Routing catalog", eyebrow: "Settings branch", symbol: "switch.2") {
            LabPanel("Branch telemetry") {
                LazyVGrid(columns: columns, spacing: 7) {
                    LabStatus(label: "Container handler", value: "Container unwind hooks: \(storage.landingContainerUnwindHookCount)", symbol: "rectangle.3.group.fill")
                        .accessibilityIdentifier(SampleAppAccessibility.landingContainerHookStatus)
                    LabStatus(label: "Branch handler", value: "Branch unwind hooks: \(storage.settingsBranchUnwindHookCount)", color: LabPalette.blue, symbol: "arrow.triangle.branch")
                        .accessibilityIdentifier(SampleAppAccessibility.settingsBranchHookStatus)
                    LabStatus(label: "Missing target", value: "Missing unwind: \(storage.missingUnwindResult.map(String.init) ?? "none")", color: LabPalette.amber, symbol: "questionmark.diamond.fill")
                        .accessibilityIdentifier(SampleAppAccessibility.settingsMissingUnwindResult)
                }
            }

            LabPanel("Routes & actions") {
                LazyVGrid(columns: columns, spacing: 8) {
                    action("Appearance push", symbol: "paintpalette.fill", id: SampleAppAccessibility.settingsAppearanceButton) { await router.present(AppearanceSettingsRoute(value: nil)) }
                    action("Authentication push", symbol: "lock.shield.fill", id: SampleAppAccessibility.settingsAuthenticationButton) { await router.present(AuthenticationSettingsRoute()) }
                    action("Protected profile", symbol: "person.crop.circle", id: SampleAppAccessibility.settingsProfileButton) { await router.present(ProfileRoute()) }
                    action("Rerouting action", symbol: "arrow.triangle.2.circlepath", color: LabPalette.blue, id: SampleAppAccessibility.settingsSaveAppearanceButton) { await router.perform(SaveAppearanceSettingsAction()) }
                    action("Local action", symbol: "sparkles", color: LabPalette.mint, id: SampleAppAccessibility.settingsNewEmojiButton) { await router.perform(RandomizeEmojiAction()) }
                    action("Cross-branch route", symbol: "arrow.left.arrow.right", color: LabPalette.blue, id: SampleAppAccessibility.settingsPresentHomeMessageButton) { await router.present(MessageRoute()) }
                    action("Dropped resolution", symbol: "nosign", color: LabPalette.coral, id: SampleAppAccessibility.settingsPresentDroppedRouteButton) { await router.present(DroppedRoute()) }
                    action("Undeclared route", symbol: "questionmark.folder", color: LabPalette.coral, id: SampleAppAccessibility.settingsPresentUndeclaredRouteButton) { await router.present(UndeclaredRoute()) }
                    action("Reroute chain", symbol: "point.3.filled.connected.trianglepath.dotted", color: LabPalette.amber, id: SampleAppAccessibility.settingsPresentRerouteChainButton) { await router.present(RerouteChainStartRoute()) }
                    action("Missing unwind", symbol: "scope", color: LabPalette.amber, id: SampleAppAccessibility.settingsMissingUnwindButton) {
                        storage.missingUnwindResult = await router.unwind(to: .id("missing"))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .hooks {
            UnwindHandler(AuthenticationSettingsRoute.self) {
                Storage.shared.settingsBranchUnwindHookCount += 1
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
        LabAction(title: title, symbol: symbol, color: color) { Task { await operation() } }
            .accessibilityIdentifier(id)
    }
}
