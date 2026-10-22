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
#if canImport(UIKit)
import UIKit
#endif

@MainActor @Suite struct AutomaticPushHostTests {
    @Test func aNewAutomaticHostHasNoPushSlot() {
        #expect(AutomaticPushHost().placement == .pending)
    }

    #if canImport(UIKit)
    @Test func stackMustBeAnAncestorOfThePhysicalHost() {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        let inside = UIView()
        root.view.addSubview(inside)
        #expect(AutomaticPushHost.hasNavigationAncestor(inside))

        let outside = UIViewController()
        outside.addChild(navigation)
        outside.view.addSubview(navigation.view)
        navigation.didMove(toParent: outside)
        let outerHost = UIView()
        outside.view.addSubview(outerHost)
        #expect(!AutomaticPushHost.hasNavigationAncestor(outerHost))
    }

    @Test func aPushedDestinationInheritsItsNavigationController() {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let pushed = UIViewController()
        navigation.pushViewController(pushed, animated: false)
        let host = UIView()
        pushed.view.addSubview(host)
        #expect(AutomaticPushHost.hasNavigationAncestor(host))
    }
    #endif
}
