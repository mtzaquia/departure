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

@MainActor @Observable
private final class DismissalStackProbeState {
    static let shared = DismissalStackProbeState()

    var currentDepth = 0
    var minimumExitDepth = 0
    var exitSamples = 0
    var firstDepthDropMilliseconds = -1
    var isExiting = false
    private var exitStartedAt = 0.0
    private var exitStartingDepth = 0
    var sheetRouter: Router?
    var sheetDismiss: (() -> Void)?

    func beginExit() {
        exitStartedAt = ProcessInfo.processInfo.systemUptime
        exitStartingDepth = currentDepth
        minimumExitDepth = currentDepth
        exitSamples = 0
        firstDepthDropMilliseconds = -1
        isExiting = true
    }

    func sample(depth: Int) {
        currentDepth = depth
        guard isExiting else { return }
        minimumExitDepth = min(minimumExitDepth, depth)
        exitSamples += 1
        if depth < exitStartingDepth && firstDepthDropMilliseconds == -1 {
            firstDepthDropMilliseconds = Int((ProcessInfo.processInfo.systemUptime - exitStartedAt) * 1000)
        }
    }
}

struct DismissalStackProbeRoot: View {
    @Environment(\.router) private var router
    @State private var probe = DismissalStackProbeState.shared

    var body: some View {
        VStack {
            Button("Present sheet") {
                probe.isExiting = false
                Task { await router.present(DismissalStackProbeSheetRoute()) }
            }
            .accessibilityIdentifier("sample.dismissal-probe.present")

            Text("Minimum exit depth: \(probe.minimumExitDepth)")
                .accessibilityIdentifier("sample.dismissal-probe.minimum-depth")
            Text("Exit samples: \(probe.exitSamples)")
                .accessibilityIdentifier("sample.dismissal-probe.samples")
            Text("First depth drop: \(probe.firstDepthDropMilliseconds)")
                .accessibilityIdentifier("sample.dismissal-probe.first-drop")
        }
        .routing()
    }
}

private struct DismissalStackProbeSheetRoute: Route {

}

private struct DismissalStackProbeFirstRoute: Route {

}

private struct DismissalStackProbeSecondRoute: Route {

}

private struct DismissalStackProbeSheet: View {
    @Environment(\.router) private var router
    @Environment(\.dismiss) private var dismiss
    private let probe = DismissalStackProbeState.shared

    var body: some View {
        NavigationStack {
            Button("Push first") { Task { await router.present(DismissalStackProbeFirstRoute()) } }
                .accessibilityIdentifier("sample.dismissal-probe.push-first")
                .routing()
        }
        .background(DismissalStackDepthSampler())
        .onAppear {
            probe.sheetRouter = router
            probe.sheetDismiss = { dismiss() }
        }
    }
}

private struct DismissalStackProbeFirst: View {
    @Environment(\.router) private var router

    var body: some View {
        Button("Push second") { Task { await router.present(DismissalStackProbeSecondRoute()) } }
            .accessibilityIdentifier("sample.dismissal-probe.push-second")
            .routing()
    }
}

private struct DismissalStackProbeSecond: View {
    private let probe = DismissalStackProbeState.shared

    var body: some View {
        VStack {
            Text("Second push")
                .accessibilityIdentifier("sample.dismissal-probe.second")
            Text("Current depth: \(probe.currentDepth)")
                .accessibilityIdentifier("sample.dismissal-probe.current-depth")
            Button("Unwind to root") {
                probe.beginExit()
                Task { await probe.sheetRouter?.unwind(to: .root) }
            }
            .accessibilityIdentifier("sample.dismissal-probe.unwind")
            Button("Unwind to ancestor") {
                probe.beginExit()
                Task { await probe.sheetRouter?.unwind(to: .topmostAncestor) }
            }
            .accessibilityIdentifier("sample.dismissal-probe.unwind-ancestor")
            Button("Dismiss sheet") {
                probe.beginExit()
                probe.sheetDismiss?()
            }
            .accessibilityIdentifier("sample.dismissal-probe.dismiss")
        }
    }
}

private struct DismissalStackDepthSampler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DismissalStackDepthController {
        DismissalStackDepthController()
    }

    func updateUIViewController(_ controller: DismissalStackDepthController, context: Context) {}
}

private final class DismissalStackDepthController: UIViewController {
    private var samplingTask: Task<Void, Never>?
    private weak var trackedNavigationController: UINavigationController?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            while let self, !Task.isCancelled, view.window != nil {
                if !DismissalStackProbeState.shared.isExiting {
                    var root: UIViewController = self
                    while let parent = root.parent { root = parent }
                    if let candidate = Self.deepestNavigationController(in: root),
                       candidate.viewControllers.count >= (trackedNavigationController?.viewControllers.count ?? 0) {
                        trackedNavigationController = candidate
                    }
                }
                if let trackedNavigationController {
                    DismissalStackProbeState.shared.sample(depth: trackedNavigationController.viewControllers.count)
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private static func deepestNavigationController(in controller: UIViewController) -> UINavigationController? {
        let own = controller as? UINavigationController
        return ([own] + controller.children.map { deepestNavigationController(in: $0) })
            .compactMap { $0 }
            .max { $0.viewControllers.count < $1.viewControllers.count }
    }
}



private enum DismissalStackDestinations {
    static let dismissalStackProbeSheetRoute = RouteDestination(DismissalStackProbeSheetRoute.self) { route, context in
        DismissalStackProbeSheet()
    }
    static let dismissalStackProbeFirstRoute = RouteDestination(DismissalStackProbeFirstRoute.self) { route, context in
        DismissalStackProbeFirst()
    }
    static let dismissalStackProbeSecondRoute = RouteDestination(DismissalStackProbeSecondRoute.self) { route, context in
        DismissalStackProbeSecond()
    }
}


enum DismissalStackProbeMap {
    static let root = RootRouteMap {
        Sheet(DismissalStackDestinations.dismissalStackProbeSheetRoute) {
            Push(DismissalStackDestinations.dismissalStackProbeFirstRoute) {
                Push(DismissalStackDestinations.dismissalStackProbeSecondRoute)
            }
        }
    }
}
