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
private final class NestedModalProbeState {
    static let shared = NestedModalProbeState()

    var sheetARouter: Router?
    var aDepth = 0
    var bDepth = 0
    var aMinimumExitDepth = 0
    var bMinimumExitDepth = 0
    var aExitSamples = 0
    var bExitSamples = 0
    var isExiting = false

    func beginExit() {
        aMinimumExitDepth = aDepth
        bMinimumExitDepth = bDepth
        aExitSamples = 0
        bExitSamples = 0
        isExiting = true
    }

    func sampleA(_ depth: Int) {
        aDepth = depth
        guard isExiting else { return }
        aMinimumExitDepth = min(aMinimumExitDepth, depth)
        aExitSamples += 1
    }

    func sampleB(_ depth: Int) {
        bDepth = depth
        guard isExiting else { return }
        bMinimumExitDepth = min(bMinimumExitDepth, depth)
        bExitSamples += 1
    }
}

struct NestedModalProbeRoot: View {
    @Environment(\.router) private var router
    @State private var probe = NestedModalProbeState.shared

    private var priority: RoutePriority {
        if ProcessInfo.processInfo.arguments.contains("--nested-modal-critical") { return .critical }
        if ProcessInfo.processInfo.arguments.contains("--nested-modal-high") { return .high }
        return .default
    }

    var body: some View {
        VStack {
            Button("Present sheet A") {
                probe.isExiting = false
                Task { await router.present(NestedModalProbeSheetARoute()) }
            }
            .accessibilityIdentifier("sample.nested-modal.present-a")
            Text("A minimum exit depth: \(probe.aMinimumExitDepth)")
                .accessibilityIdentifier("sample.nested-modal.a-minimum-depth")
            Text("B minimum exit depth: \(probe.bMinimumExitDepth)")
                .accessibilityIdentifier("sample.nested-modal.b-minimum-depth")
            Text("A exit samples: \(probe.aExitSamples)")
                .accessibilityIdentifier("sample.nested-modal.a-samples")
            Text("B exit samples: \(probe.bExitSamples)")
                .accessibilityIdentifier("sample.nested-modal.b-samples")
        }
        .routing()
    }
}

private struct NestedModalProbeSheetARoute: Route, Equatable {

}

private struct NestedModalProbeAPushRoute: Route {

}

private struct NestedModalProbeSheetBRoute: Route {

}

private struct NestedModalProbeBPushRoute: Route {

}

private struct NestedModalProbeSheetA: View {
    @Environment(\.router) private var router
    private let probe = NestedModalProbeState.shared

    var body: some View {
        NavigationStack {
            VStack {
                Button("Push in A") { Task { await router.present(NestedModalProbeAPushRoute()) } }
                    .accessibilityIdentifier("sample.nested-modal.push-a")
                Text("B minimum exit depth: \(probe.bMinimumExitDepth)")
                    .accessibilityIdentifier("sample.nested-modal.retained-b-minimum-depth")
                Text("B exit samples: \(probe.bExitSamples)")
                    .accessibilityIdentifier("sample.nested-modal.retained-b-samples")
            }
            .routing()
        }
        .background(NestedModalDepthSampler(isSheetA: true))
        .onAppear { probe.sheetARouter = router }
    }
}

private struct NestedModalProbeAPush: View {
    @Environment(\.router) private var router

    var body: some View {
        Button("Present sheet B") { Task { await router.present(NestedModalProbeSheetBRoute()) } }
            .accessibilityIdentifier("sample.nested-modal.present-b")
            .routing()
    }
}

private struct NestedModalProbeSheetB: View {
    @Environment(\.router) private var router

    var body: some View {
        NavigationStack {
            Button("Push in B") { Task { await router.present(NestedModalProbeBPushRoute()) } }
                .accessibilityIdentifier("sample.nested-modal.push-b")
                .routing()
        }
        .background(NestedModalDepthSampler(isSheetA: false))
    }
}

