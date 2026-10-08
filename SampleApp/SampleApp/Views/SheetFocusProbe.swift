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
import UIKit

extension EnvironmentValues {
    @Entry var sheetFocusKeyboard = false
}

private enum SheetFocusTab: nonisolated Hashable, Sendable { case home, other }

/// Public-routing reproduction for first presentation and keyboard-driven environment changes.
struct SheetFocusProbeRoot: View {
    @State private var selection = SheetFocusTab.home
    @State private var keyboard = false

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--sheet-focus-root") {
                NavigationStack { SheetFocusProbeControls() }
                    .routes { Sheet(SheetFocusProbeRoute.self) }
            } else {
                TabView(selection: $selection) {
                    NavigationStack { SheetFocusProbeControls().routeBranch(SheetFocusTab.home) }
                        .tabItem { Text("Home") }.tag(SheetFocusTab.home)
                    NavigationStack { SheetFocusProbeControls().routeBranch(SheetFocusTab.other) }
                        .tabItem { Text("Other") }.tag(SheetFocusTab.other)
                }
                .routes(branch: $selection) {
                    Branch(SheetFocusTab.home) { Sheet(SheetFocusProbeRoute.self) }
                    Branch(SheetFocusTab.other) { Sheet(SheetFocusProbeRoute.self) }
                }
            }
        }
        .environment(\.sheetFocusKeyboard, keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
    }
}

private struct SheetFocusProbeControls: View {
    @Environment(\.router) private var router

    var body: some View {
        Button("Present sheet") { Task { await router.present(SheetFocusProbeRoute(number: 1)) } }
            .accessibilityIdentifier("sample.sheet-focus.present")
    }
}

private struct SheetFocusProbeRoute: Route, Equatable {
    let number: Int
    func destination() -> some View { SheetFocusProbeForm(number: number) }
}

private struct SheetFocusProbeForm: View {
    let number: Int
    @Environment(\.router) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sheetFocusKeyboard) private var keyboard
    @State private var identity = UUID()
    @State private var name = ""
    @State private var errors = false
    @FocusState private var focus: Bool

    var body: some View {
        ScrollView {
            VStack {
                TextField("Coffee", text: $name).focused($focus)
                    .accessibilityIdentifier("sample.sheet-focus.field")
                Text(focus ? "focused" : "unfocused")
                    .accessibilityIdentifier("sample.sheet-focus.focus")
                Text(identity.uuidString).accessibilityIdentifier("sample.sheet-focus.identity")
                Text("Sheet \(number)").accessibilityIdentifier("sample.sheet-focus.number")
                if errors { Text("Required").accessibilityIdentifier("sample.sheet-focus.error") }
                Button("Replace sheet") { Task { await router.present(SheetFocusProbeRoute(number: number + 1)) } }
                    .accessibilityIdentifier("sample.sheet-focus.replace")
                Button("Unwind sheet") { Task { await router.unwind(to: .topmostAncestor) } }
                    .accessibilityIdentifier("sample.sheet-focus.unwind")
                ForEach(0..<10, id: \.self) { Text("Item \($0)") }
            }.padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if !keyboard {
                Button("Save") { errors = true; focus = true }
                    .accessibilityIdentifier("sample.sheet-focus.save")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if focus {
                Button("Done") { focus = false }
                    .accessibilityIdentifier("sample.sheet-focus.done")
            }
        }
        .navigationTitle("Focus probe")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Dismiss", action: dismiss.callAsFunction)
                    .accessibilityIdentifier("sample.sheet-focus.dismiss")
            }
        }
    }
}
