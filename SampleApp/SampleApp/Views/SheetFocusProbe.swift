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
import Combine

extension EnvironmentValues {
    @Entry var sheetFocusKeyboard = false
    @Entry var sheetFocusUpdate = 0
}

private enum SheetFocusTab: nonisolated Hashable, Sendable { case home, other }

/// Public-routing probe for stable native focus through parent and form-layout updates.
struct SheetFocusProbeRoot: View {
    @State private var selection = SheetFocusTab.home
    @State private var sourceUpdates = 0
    @State private var keyboard = false
    @State private var updates = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    static var routes: RootRouteMap {
        let destination = RouteDestination(SheetFocusProbeRoute.self) { route, _ in
            NavigationStack { SheetFocusProbeForm(number: route.number).routing() }
        }
        if ProcessInfo.processInfo.arguments.contains("--sheet-focus-root") {
            return RootRouteMap { Sheet(destination) }
        }
        return RootRouteMap {
            Branches {
                Branch(SheetFocusTab.home) { Sheet(destination) }
                Branch(SheetFocusTab.other) { Sheet(destination) }
            }
        }
    }

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--sheet-focus-root") {
                NavigationStack { SheetFocusProbeControls().routing() }
            } else {
                TabView(selection: $selection) {
                    NavigationStack { SheetFocusProbeControls().routing(SheetFocusTab.home) }
                        .tabItem { Text("Home") }.tag(SheetFocusTab.home)
                    NavigationStack { SheetFocusProbeControls().routing(SheetFocusTab.other) }
                        .tabItem { Text("Other") }.tag(SheetFocusTab.other)
                }
                .routing(branch: $selection)
            }
        }
        .environment(\.sheetFocusKeyboard, keyboard)
        .environment(\.sheetFocusUpdate, sourceUpdates)
        .onReceive(updates) { _ in sourceUpdates += 1 }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
    }
}

private struct SheetFocusProbeControls: View {
    @Environment(\.router) private var router
    @State private var completedCycles = 0

    var body: some View {
        VStack {
            Text("Cycles: \(completedCycles)").accessibilityIdentifier("sample.sheet-focus.cycles")
            Button("Present and unwind repeatedly") {
                Task {
                    for number in 1...10 {
                        await router.present(SheetFocusProbeRoute(number: number))
                        await Task.yield()
                        await router.unwind(to: .topmostAncestor)
                        completedCycles = number
                    }
                }
            }.accessibilityIdentifier("sample.sheet-focus.cycle")
            Button("Present sheet") {
                Task { await router.present(SheetFocusProbeRoute(number: 1)) }
            }
            .accessibilityIdentifier("sample.sheet-focus.present")
        }
    }
}

private struct SheetFocusProbeRoute: Route, Equatable {
    let number: Int
}

private final class WeakFocusField { weak var value: UITextField? }

private struct SheetFocusProbeForm: View {
    let number: Int
    @Environment(\.router) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var keyboard = false
    @State private var identity = UUID()
    @State private var name = ""
    @State private var errors = false
    @FocusState private var focus: Bool
    @State private var nativeField = WeakFocusField()
    @State private var nativeBegins = 0
    @State private var nativeEnds = 0
    @State private var unexpectedResignations = 0
    @State private var focusSamples = 0
    @State private var monitorsFocus = false
    @State private var layoutUpdate = 0
    @State private var updates = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack {
                TextField("Coffee", text: $name).focused($focus)
                    .accessibilityIdentifier("sample.sheet-focus.field")
                Text(verbatim: "\(nativeBegins),\(nativeEnds),\(unexpectedResignations),\(nativeField.value?.isFirstResponder == true),\(nativeField.value.map { String(describing: ObjectIdentifier($0)) } ?? "nil"),\(focusSamples)")
                    .accessibilityIdentifier("sample.sheet-focus.responder")
                Text(keyboard ? "keyboard shown" : "keyboard hidden")
                    .accessibilityIdentifier("sample.sheet-focus.keyboard")
                Text(focus ? "focused" : "unfocused")
                    .accessibilityIdentifier("sample.sheet-focus.focus")
                Text(identity.uuidString).accessibilityIdentifier("sample.sheet-focus.identity")
                Text("Sheet \(number)").accessibilityIdentifier("sample.sheet-focus.number")
                if errors { Text("Required").accessibilityIdentifier("sample.sheet-focus.error") }
                Button("Replace sheet") { Task { await router.present(SheetFocusProbeRoute(number: number + 1)) } }
                    .accessibilityIdentifier("sample.sheet-focus.replace")
                Button("Unwind sheet") { Task {
                    await router.unwind(to: .topmostAncestor)
                } }
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
                Button("Done") { monitorsFocus = false; focus = false }
                    .accessibilityIdentifier("sample.sheet-focus.done")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
            guard let field = notification.object as? UITextField else { return }
            nativeField.value = field
            nativeBegins += 1
            monitorsFocus = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { notification in
            guard let field = notification.object as? UITextField, field === nativeField.value else { return }
            nativeEnds += 1
        }
        .onReceive(updates) { _ in
            layoutUpdate += 1
            if monitorsFocus {
                focusSamples += 1
                if nativeField.value?.isFirstResponder != true { unexpectedResignations += 1 }
            }
        }
        .safeAreaInset(edge: .top) {
            if layoutUpdate.isMultiple(of: 2) { Text("Layout update").frame(height: 1) }
        }
        .navigationTitle("Focus probe")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Dismiss") { monitorsFocus = false; dismiss() }
                    .accessibilityIdentifier("sample.sheet-focus.dismiss")
            }
        }
    }
}
