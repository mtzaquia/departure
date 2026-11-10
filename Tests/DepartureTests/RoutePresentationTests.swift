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
import Testing
@testable import Departure

@MainActor @Suite struct RoutePresentationTests {
    @Test func outsideDestinationsHasNoPresentation() {
        let presentation: RoutePresentation = EnvironmentValues().routePresentation
        let state: RoutePresentationState = presentation
        #expect(state == presentation)
        #expect(presentation.effectivePresentationStyle == nil)
        #expect(!presentation.isWithinSheetRoute)
        #expect(!presentation.isGlobalRoute)
    }

    @Test func legacyAccessorsPreserveDeclaredMetadataForAdaptedSheets() {
        let sheet = Sheet(SettingsRoute.self, compactAdaptation: .cover).declaration.globallyAvailable()
        let presentation: RoutePresentationState = RoutePresentation().presenting(sheet, effectiveStyle: .cover(.slide))
        #expect(presentation.effectivePresentationStyle == .cover(.slide))
        #expect(!presentation.isWithinSheetRoute)
        #expect(presentation.style == .sheet)
        #expect(presentation.compactAdaptation == .cover)
        #expect(presentation.isGlobal == presentation.isGlobalRoute)
    }

    @Test(arguments: [false, true], Sheet.CompactAdaptation.allCases)
    func effectiveStyleResolvesAdaptationWithoutChangingDeclaration(compact: Bool, adaptation: Sheet.CompactAdaptation) {
        let declared = Sheet(SettingsRoute.self, compactAdaptation: adaptation).declaration.presentation
        #if canImport(UIKit)
        let expected: RoutePresentation.Style = compact && adaptation == .cover ? .cover(.slide) : .sheet
        #else
        let expected: RoutePresentation.Style = .sheet
        #endif
        #expect(declared.effectiveStyle(inCompactSizeClass: compact) == expected)
        #expect(declared.declaredStyle == .sheet)
        #expect(declared.declaredCompactAdaptation == adaptation)
    }

    @Test(arguments: [RoutePresentation.Style.push, .replace, .sheet, .cover(.slide), .cover(.fade)])
    func unadaptedStylesMatchTheNativePlatform(style: RoutePresentation.Style) {
        let declared = RoutePresentation(style: style)
        #if canImport(UIKit)
        let expected = style
        #else
        let expected: RoutePresentation.Style = style.isModal ? .sheet : style
        #endif
        #expect(declared.effectiveStyle(inCompactSizeClass: false) == expected)
        #expect(declared.effectiveStyle(inCompactSizeClass: true) == expected)
    }

    @Test func sheetAncestryPassesThroughPushesAndReplacementsUntilAnotherModal() {
        let sheet = Sheet(SettingsRoute.self).declaration.globallyAvailable()
        let push = Push(HomeDetailRoute.self).declaration
        let replace = Replace(LoginRoute.self).declaration
        let cover = Cover(MessageRoute.self).declaration
        let modal = RoutePresentationState().presenting(sheet)
        #expect(modal.isWithinSheetRoute)
        #expect(modal.isGlobalRoute)

        let first = modal.presenting(push)
        let second = first.presenting(push)
        let replacement = second.presenting(replace)
        #expect(first.effectivePresentationStyle == .push)
        #expect(second.isWithinSheetRoute)
        #expect(replacement.effectivePresentationStyle == .replace)
        #expect(replacement.isWithinSheetRoute)
        #expect(!first.isGlobalRoute)
        #expect(!replacement.isGlobalRoute)

        let covering = replacement.presenting(cover)
        #expect(!covering.isWithinSheetRoute)
        #expect(!covering.presenting(push).isWithinSheetRoute)
        #expect(!covering.presenting(replace).isWithinSheetRoute)
        #expect(covering.presenting(sheet).isWithinSheetRoute)
    }

    @Test func adaptedGlobalSheetKeepsGlobalIdentityAndOverridesSheetAncestry() {
        let sheet = Sheet(SettingsRoute.self, compactAdaptation: .cover).declaration.globallyAvailable()
        let parent = RoutePresentationState(effectivePresentationStyle: .sheet, isWithinSheetRoute: true)
        let adapted = parent.presenting(sheet, effectiveStyle: .cover(.slide))
        #expect(adapted.effectivePresentationStyle == .cover(.slide))
        #expect(!adapted.isWithinSheetRoute)
        #expect(adapted.isGlobalRoute)
        let child = adapted.presenting(Push(HomeDetailRoute.self).declaration)
        #expect(child.effectivePresentationStyle == .push)
        #expect(!child.isWithinSheetRoute)
        #expect(!child.isGlobalRoute)
    }
}
