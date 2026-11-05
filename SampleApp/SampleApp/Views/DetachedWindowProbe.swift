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

/// Uses the same hierarchy-wide modifier in the app and in detached destinations.
struct DetachedWindowProbe: View {
    @State private var probe = DetachedWindowProbeState()

    private var routes: RootRouteMap {
        RootRouteMap {
            HighPriority { Sheet(DetachedHighRoute.self) }
            CriticalPriority { Sheet(DetachedCriticalRoute.self) }
        } destinations: {
            RouteDestination(DetachedHighRoute.self) { _, _ in DetachedProbeSheet(critical: false, probe: probe) }
            RouteDestination(DetachedCriticalRoute.self) { _, _ in DetachedProbeSheet(critical: true, probe: probe) }
        }
    }

    var body: some View {
        WithRouter(routes: routes) {
            NavigationStack { DetachedProbeControls(probe: probe).routing() }
                .modifier(HorizontalProbeToolbars())
        } windowDestination: { destination, _ in
            destination.modifier(HorizontalProbeToolbars())
        }
    }
}

private struct HorizontalProbeToolbars: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.toolbarVerticalBehavior(.disabled)
        } else {
            content
        }
    }
}

private struct DetachedHighRoute: Route {}
private struct DetachedCriticalRoute: Route {}

@MainActor @Observable
private final class DetachedWindowProbeState {
    @ObservationIgnored weak var sourceWindow: UIWindow?
}

private struct DetachedProbeControls: View {
    @Environment(\.router) private var router
    let probe: DetachedWindowProbeState

    var body: some View {
        VStack(spacing: 20) {
            Text("The app and detached sheets disable vertical toolbars with the same modifier.")
            Text("Present a sheet, fold or rotate the device, and read its native preferences.")
            Button("Present high sheet") { Task { await router.present(DetachedHighRoute()) } }
                .accessibilityIdentifier(SampleAppAccessibility.detachedPresent)
        }
        .padding()
        .navigationTitle("Detached window")
        .background(DetachedPolicyReader(probe: probe, isSource: true, report: { _ in }))
    }
}

private struct DetachedProbeSheet: View {
    @Environment(\.router) private var router
    @UnwindRoute private var unwind
    let critical: Bool
    let probe: DetachedWindowProbeState
    @State private var report = "Waiting for native layout"
    @State private var inspection = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Priority: \(critical ? "critical" : "high")\n\(report)")
                    .font(.caption.monospaced())
                    .accessibilityIdentifier(SampleAppAccessibility.detachedReport)
                Button("Read preferences") { inspection += 1 }
                    .accessibilityIdentifier(SampleAppAccessibility.detachedInspect)
                if !critical {
                    Button("Present critical sheet") { Task { await router.present(DetachedCriticalRoute()) } }
                        .accessibilityIdentifier(SampleAppAccessibility.detachedCritical)
                }
                Button("Dismiss") { Task { await unwind() } }
                    .accessibilityIdentifier(SampleAppAccessibility.detachedDismiss)
            }
            .padding()
            .navigationTitle(critical ? "Critical window" : "High window")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") { inspection += 1 }
                }
            }
            .routing()
        }
        .background(DetachedPolicyReader(probe: probe, inspection: inspection, report: { report = $0 }))
    }
}

private struct DetachedPolicyReader: UIViewControllerRepresentable {
    let probe: DetachedWindowProbeState
    var isSource = false
    var inspection = 0
    let report: (String) -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(probe: probe, isSource: isSource, report: report)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        if controller.inspection != inspection {
            controller.inspection = inspection
            controller.readAfterLayout()
        }
    }

    final class Controller: UIViewController {
        let probe: DetachedWindowProbeState
        let isSource: Bool
        let report: (String) -> Void
        var inspection = 0

        init(probe: DetachedWindowProbeState, isSource: Bool, report: @escaping (String) -> Void) {
            self.probe = probe
            self.isSource = isSource
            self.report = report
            super.init(nibName: nil, bundle: nil)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if isSource { probe.sourceWindow = view.window }
            else { readAfterLayout() }
        }

        func readAfterLayout() {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.read()
            }
        }

        private func read() {
            guard !isSource, let window = view.window, let root = window.rootViewController,
                  let source = probe.sourceWindow?.rootViewController else { return }
            let orientations = root.supportedInterfaceOrientations == source.supportedInterfaceOrientations
                && root.preferredInterfaceOrientationForPresentation == source.preferredInterfaceOrientationForPresentation
            let status = root.prefersStatusBarHidden == source.prefersStatusBarHidden
                && root.preferredStatusBarStyle == source.preferredStatusBarStyle
                && root.preferredStatusBarUpdateAnimation == source.preferredStatusBarUpdateAnimation
            var lines = ["Orientation matches: \(orientations)", "Status bar matches: \(status)",
                         "Detached window: \(window !== probe.sourceWindow)"]
            if #available(iOS 27.1, *) {
                var presented = root
                while let next = presented.presentedViewController { presented = next }
                while let next = presented.childForPreferredVerticalBarBehavior { presented = next }
                var sourceOwner = source
                while let next = sourceOwner.childForPreferredVerticalBarBehavior { sourceOwner = next }
                let sourceBehavior = sourceOwner.preferredVerticalBarBehavior
                let matches = root.preferredVerticalBarBehavior == sourceBehavior
                    && presented.preferredVerticalBarBehavior == sourceBehavior
                lines += ["Source toolbar: \(sourceBehavior == .disabled ? "disabled" : "automatic")",
                          "Toolbars match: \(matches)", "Elevated toolbar: \(root.preferredVerticalBarBehavior == .disabled ? "disabled" : "automatic")",
                          "Presentation toolbar: \(presented.preferredVerticalBarBehavior == .disabled ? "disabled" : "automatic")"]
            }
            lines += ["Window width: \(Int(window.bounds.width))", "Inspection: \(inspection)"]
            report(lines.joined(separator: "\n"))
        }
    }
}
