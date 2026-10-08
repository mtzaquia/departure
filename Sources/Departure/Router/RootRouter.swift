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

/// Owns one routing container and its global transition coordinator.
public struct RootRouter {
    let engine: RouterEngine

    public init() { engine = RouterEngine() }
    init(engine: RouterEngine) { self.engine = engine }

    /// Captures the current scope of the top space for ordinary navigation.
    public var current: Router { Router(engine: engine, scope: engine.currentRouteScope) }

    /// Captures the current scope of the default flow for external entry points.
    ///
    /// Use this handle for deep links and notifications. Presentations, unwinds,
    /// and action dispatch are rejected while a high or critical space covers it.
    /// The captured router becomes inactive if its exact scope leaves navigation.
    public var `default`: Router { Router(engine: engine, scope: engine.defaultSpace.currentRouteScope) }

    /// Removes the captured elevated space, including a covered space, and awaits native teardown.
    @discardableResult
    public func dismissSpace(_ priority: RoutePriority) async -> Bool {
        guard let space = engine.spaces.space(for: priority) else { return false }
        return await engine.dismissSpace(space)
    }

    /// Removes all elevated spaces present when this operation is accepted.
    @discardableResult
    public func dismissSpaces() async -> Bool {
        await engine.dismissSpaces(engine.spaces.allSpaces.filter { $0.priority != .default })
    }
}
