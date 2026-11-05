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

#if canImport(UIKit)
import UIKit

final class WindowRootHostingController<Content: View>: UIHostingController<Content> {
    var onDismiss: (@MainActor () -> Void)?
    weak var coveredWindow: UIWindow?

    // Resolve on every query: the covered window can replace its root, present a
    // modal, or change container selection while this window is installed.
    private var coveredPresenter: UIViewController? {
        guard var controller = coveredWindow?.rootViewController, controller !== self else { return nil }
        while let presented = controller.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }

    private func coveredPreferenceOwner(_ child: KeyPath<UIViewController, UIViewController?>) -> UIViewController? {
        guard var controller = coveredPresenter else { return nil }
        while let next = controller[keyPath: child], next !== controller {
            controller = next
        }
        return controller
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        coveredPresenter?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        coveredPresenter?.preferredInterfaceOrientationForPresentation ?? super.preferredInterfaceOrientationForPresentation
    }

    // Do not return a controller from another window as a containment child.
    // Resolve its child delegation here and report the resulting value instead.
    override var childForStatusBarHidden: UIViewController? {
        coveredPresenter == nil ? super.childForStatusBarHidden : nil
    }

    override var childForStatusBarStyle: UIViewController? {
        coveredPresenter == nil ? super.childForStatusBarStyle : nil
    }

    override var prefersStatusBarHidden: Bool {
        coveredPreferenceOwner(\.childForStatusBarHidden)?.prefersStatusBarHidden ?? super.prefersStatusBarHidden
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        coveredPreferenceOwner(\.childForStatusBarStyle)?.preferredStatusBarStyle ?? super.preferredStatusBarStyle
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        coveredPreferenceOwner(\.childForStatusBarHidden)?.preferredStatusBarUpdateAnimation ?? super.preferredStatusBarUpdateAnimation
    }

    override var childForHomeIndicatorAutoHidden: UIViewController? {
        coveredPresenter == nil ? super.childForHomeIndicatorAutoHidden : nil
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        coveredPreferenceOwner(\.childForHomeIndicatorAutoHidden)?.prefersHomeIndicatorAutoHidden ?? super.prefersHomeIndicatorAutoHidden
    }

    override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
        coveredPresenter == nil ? super.childForScreenEdgesDeferringSystemGestures : nil
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        coveredPreferenceOwner(\.childForScreenEdgesDeferringSystemGestures)?.preferredScreenEdgesDeferringSystemGestures
            ?? super.preferredScreenEdgesDeferringSystemGestures
    }

    @available(iOS 27.1, tvOS 27.1, visionOS 27.1, *)
    override var childForPreferredVerticalBarBehavior: UIViewController? {
        coveredPresenter == nil ? super.childForPreferredVerticalBarBehavior : nil
    }

    @available(iOS 27.1, tvOS 27.1, visionOS 27.1, *)
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        coveredPreferenceOwner(\.childForPreferredVerticalBarBehavior)?.preferredVerticalBarBehavior
            ?? super.preferredVerticalBarBehavior
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNeedsUpdateOfSupportedInterfaceOrientations()
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        if #available(iOS 27.1, tvOS 27.1, visionOS 27.1, *) {
            setNeedsUpdateOfVerticalBarConfiguration()
        }
    }

    // Work around swiftlang/swift#90385.
    @_optimize(none)
    deinit {}

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        notifyPresentationDismissIfNeeded(onDismiss)
    }
}
#endif
