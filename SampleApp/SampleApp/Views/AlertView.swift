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

struct AlertView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unwindRoute) private var unwindRoute

    var body: some View {
        LabModalCard("Ancestor alert", subtitle: "This high-priority fade cover was declared above login and replaces it.", symbol: "exclamationmark.bubble.fill", color: LabPalette.coral) {
            Text("This is an alert!")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.alertText)
            HStack {
                Button("unwindRoute()") { Task { await unwindRoute() } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(SampleAppAccessibility.alertDismissUnwindButton)
                Button("dismiss()") { dismiss() }
                    .labPrimaryButton(color: LabPalette.coral)
                    .accessibilityIdentifier(SampleAppAccessibility.alertDismissSwiftUIButton)
            }
        }
    }
}
