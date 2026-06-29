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

#if canImport(UIKit)
import UIKit

final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)

        guard let rootView = rootViewController?.view else {
            return view
        }

        if let rootViewController,
           rootViewController.presentedViewController != nil,
           let view {
            if rootViewController.topPresentedControllerAllowsChromePassthrough,
               rootViewController.presentedViewControllers.contains(where: { presentedViewController in
                   guard let presentedView = presentedViewController.view else {
                       return false
                   }

                   return view === presentedView || view.isDescendant(of: presentedView)
               }) == false {
                return nil
            }

            if view === rootView || view.isDescendant(of: rootView) {
                return nil
            }

            return view
        }

        if let view, view === rootView || view.isDescendant(of: rootView) {
            return nil
        }

        return view
    }
}

private extension UIViewController {
    var presentedViewControllers: [UIViewController] {
        var viewControllers: [UIViewController] = []
        var current = presentedViewController

        while let viewController = current {
            viewControllers.append(viewController)
            current = viewController.presentedViewController
        }

        return viewControllers
    }

    var topPresentedControllerAllowsChromePassthrough: Bool {
        presentedViewControllers.last is AnyPassThroughModalHostingController
    }
}
#endif
