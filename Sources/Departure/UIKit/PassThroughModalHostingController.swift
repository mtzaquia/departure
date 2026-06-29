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

final class PassThroughModalHostingController<Content: View>: UIHostingController<Content> {
    var onDismiss: (@MainActor () -> Void)?
    private let modalTransitioningDelegate = PassThroughModalTransitioningDelegate()

    override init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = [.preferredContentSize]
        modalPresentationStyle = .custom
        transitioningDelegate = modalTransitioningDelegate
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.isOpaque = false
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        notifyPresentationDismissIfNeeded(onDismiss)
    }
}

private final class PassThroughModalTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        PassThroughModalPresentationController(
            presentedViewController: presented,
            presenting: presenting
        )
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        CrossDissolveTransitionAnimator(isPresenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        CrossDissolveTransitionAnimator(isPresenting: false)
    }
}

private final class PassThroughModalPresentationController: UIPresentationController {
    override var shouldRemovePresentersView: Bool {
        false
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else {
            return .zero
        }

        let bounds = containerView.bounds
        let fittingSize: CGSize

        if let hostingController = presentedViewController as? any HostingControllerSizing {
            fittingSize = hostingController.sizeThatFits(in: bounds.size)
        } else {
            fittingSize = presentedViewController.view.systemLayoutSizeFitting(
                bounds.size,
                withHorizontalFittingPriority: .defaultLow,
                verticalFittingPriority: .defaultLow
            )
        }

        let contentSize = CGSize(
            width: min(max(fittingSize.width, 1), bounds.width),
            height: min(max(fittingSize.height, 1), bounds.height)
        )

        return CGRect(
            x: bounds.midX - contentSize.width / 2,
            y: bounds.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        ).integral
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()

        presentedView?.frame = frameOfPresentedViewInContainerView
    }
}

private protocol HostingControllerSizing {
    func sizeThatFits(in size: CGSize) -> CGSize
}

extension UIHostingController: HostingControllerSizing {}

private final class CrossDissolveTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isPresenting: Bool

    init(isPresenting: Bool) {
        self.isPresenting = isPresenting
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.25
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        if isPresenting {
            animatePresentation(using: transitionContext)
        } else {
            animateDismissal(using: transitionContext)
        }
    }

    private func animatePresentation(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let presentedView = transitionContext.view(forKey: .to),
            let presentedViewController = transitionContext.viewController(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView
        presentedView.frame = transitionContext.finalFrame(for: presentedViewController)
        presentedView.alpha = 0
        containerView.addSubview(presentedView)

        UIView.animate(withDuration: transitionDuration(using: transitionContext)) {
            presentedView.alpha = 1
        } completion: { finished in
            transitionContext.completeTransition(finished && transitionContext.transitionWasCancelled == false)
        }
    }

    private func animateDismissal(using transitionContext: UIViewControllerContextTransitioning) {
        guard let dismissedView = transitionContext.view(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }

        UIView.animate(withDuration: transitionDuration(using: transitionContext)) {
            dismissedView.alpha = 0
        } completion: { finished in
            if transitionContext.transitionWasCancelled == false {
                dismissedView.removeFromSuperview()
            }

            transitionContext.completeTransition(finished && transitionContext.transitionWasCancelled == false)
        }
    }
}
#endif
