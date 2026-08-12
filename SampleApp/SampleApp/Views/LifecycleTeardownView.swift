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

struct LifecycleTeardownView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var generation = 0
    @State private var backgroundTransitionCount = 0

    var body: some View {
        LabScreen("Routed scroll teardown", eyebrow: "Lifecycle regression", symbol: "arrow.triangle.2.circlepath") {
            Text("Replace a visible routed scroll, then background and foreground the app. Its active route scope should recover without publishing from UIKit's dismantle stack.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Replace routed scroll") {
                generation += 1
            }
            .frame(maxWidth: .infinity)
            .labPrimaryButton(color: LabPalette.mint)
            .accessibilityIdentifier(SampleAppAccessibility.lifecycleTeardownReplaceButton)

            RoutedScrollProbe(generation: generation)
                .id(generation)

            Text("Background transitions: \(backgroundTransitionCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SampleAppAccessibility.lifecycleTeardownBackgroundCount)
        }
        .navigationTitle("Lifecycle teardown")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                backgroundTransitionCount += 1
            }
        }
    }
}

private struct RoutedScrollProbe: View {
    private enum ProbeBranch: nonisolated Hashable {
        case content
    }

    let generation: Int
    @State private var selection = ProbeBranch.content

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                RoutedScrollStatus(generation: generation)

                ForEach(0..<12, id: \.self) { row in
                    HStack {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .foregroundStyle(LabPalette.indigo)
                        Text("Routed row \(row + 1)")
                        Spacer()
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .routeBranch(ProbeBranch.content)
        }
        .frame(maxHeight: 430)
        .routes(branch: $selection) {
            Branch(ProbeBranch.content) {
                Sheet(TopLevelSheetRoute.self, providesNavigation: false)
            }
        }
    }
}

private struct RoutedScrollStatus: View {
    let generation: Int
    @Environment(\.routePhase) private var routePhase

    var body: some View {
        LabPanel("Observed router state") {
            Text("Generation: \(generation)")
                .accessibilityIdentifier(SampleAppAccessibility.lifecycleTeardownGeneration)
            Text("Nested route phase: \(routePhase == .active ? "active" : "inactive")")
                .accessibilityIdentifier(SampleAppAccessibility.lifecycleTeardownRoutePhase)
        }
    }
}
