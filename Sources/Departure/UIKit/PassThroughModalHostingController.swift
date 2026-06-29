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
    private weak var hostedView: UIView?

    override init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = [.preferredContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        super.loadView()

        guard let hostedView = view else {
            assertionFailure("UIHostingController did not install a root view.")
            view = PassThroughRootView()
            return
        }

        hostedView.backgroundColor = .clear
        hostedView.isOpaque = false
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let passThroughRootView = PassThroughRootView()
        passThroughRootView.backgroundColor = .clear
        passThroughRootView.isOpaque = false
        passThroughRootView.addSubview(hostedView)

        self.hostedView = hostedView
        view = passThroughRootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        view.isOpaque = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let bounds = view.bounds
        let fittingSize = sizeThatFits(in: bounds.size)
        let contentSize = CGSize(
            width: min(max(fittingSize.width, 1), bounds.width),
            height: min(max(fittingSize.height, 1), bounds.height)
        )

        hostedView?.frame = CGRect(
            x: bounds.midX - contentSize.width / 2,
            y: bounds.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        ).integral
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        notifyPresentationDismissIfNeeded(onDismiss)
    }
}

private final class PassThroughRootView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)

        if view === self {
            return nil
        }

        return view
    }
}
#endif
