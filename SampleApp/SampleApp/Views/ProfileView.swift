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

struct ProfileView: View {
    @Environment(Router.self) private var router
    @Environment(\.routePhase) private var routePhase

    var body: some View {
        LabScreen("Protected destination", eyebrow: "Resolved profile", symbol: "person.crop.circle.fill") {
            Text("Profile route active")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SampleAppAccessibility.profileTitle)

            LabPanel("Route telemetry") {
                LabStatus(label: "Route phase", value: "Profile route phase: \(routePhase == .active ? "active" : "inactive")", color: routePhase == .active ? LabPalette.mint : LabPalette.amber, symbol: "bolt.fill")
                    .accessibilityIdentifier(SampleAppAccessibility.profileRoutePhase)
            }

            LabPanel("Continuation scenarios") {
                LabAction(title: "Present container sheet", symbol: "rectangle.bottomhalf.inset.filled", color: LabPalette.blue) {
                    Task { await router.present(TopLevelSheetRoute()) }
                }
                .accessibilityIdentifier(SampleAppAccessibility.profilePresentTopLevelSheetButton)

                LabAction(title: "Sign out to root", symbol: "rectangle.portrait.and.arrow.right", color: LabPalette.coral, role: .destructive) {
                    Storage.shared.isLoggedIn = false
                    Task { await router.unwind(to: .root) }
                }
                .accessibilityIdentifier(SampleAppAccessibility.profileSignOutButton)
            }
            Spacer()
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}
