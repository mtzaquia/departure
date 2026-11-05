import Departure
import SwiftUI
import UIKit

struct GlobalRoutesLabRoute: Route {}
private struct GlobalDetailRoute: Route, Equatable {}
private struct GlobalPasscodeRoute: Route, Equatable {}
private struct GlobalSecondFactorRoute: Route, Equatable {}
private struct GlobalHelpRoute: Route, Equatable {}
private struct GlobalProtectedSheetRoute: Route, Equatable {}
private struct GlobalPasscodeChildRoute: Route, Equatable {}

private extension EnvironmentValues {
    @Entry var globalLabBadge = "missing"
}

@MainActor @Observable
private final class GlobalLabState {
    @ObservationIgnored weak var sourceWindow: UIWindow?
}

/// A single-window showcase for shared declarations and active-only protection.
struct GlobalRoutesProbe: View {
    @State private var owner = RootRouter()
    @State private var state = GlobalLabState()
    let closeLab: UnwindRouteAction?

    init(closeLab: UnwindRouteAction? = nil) { self.closeLab = closeLab }

    private var routes: RootRouteMap {
        let coveredRouter = owner.root
        let state = state
        return RootRouteMap {
            Push(GlobalDetailRoute.self)
            GlobalMap {
                Sheet(GlobalSecondFactorRoute.self)
                Cover(GlobalPasscodeRoute.self, transition: .fade) {
                    Sheet(GlobalHelpRoute.self)
                    Push(GlobalPasscodeChildRoute.self)
                }.dismissalProtection()
                Sheet(GlobalProtectedSheetRoute.self).dismissalProtection()
            }
        } destinations: {
            RouteDestination(GlobalDetailRoute.self) { _, _ in GlobalLabHome(detail: true) }
            RouteDestination(GlobalPasscodeRoute.self) { _, _ in
                NavigationStack { GlobalPasscodeView(coveredRouter: coveredRouter, state: state).routing() }
                    .interactiveDismissDisabled()
            }
            RouteDestination(GlobalSecondFactorRoute.self) { _, _ in
                NavigationStack { GlobalLabOverlay(title: "Two-factor authentication", state: state).routing() }
            }
            RouteDestination(GlobalHelpRoute.self) { _, _ in
                NavigationStack { GlobalLabOverlay(title: "Passcode help", state: state).routing() }
            }
            RouteDestination(GlobalProtectedSheetRoute.self) { _, _ in
                NavigationStack { GlobalLabOverlay(title: "Protected sheet", state: state).routing() }
                    .interactiveDismissDisabled()
            }
            RouteDestination(GlobalPasscodeChildRoute.self) { _, _ in
                GlobalLabOverlay(title: "Unprotected child", state: state)
            }
        }
    }

    var body: some View {
        WithRouter(routes: routes, router: owner) {
            NavigationStack {
                GlobalLabHome(detail: false)
                    .routing()
                    .toolbar {
                        if let closeLab {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close lab") { Task { await closeLab() } }
                                    .accessibilityIdentifier("sample.globals.close-lab")
                            }
                        }
                    }
            }
            .background(GlobalWindowReader(state: state, source: true))
        }
        .environment(\.globalLabBadge, "inherited configuration")
    }
}

private struct GlobalLabHome: View {
    let detail: Bool
    @Environment(\.router) private var router
    @UnwindRoute private var unwind
    @State private var note = ""

    var body: some View {
        Form {
            Section {
                Text("One GlobalMap supplies 2FA and passcode from either screen. Protection applies only to the active route.")
                Text(detail ? "App detail" : "App root")
                    .accessibilityIdentifier("sample.globals.location")
                TextField("Retained app note", text: $note)
                    .accessibilityIdentifier("sample.globals.note")
            }
            Section("Global destinations") {
                Button("Present 2FA") { Task { await router.present(GlobalSecondFactorRoute()) } }
                    .accessibilityIdentifier("sample.globals.2fa")
                Button("Lock with fade") { Task { await router.present(GlobalPasscodeRoute()) } }
                    .accessibilityIdentifier("sample.globals.lock")
            }
            if !detail {
                Button("Open app detail") { Task { await router.present(GlobalDetailRoute()) } }
                    .accessibilityIdentifier("sample.globals.detail")
            } else {
                Button("Back to app root") { Task { await unwind() } }
                    .accessibilityIdentifier("sample.globals.back")
            }
        }
        .navigationTitle("Global routes")
    }
}

