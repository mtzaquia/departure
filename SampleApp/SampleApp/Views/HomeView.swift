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
    @State private var storage = Storage.shared
    @State private var passthroughTapCount = 0

    var body: some View {
        List {
            Text("Welcome home.")
                .accessibilityIdentifier(SampleAppAccessibility.homeWelcome)

            Button("Show message") {
                Task {
                    await router.present(MessageRoute())
                }
            }
            .accessibilityIdentifier(SampleAppAccessibility.homeShowMessageButton)

            if SampleAppUITesting.isEnabled {
                Button("Show dismiss probe") {
                    Task {
                        await router.present(DismissProbeRoute())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.homeShowDismissProbeButton)
            }

            Button("Show high-priority passthrough sheet") {
                Task {
                    await router.present(HighPriorityPassthroughSheetRoute())
                }
            }
            .accessibilityIdentifier(SampleAppAccessibility.homePresentHighPriorityPassthroughSheetButton)

            Button("Tap behind presentation") {
                passthroughTapCount += 1
            }
            .accessibilityIdentifier(SampleAppAccessibility.homePassthroughBehindButton)

            Text("Behind sheet taps: \(passthroughTapCount)")
                .accessibilityIdentifier(SampleAppAccessibility.homePassthroughTapCount)

            Section {
                LabeledContent {
                    Text(Storage.shared.emoji)
                        .accessibilityIdentifier(SampleAppAccessibility.homeEmojiValue)
                } label: {
                    Text("Current emoji")
                    Text("Change from settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if SampleAppUITesting.isEnabled {
                Section("UI Tests") {
                    Text("Payload hooks: \(storage.homeUnwindPayloads.joined(separator: ", "))")
                        .accessibilityIdentifier(SampleAppAccessibility.homeUnwindPayloadStatus)

                    Text("Dismiss probe hooks: \(storage.dismissProbeUnwindHookCount)")
                        .accessibilityIdentifier(SampleAppAccessibility.homeDismissProbeHookStatus)
                }
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Profile", systemImage: "person") {
                    Task {
                        await router.present(ProfileRoute())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.homeProfileButton)
            }
        }
        .hooks {
            UnwindHandler(DismissProbeRoute.self) {
                guard SampleAppUITesting.isEnabled else {
                    return
                }

                Storage.shared.dismissProbeUnwindHookCount += 1
                Task {
                    await router.present(MessageRoute())
                }
            }

            UnwindHandler(MessageRoute.self, expecting: String.self) { payload in
                guard SampleAppUITesting.isEnabled else {
                    print(payload)
                    return
                }

                Storage.shared.homeUnwindPayloads.append(payload)
            }
        }
    }
}