private struct NestedModalProbeBPush: View {
    @Environment(\.router) private var router
    private let probe = NestedModalProbeState.shared

    var body: some View {
        VStack {
            Text("A depth: \(probe.aDepth)")
                .accessibilityIdentifier("sample.nested-modal.a-depth")
            Text("B depth: \(probe.bDepth)")
                .accessibilityIdentifier("sample.nested-modal.b-depth")
            Button("Unwind A to root") {
                probe.beginExit()
                Task { await probe.sheetARouter?.unwind(to: .root) }
            }
            .accessibilityIdentifier("sample.nested-modal.unwind")
            Button("Present existing A") {
                probe.beginExit()
                Task { await router.present(NestedModalProbeSheetARoute()) }
            }
            .accessibilityIdentifier("sample.nested-modal.reuse-a")
        }
    }
}

private struct NestedModalDepthSampler: UIViewControllerRepresentable {
    let isSheetA: Bool

    func makeUIViewController(context: Context) -> NestedModalDepthController {
        NestedModalDepthController(isSheetA: isSheetA)
    }

    func updateUIViewController(_ controller: NestedModalDepthController, context: Context) {}
}

private final class NestedModalDepthController: UIViewController {
    private let isSheetA: Bool
    private var samplingTask: Task<Void, Never>?
    private weak var trackedNavigationController: UINavigationController?

    init(isSheetA: Bool) {
        self.isSheetA = isSheetA
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            while let self, !Task.isCancelled, view.window != nil {
                if !NestedModalProbeState.shared.isExiting {
                    var root: UIViewController = self
                    while let parent = root.parent { root = parent }
                    if let candidate = Self.deepestNavigationController(in: root),
                       candidate.viewControllers.count >= (trackedNavigationController?.viewControllers.count ?? 0) {
                        trackedNavigationController = candidate
                    }
                }
                if let trackedNavigationController {
                    let depth = trackedNavigationController.viewControllers.count
                    if isSheetA {
                        NestedModalProbeState.shared.sampleA(depth)
                    } else {
                        NestedModalProbeState.shared.sampleB(depth)
                    }
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


private enum NestedModalDestinations {
    static let nestedModalProbeSheetARoute = RouteDestination(NestedModalProbeSheetARoute.self) { route, context in
        NestedModalProbeSheetA()
    }
    static let nestedModalProbeAPushRoute = RouteDestination(NestedModalProbeAPushRoute.self) { route, context in
        NestedModalProbeAPush()
    }
    static let nestedModalProbeSheetBRoute = RouteDestination(NestedModalProbeSheetBRoute.self) { route, context in
        NestedModalProbeSheetB()
    }
    static let nestedModalProbeBPushRoute = RouteDestination(NestedModalProbeBPushRoute.self) { route, context in
        NestedModalProbeBPush()
    }
}


enum NestedModalProbeMap {
    private static let nested = RouteMap {
        Push(NestedModalDestinations.nestedModalProbeAPushRoute) {
            Sheet(NestedModalDestinations.nestedModalProbeSheetBRoute) {
                Push(NestedModalDestinations.nestedModalProbeBPushRoute)
            }
        }
    }
    static var root: RootRouteMap {
        let arguments = ProcessInfo.processInfo.arguments
        return RootRouteMap {
            if !arguments.contains("--nested-modal-high") && !arguments.contains("--nested-modal-critical") {
                Sheet(NestedModalDestinations.nestedModalProbeSheetARoute) { nested }
            }
        } highPriority: {
            if arguments.contains("--nested-modal-high") {
                Sheet(NestedModalDestinations.nestedModalProbeSheetARoute) { nested }
            }
        } criticalPriority: {
            if arguments.contains("--nested-modal-critical") {
                Sheet(NestedModalDestinations.nestedModalProbeSheetARoute) { nested }
            }
        }
    }
}