private struct GlobalPasscodeView: View {
    let coveredRouter: Router
    let state: GlobalLabState
    @Environment(\.router) private var router
    @Environment(\.routePhase) private var phase
    @UnwindRoute private var unwind
    @State private var attempted = false

    var body: some View {
        Form {
            Section {
                Text("Passcode lock").accessibilityIdentifier("sample.globals.passcode")
                Text(phase == .active ? "Protection active" : "Protection inactive")
                    .accessibilityIdentifier("sample.globals.protection")
                Text("Unrelated app navigation is blocked here. A global or a declared child may present above the lock, suspending its protection.")
                GlobalWindowStatus(state: state)
            }
            Section("Try the admission rules") {
                Button("Request app detail from covered root") {
                    Task { await coveredRouter.present(GlobalDetailRoute()); attempted = true }
                }.accessibilityIdentifier("sample.globals.covered-request")
                if attempted {
                    Text("Covered request attempted").accessibilityIdentifier("sample.globals.attempted")
                }
                Button("Present global 2FA") { Task { await router.present(GlobalSecondFactorRoute()) } }
                    .accessibilityIdentifier("sample.globals.over-lock")
                Button("Present declared help") { Task { await router.present(GlobalHelpRoute()) } }
                    .accessibilityIdentifier("sample.globals.help")
                Button("Push unprotected child") { Task { await router.present(GlobalPasscodeChildRoute()) } }
                    .accessibilityIdentifier("sample.globals.child")
                Button("Present another protected global") { Task { await router.present(GlobalProtectedSheetRoute()) } }
                    .accessibilityIdentifier("sample.globals.protected-overlay")
            }
        }
        .navigationTitle("Passcode")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Unlock") { Task { await unwind() } }
                    .accessibilityIdentifier("sample.globals.unlock")
            }
        }
    }
}

private struct GlobalLabOverlay: View {
    let title: String
    let state: GlobalLabState
    @Environment(\.router) private var router
    @UnwindRoute private var unwind
    @State private var code = ""

    var body: some View {
        Form {
            Text(title).accessibilityIdentifier("sample.globals.overlay-title")
            GlobalWindowStatus(state: state)
            TextField("Authentication code", text: $code)
                .accessibilityIdentifier("sample.globals.code")
            Button("Done") { Task { await unwind() } }
                .accessibilityIdentifier("sample.globals.done")
            Button("Crawl back to app detail") { Task { await router.present(GlobalDetailRoute()) } }
                .accessibilityIdentifier("sample.globals.crawlback")
        }
        .navigationTitle(title)
    }
}

private struct GlobalWindowStatus: View {
    let state: GlobalLabState
    @Environment(\.globalLabBadge) private var badge
    @State private var sameWindow = false

    var body: some View {
        Text("Same window: \(String(sameWindow)) · \(badge)")
            .font(.caption)
            .accessibilityIdentifier("sample.globals.environment")
            .background(GlobalWindowReader(state: state, source: false) { sameWindow = $0 })
    }
}

private struct GlobalWindowReader: UIViewRepresentable {
    let state: GlobalLabState
    let source: Bool
    var report: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> WindowView { WindowView() }
    func updateUIView(_ view: WindowView, context: Context) {
        view.state = state
        view.source = source
        view.report = report
        view.inspect()
    }

    final class WindowView: UIView {
        var state: GlobalLabState?
        var source = false
        var report: ((Bool) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); inspect() }
        override func layoutSubviews() { super.layoutSubviews(); inspect() }
        func inspect() {
            guard let window, let state else { return }
            let report = report
            let source = source
            Task { @MainActor [weak window] in
                await Task.yield()
                guard let window else { return }
                if source { state.sourceWindow = window }
                else { report?(window === state.sourceWindow) }
            }
        }
    }
}
