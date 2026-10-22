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
import OSLog

/// Direct-launch fixtures for physical push-host placement. Each shape uses the public API.
struct PushHostProbe: View {
    let scenario: String
    @State private var selection = "first"
    private let console = PushHostConsoleLog.shared

    private var routes: RootRouteMap {
        RootRouteMap {
            if scenario != "branch" { Push(PushHostFirst.self) { Push(PushHostSecond.self) } }
            Sheet(PushHostModal.self) { Push(PushHostFirst.self) { Push(PushHostSecond.self) } }
            Cover(PushHostCover.self) { Push(PushHostFirst.self) { Push(PushHostSecond.self) } }
            Cover(PushHostFade.self, transition: .fade) { Push(PushHostFirst.self) { Push(PushHostSecond.self) } }
            Sheet(PushHostPlain.self)
            Cover(PushHostPlainCover.self)
            if scenario == "branch" {
                Branches {
                    Branch("first") { Push(PushHostFirst.self) { Push(PushHostSecond.self) } }
                    Branch("second") { Push(PushHostFirst.self) { Push(PushHostSecond.self) } }
                }
            }
        } destinations: {
            RouteDestination(PushHostFirst.self) { route, _ in PushHostFirstScreen(pushImmediately: route.pushImmediately) }
            RouteDestination(PushHostSecond.self) { _, _ in PushHostSecondScreen() }
            RouteDestination(PushHostModal.self) { _, _ in PushHostModalStack() }
            RouteDestination(PushHostCover.self) { _, _ in PushHostModalStack() }
            RouteDestination(PushHostFade.self) { _, _ in PushHostModalStack() }
            RouteDestination(PushHostPlain.self) { _, _ in PushHostPlainScreen() }
            RouteDestination(PushHostPlainCover.self) { _, _ in PushHostPlainScreen() }
        }
    }

    var body: some View {
        if scenario == "outer" || scenario == "handover" {
            NavigationStack {
                WithRouter(routes: routes) { PushHostControls(handover: scenario == "handover") }
            }
        } else if scenario == "branch" {
            WithRouter(routes: routes) {
                TabView(selection: $selection) {
                    NavigationStack { PushHostControls().routing("first") }
                        .tabItem { Text("First") }.tag("first")
                    NavigationStack { PushHostControls().routing("second") }
                        .tabItem { Text("Second") }.tag("second")
                }
                .routing(branch: $selection)
            }
        } else if scenario == "missing" || scenario == "late" {
            WithRouter(routes: routes) {
                NavigationStack { PushHostControls(handover: scenario == "late", initiallyExplicit: false) }
            }
        } else {
            WithRouter(routes: routes) { NavigationStack { PushHostControls().routing() } }
        }
    }
}

private struct PushHostFirst: Route { var pushImmediately = false }
private struct PushHostSecond: Route {}
private struct PushHostModal: Route {}
private struct PushHostCover: Route {}
private struct PushHostFade: Route {}
private struct PushHostPlain: Route {}
private struct PushHostPlainCover: Route {}

private struct PushHostControls: View {
    var handover = false
    @Environment(\.router) private var router
    @State private var explicit = true

    init(handover: Bool = false, initiallyExplicit: Bool = true) {
        self.handover = handover
        _explicit = State(initialValue: initiallyExplicit)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Push host root").accessibilityIdentifier("sample.push-host.root")
            Button("Push first") { Task { await router.present(PushHostFirst()) } }
                .accessibilityIdentifier("sample.push-host.push-first")
            Button("Push immediate child") { Task { await router.present(PushHostFirst(pushImmediately: true)) } }
                .accessibilityIdentifier("sample.push-host.push-immediate")
            Button("Open sheet") { Task { await router.present(PushHostModal()) } }
                .accessibilityIdentifier("sample.push-host.sheet")
            Button("Open cover") { Task { await router.present(PushHostCover()) } }
                .accessibilityIdentifier("sample.push-host.cover")
            Button("Open fade cover") { Task { await router.present(PushHostFade()) } }
                .accessibilityIdentifier("sample.push-host.fade")
            Button("Open plain sheet") { Task { await router.present(PushHostPlain()) } }
                .accessibilityIdentifier("sample.push-host.plain-sheet")
            Button("Open plain cover") { Task { await router.present(PushHostPlainCover()) } }
                .accessibilityIdentifier("sample.push-host.plain-cover")
            if handover {
                Button(explicit ? "Remove explicit host" : "Install explicit host") { explicit.toggle() }
                    .accessibilityIdentifier("sample.push-host.explicit")
                Text(explicit ? "Enabled" : "Disabled")
                    .accessibilityIdentifier("sample.push-host.explicit-state")
                if explicit { Color.clear.frame(width: 0, height: 0).routing() }
            }
            PushHostConsole()
        }
        .navigationTitle("Host placement")
    }
}

