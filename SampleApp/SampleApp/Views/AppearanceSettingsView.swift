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

struct AppearanceSettingsView: View {
    let value: UUID?

    @State private var storage = Storage.shared
    @Environment(Router.self) private var router

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        LabScreen("Route identity", eyebrow: "Equatable push", symbol: "equal.circle.fill") {
            Text("Appearance route active")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SampleAppAccessibility.appearanceTitle)

            LabPanel("Current destination") {
                LabStatus(label: "Route value", value: "Route value: \(value.map(\.uuidString) ?? "nil")", color: LabPalette.blue, symbol: "number.circle.fill")
                    .accessibilityIdentifier(SampleAppAccessibility.appearanceValue)
                LabStatus(label: "Action interceptor", value: "Saved \(storage.appearanceSaveCount) time(s)", color: LabPalette.mint, symbol: "checkmark.seal.fill")
                    .accessibilityIdentifier(SampleAppAccessibility.appearanceSavedCount)
            }

            LabPanel("Identity & scope scenarios") {
                LazyVGrid(columns: columns, spacing: 8) {
                    action("Equal route · no-op", symbol: "equal", id: SampleAppAccessibility.appearanceRePresentButton) { await router.present(AppearanceSettingsRoute(value: value)) }
                    action("New value · replace", symbol: "arrow.triangle.2.circlepath", color: LabPalette.blue, id: SampleAppAccessibility.appearanceRePresentDifferentButton) { await router.present(AppearanceSettingsRoute(value: UUID())) }
                    action("Nested push", symbol: "arrow.right.square.fill", id: SampleAppAccessibility.appearancePresentAuthenticationButton) { await router.present(AuthenticationSettingsRoute()) }
                    action("Unwind then route", symbol: "arrow.uturn.backward.square.fill", color: LabPalette.amber, id: SampleAppAccessibility.appearanceUnwindToLandingPresentMessageButton) {
                        guard await router.unwind(to: .id(LandingRoute().id)) else { return }
                        await router.present(MessageRoute())
                    }
                    action("Intercepted save", symbol: "tray.and.arrow.down.fill", color: LabPalette.mint, id: SampleAppAccessibility.appearanceSaveButton) { await router.perform(SaveAppearanceSettingsAction()) }
                }
            }

            Spacer(minLength: 0)
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .routes { Push(AuthenticationSettingsRoute.self) }
        .hooks {
            ActionInterceptor(SaveAppearanceSettingsAction.self) { invocation in
                try? await invocation()
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
