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
        case push, sheet, cover

        var presentationKind: RoutePresentationKind {
            switch self {
            case .push: .push
            case .sheet: .sheet
            case .cover: .cover(.slide)
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
            content.modifier(SystemModalPresentationModifier(style: .sheet, route: presentation.wrappedValue))
        case .cover:
            content.modifier(SystemModalPresentationModifier(style: .cover(.slide), route: presentation.wrappedValue))
        }
    }
}

/// A stable rendered destination survives logical removal until native `onDismiss`.
struct SystemModalPresentationModifier: ViewModifier {
    let style: RoutePresentationKind
    let route: PresentedRoute?
    var destinationBuilder: WindowDestinationBuilder?
    @RouterEnvironment private var router
    @State private var lifetime = NativePresentationLifetime()

    func body(content: Content) -> some View {
        let rendered = lifetime.presentation
        let presented = Binding(get: { lifetime.isPresented }, set: { value in
            guard !value, let rendered else { return }
            // Native write-back can arrive inside SwiftUI's update transaction.
            Task { @MainActor in
                lifetime.requestDismissal(of: rendered.id, in: router)
            }
        })
        return systemPresentation(content, presented: presented, rendered: rendered)
            .onChange(of: route?.id, initial: true) { _, _ in synchronize() }
            .onLifecycleEvent { _, _, event in
                switch event {
                case .installedInWindow: synchronize()
                case .dismantled, .deinitialized:
                    if let id = lifetime.presentation?.id { lifetime.completeDismissal(of: id, in: router) }
                case .updated: break
                }
            }
    }

    @ViewBuilder
    private func systemPresentation(_ content: Content, presented: Binding<Bool>, rendered: RouteDestinationSnapshot?) -> some View {
        #if canImport(UIKit)
        if style != .sheet {
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

    private func destination(_ rendered: RouteDestinationSnapshot) -> some View {
        rendered.destination.id(rendered.id)
            .onLifecycleEvent { _, _, event in
                switch event {
                case .installedInWindow, .updated: lifetime.didAdmitPresentation(of: rendered.id)
                case .dismantled, .deinitialized: break
                }
            }
    }

    private func synchronize() {
        lifetime.synchronize(route) {
            if let destinationBuilder { RouteDestinationSnapshot(route: $0, destinationBuilder: destinationBuilder) }
            else { RouteDestinationSnapshot(route: $0) }
        }
    }
    private func complete(_ rendered: RouteDestinationSnapshot?) {
        guard let rendered else { return }
        lifetime.completeDismissal(of: rendered.id, in: router)
        synchronize()
    }
}