private struct PushHostFirstScreen: View {
    var pushImmediately = false
    @Environment(\.router) private var router
    var body: some View {
        VStack(spacing: 16) {
            Text("First push").accessibilityIdentifier("sample.push-host.first")
            Button("Push second") { Task { await router.present(PushHostSecond()) } }
                .accessibilityIdentifier("sample.push-host.push-second")
            PushHostConsole()
        }
        .navigationTitle("First")
        .task { if pushImmediately { await router.present(PushHostSecond()) } }
        // Intentionally no .routing(): this destination inherits the parent's stack.
    }
}

private struct PushHostModalStack: View {
    @State private var path: [String] = []
    var body: some View {
        NavigationStack(path: $path) {
            PushHostControls()
                .navigationDestination(for: String.self) { Text($0) }
                .routing()
        }
    }
}

private struct PushHostSecondScreen: View {
    @UnwindRoute private var unwind
    var body: some View {
        VStack(spacing: 16) {
            Text("Second push").accessibilityIdentifier("sample.push-host.second")
            Button("Unwind") { Task { await unwind() } }
                .accessibilityIdentifier("sample.push-host.unwind")
            PushHostConsole()
        }
        .navigationTitle("Second")
    }
}

private struct PushHostPlainScreen: View {
    @UnwindRoute private var unwind
    var body: some View {
        VStack {
            Text("Plain modal").accessibilityIdentifier("sample.push-host.plain")
            Button("Close") { Task { await unwind() } }
                .accessibilityIdentifier("sample.push-host.close")
            PushHostConsole()
        }
    }
}

/// Read the entire process log: bundle-subsystem-only capture misses SwiftUI warnings.
@MainActor @Observable
private final class PushHostConsoleLog {
    static let shared = PushHostConsoleLog()
    private let started = Date()
    var output = "Console not read"
    var transcript = ""

    func read() {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(at: store.position(date: started))
                .compactMap { $0 as? OSLogEntryLog }
            let navigation = entries.filter {
                $0.composedMessage.contains("navigationDestination")
                    && ($0.composedMessage.contains("misplaced") || $0.composedMessage.contains("only works inside"))
            }
            let diagnostics = entries.filter {
                $0.subsystem == "eu.lelfe.departure" && $0.composedMessage.contains("outside a NavigationStack")
            }
            transcript = entries.map { "[\($0.subsystem)] \($0.composedMessage)" }.joined(separator: "\n")
            output = "SwiftUI navigation warnings: \(navigation.count)\n"
                + "Departure placement diagnostics: \(diagnostics.count)\n"
                + "Entries inspected: \(entries.count)\n"
                + (navigation + diagnostics).map { "[\($0.subsystem)] \($0.composedMessage)" }.joined(separator: "\n")
            print("[push-host-console] \(output)")
        } catch {
            output = "Console read failed: \(error)"
        }
    }
}

private struct PushHostConsole: View {
    @State private var console = PushHostConsoleLog.shared
    var body: some View {
        VStack(spacing: 8) {
            Button("Read console") { console.read() }
                .accessibilityIdentifier("sample.push-host.read-console")
            Text(console.output.components(separatedBy: "\n").prefix(3).joined(separator: "\n"))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(console.output)
                .accessibilityIdentifier("sample.push-host.console")
                .accessibilityValue(console.transcript)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
