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

enum AppTab: Hashable, Sendable {
    case home
    case wallet
}

struct RootRoute: Route, Equatable {
    func destination() -> some View {
        Text("Root")
    }
}

struct HomeDetailRoute: Route, Equatable {
    func destination() -> some View {
        Text("Home Detail")
    }
}

struct NumberedRoute: Route, Equatable {
    let number: Int

    func destination() -> some View {
        Text("Number \(number)")
    }
}

struct TransactionRoute: Route, Equatable {
    func destination() -> some View {
        Text("Transaction")
    }
}

struct SettingsRoute: Route, Equatable {
    func destination() -> some View {
        Text("Settings")
    }
}

struct LoginRoute: Route, Equatable {
    func destination() -> some View {
        Text("Login")
    }
}

struct AlertRoute: Route, Equatable {
    func destination() -> some View {
        Text("Alert")
    }
}

struct MessageRoute: Route, Equatable {
    func destination() -> some View {
        Text("Message")
    }
}

struct DroppedRoute: Route, Equatable {
    func resolveRoute() async -> RouteResolution {
        .drop
    }

    func destination() -> some View {
        Text("Dropped")
    }
}

struct ReroutingRoute: Route, Equatable {
    func resolveRoute() async -> RouteResolution {
        .reroute(LoginRoute())
    }

    func destination() -> some View {
        Text("Rerouting")
    }
}

struct ContextProbeAction: Action {
    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) -> Bool {
        context.isRunning(in: RootRoute.self)
    }
}

@MainActor
final class ActionRecorder {
    var bools: [Bool] = []
    var labels: [String] = []
}

actor AsyncActionRecorder {
    private var bools: [Bool] = []

    func append(_ value: Bool) {
        bools.append(value)
    }

    func values() -> [Bool] {
        bools
    }
}

struct RecordingProbeAction: Action {
    let recorder: AsyncActionRecorder

    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        await recorder.append(context.isRunning(in: RootRoute.self))
    }
}

@MainActor
func tabSelection(_ value: AppTab) -> (Binding<AppTab>, @MainActor () -> AppTab) {
    final class Storage {
        var value: AppTab

        init(_ value: AppTab) {
            self.value = value
        }
    }

    let storage = Storage(value)
    let binding = Binding<AppTab>(
        get: { storage.value },
        set: { storage.value = $0 }
    )

    return (binding, { storage.value })
}

extension AnyRouteDeclaration {
    @MainActor
    var routeTypeID: ObjectIdentifier {
        ObjectIdentifier(routeType)
    }
}
