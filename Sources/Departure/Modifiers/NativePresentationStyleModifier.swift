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

import SwiftUI

/// Each native style stays fixed within its independent presentation host slot.
struct NativePresentationStyleModifier: ViewModifier {
    enum Style {
        case push, sheet, cover(Cover.Transition)

        var presentationKind: RoutePresentationKind {
            switch self {
            case .push: .push
            case .sheet: .sheet
            case .cover(let transition): .cover(transition)
            }
        }
    }

    let style: Style
    let presentationHostID: RoutePresentationHostID
    @RouterEnvironment private var router
    @Environment(\.routeScope) private var routeScope

    @ViewBuilder
    func body(content: Content) -> some View {
        let presentation = router.routePresentationBinding(
            from: routeScope, matching: style.presentationKind, hostedBy: presentationHostID
        )
        switch style {
        case .push:
            let disablesDismissalAnimations = router.pushPresentationDismissalDisablesAnimations(
                from: routeScope, hostedBy: presentationHostID
            )
            content
                .navigationDestination(item: presentation) { RouteView(scope: $0.scope) }
                .transaction { transaction in
                    if disablesDismissalAnimations { transaction.disablesAnimations = true }
                }
        case .sheet:
            content.modifier(SystemModalPresentationModifier(style: .sheet, route: presentation))
        case .cover(let transition):
            #if canImport(UIKit)
            let builder = transition == .fade ? router.windowDestinationBuilder : nil
            #else
            let builder: WindowDestinationBuilder? = nil
            #endif
            content.modifier(SystemModalPresentationModifier(style: .cover(transition), route: presentation, destinationBuilder: builder))
        }
    }
}

/// A stable rendered destination survives logical removal until native `onDismiss`.
struct SystemModalPresentationModifier: ViewModifier {
    let style: RoutePresentationKind
    @Binding var route: PresentedRoute?
    var destinationBuilder: WindowDestinationBuilder?
    @RouterEnvironment private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var lifetime = NativePresentationLifetime()
    @State private var fade: Fade = .hidden

    private enum Fade: Equatable {
        case hidden, visible, dismissed(PresentedRoute.ID)
        var opacity: Double { self == .visible ? 1 : 0 }
    }

    private var fades: Bool {
        #if canImport(UIKit)
        style == .cover(.fade)
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        let rendered = lifetime.presentation
        let presented = Binding(get: {
            if fades { return rendered.map { fade != .dismissed($0.id) } ?? false }
            return lifetime.isPresented
        }, set: { value in
            guard !value, let rendered else { return }
            // Native write-back can arrive inside SwiftUI's update transaction.
            Task { @MainActor in
                lifetime.requestDismissal(of: rendered.id, in: router)
            }
        })
        return systemPresentation(content, presented: presented, rendered: rendered)
            .onChange(of: route?.id, initial: true) { _, _ in synchronize() }
            .onChange(of: lifetime.presentation?.id) { _, id in
                if id == nil { synchronize() }
            }
            .onChange(of: admittedFadeID, initial: true) { _, id in
                guard let id, lifetime.presentation?.id == id, lifetime.isPresented else { return }
                withAnimation(.easeInOut(duration: 0.35)) { fade = .visible }
            }
            .task(id: fades ? lifetime.dismissalID : nil) {
                guard fades, let id = lifetime.dismissalID else { return }
                withAnimation(.easeInOut(duration: 0.25), completionCriteria: .removed) {
                    fade = .hidden
                } completion: {
                    guard lifetime.dismissalID == id else { return }
                    fade = .dismissed(id)
                }
            }
            .onLifecycleEvent { _, _, event in
                switch event {
                case .installedInWindow: synchronize()
                case .ended:
                    if let id = lifetime.presentation?.id { lifetime.completeDismissal(of: id, in: router) }
                case .created, .updated: break
                }
            }
    }

    @ViewBuilder
    private func systemPresentation(_ content: Content, presented: Binding<Bool>, rendered: RouteDestinationSnapshot?) -> some View {
        #if canImport(UIKit)
        if fades {
            content.fullScreenCover(isPresented: presented, onDismiss: { complete(rendered) }) {
                if let rendered { destination(rendered).presentationBackground(.clear) }
            }
            .transaction { $0.disablesAnimations = true }
        } else if style != .sheet {
            content.fullScreenCover(isPresented: presented, onDismiss: { complete(rendered) }) {
                if let rendered { destination(rendered) }
            }
        } else {
            content.sheet(isPresented: presented, onDismiss: { complete(rendered) }) {
                if let rendered { destination(rendered) }
            }
        }
        #else
        content.sheet(isPresented: presented, onDismiss: { complete(rendered) }) {
            if let rendered { destination(rendered) }
        }
        #endif
    }

    @ViewBuilder
    private func destination(_ rendered: RouteDestinationSnapshot) -> some View {
        if fades {
            rendered.destination.id(rendered.id)
                .environment(\.routerEngine, router)
                .environment(\.scenePhase, scenePhase)
                .opacity(fade.opacity)
        } else {
            rendered.destination.id(rendered.id)
        }
    }

    private var admittedFadeID: PresentedRoute.ID? {
        guard fades, let rendered = lifetime.presentation, lifetime.isAdmitted else { return nil }
        return rendered.id
    }

    private func synchronize() {
        let previousID = lifetime.presentation?.id
        lifetime.synchronize(route) {
            if let destinationBuilder { RouteDestinationSnapshot(route: $0, destinationBuilder: destinationBuilder, nativePresentation: lifetime) }
            else { RouteDestinationSnapshot(route: $0, nativePresentation: lifetime) }
        }
        if previousID != lifetime.presentation?.id { fade = .hidden }
    }
    private func complete(_ rendered: RouteDestinationSnapshot?) {
        guard let rendered else { return }
        lifetime.completeDismissal(of: rendered.id, in: router)
        synchronize()
    }
}
