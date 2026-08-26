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

/// A destination view supplied separately from a route's primary conformance.
///
/// Departure prefers this destination over ``Route/destination()`` when a route conforms to both
/// protocols. This lets a domain module declare a route while a feature module supplies its view.
///
/// ```swift
/// // Domain module
/// public struct SettingsRoute: Route {}
///
/// // Feature module
/// extension SettingsRoute: RouteViewProviding {
///     public func destination() -> some View {
///         SettingsView()
///     }
/// }
/// ```
///
/// A conformance can be declared only once for a route type. Add `@retroactive` only when the route
/// belongs to another package; modules in the same package do not need it.
public protocol RouteViewProviding {
    /// The view supplied for the route.
    associatedtype ProvidedView: View

    /// Builds the route's preferred destination.
    @ViewBuilder func destination() -> ProvidedView
}
