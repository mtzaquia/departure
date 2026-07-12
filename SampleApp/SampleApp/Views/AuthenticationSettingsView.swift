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

struct AuthenticationSettingsView: View {
    @Environment(Router.self) private var router
    @State private var storage = Storage.shared

    let state: AuthenticationSettingsRouteState

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        LabScreen("Scope targeting", eyebrow: "Authentication", symbol: "scope") {
            Text("Authentication route active")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SampleAppAccessibility.authenticationTitle)

            LabPanel("Runtime configuration") {
                Toggle(isOn: $storage.isLoggedIn) {
                    Label("Authenticated", systemImage: "person.badge.key.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(LabPalette.mint)
                .accessibilityIdentifier(SampleAppAccessibility.authenticationLoggedInToggle)

                Divider()

                @Bindable var routeState = state
                Toggle(isOn: $routeState.attachesLocalRoute) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Attach local sheet declaration", systemImage: "paperclip")
                            .font(.subheadline.weight(.semibold))
                        Text("Shows nearest-declaration routing")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(LabPalette.blue)
                .accessibilityIdentifier(SampleAppAccessibility.authenticationAttachLocalRouteToggle)
            }

            LabPanel("Presentation & unwind targets") {
                LazyVGrid(columns: columns, spacing: 8) {
                    action("Top-level sheet", symbol: "rectangle.bottomhalf.inset.filled", id: SampleAppAccessibility.authenticationPresentTopLevelSheetButton) { await router.present(TopLevelSheetRoute()) }
                    action("Top-level cover", symbol: "rectangle.fill", id: SampleAppAccessibility.authenticationPresentTopLevelCoverButton) { await router.present(TopLevelCoverRoute()) }
                    action("Declaration crawl", symbol: "arrow.up.left.and.arrow.down.right", color: LabPalette.blue) { await router.present(StartInfoRoute()) }
                    action("Root", symbol: "house.fill", color: LabPalette.coral, id: SampleAppAccessibility.authenticationUnwindToRootButton) { await router.unwind(to: .root) }
                    action("Topmost ancestor", symbol: "arrow.up.to.line", color: LabPalette.amber, id: SampleAppAccessibility.authenticationUnwindToTopmostAncestorButton) { await router.unwind(to: .topmostAncestor) }
                    action("Nearest branch", symbol: "arrow.uturn.backward", color: LabPalette.amber, id: SampleAppAccessibility.authenticationUnwindToNearestBranchButton) { await router.unwind(to: .nearestBranch) }
                    action("Branch ID", symbol: "number.square.fill", color: LabPalette.amber, id: SampleAppAccessibility.authenticationUnwindToBranchIDButton) { await router.unwind(to: .id(LandingView.TabItem.settings)) }
                    action("Stored unwind", symbol: "bookmark.fill", color: LabPalette.coral, id: SampleAppAccessibility.authenticationUnwindStoredActionButton) { await storage.landingUnwindRoute() }
                }
            }

            Spacer(minLength: 0)
        }
        .navigationTitle("Authentication")
        .navigationBarTitleDisplayMode(.inline)
        .routes {
            if state.attachesLocalRoute {
                Sheet(TopLevelSheetRoute.self, providesNavigation: false)
            }
        }
        .environment(\.samplePresentationSource, "authentication settings scope")
    }

    private func action(
        _ title: String,
        symbol: String,
        color: Color = LabPalette.indigo,
        id: String? = nil,
        operation: @escaping @MainActor () async -> Void
    ) -> some View {
        LabAction(title: title, symbol: symbol, color: color) { Task { await operation() } }
            .accessibilityIdentifier(id ?? "sample.authentication.declaration-crawl")
    }
}
