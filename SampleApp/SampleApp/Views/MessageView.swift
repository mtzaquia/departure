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

struct MessageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unwindRoute) private var unwindRoute
    @Environment(\.samplePresentationSource) private var samplePresentationSource

    var body: some View {
        ZStack {
            Color.black.opacity(0.24).ignoresSafeArea()
            LabModalCard("Fade cover", subtitle: "A custom cover transition with three equivalent dismissal paths.", symbol: "envelope.open.fill", color: LabPalette.indigo) {
                Text("This is a message.")
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier(SampleAppAccessibility.messageText)
                Text("Presented from: \(samplePresentationSource)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(SampleAppAccessibility.messagePresentationSource)
                Button("Unwind with payload") { Task { await unwindRoute(payload: "message delivered") } }
                    .labPrimaryButton()
                    .accessibilityIdentifier(SampleAppAccessibility.messageDismissPayloadButton)
                Button("Unwind mismatched payload") { Task { await unwindRoute(payload: 42) } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(SampleAppAccessibility.messageDismissMismatchedPayloadButton)
                HStack {
                    Button("unwindRoute()") { Task { await unwindRoute() } }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(SampleAppAccessibility.messageDismissUnwindButton)
                    Button("dismiss()") { dismiss() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(SampleAppAccessibility.messageDismissSwiftUIButton)
                }
            }
        }
    }
}
