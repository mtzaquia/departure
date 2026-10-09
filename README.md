# 🛫 Departure

[![Tests](https://github.com/mtzaquia/departure/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/mtzaquia/departure/actions/workflows/tests.yml)
[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://www.swift.org/)
[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue.svg)](https://github.com/mtzaquia/departure/blob/main/Package.swift)
![Class A](https://img.shields.io/badge/class-A-gold)

<a href="https://www.buymeacoffee.com/mtzaquia" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" style="height: 30px !important;" ></a>

`Departure` is a SwiftUI routing framework with composable route maps and scoped navigation.

Declare the navigation tree once. Feature modules supply typed destination builders; views bind their place in the tree. Departure finds the nearest eligible declaration, coordinates branches and modal lanes, and unwinds through one shared plan.

- Push, replace, sheet, and cover destinations.
- Keep domain routes independent of feature views.
- Preserve independent paths in tabs and concurrent split columns.
- Resolve guarded routes, intercept actions, and return unwind payloads.
- Declare high and critical presentations at the root.

```swift
let routes = RootRouteMap {
  Sheet(SettingsFeature.destination) {
    Push(SettingsFeature.advancedDestination)
  }
}
```

## Install

Departure requires Swift 6.3+, iOS 17+, or macOS 14+. The map API described here is available in the `v3.0.0-beta.1` prerelease.

```swift
dependencies: [
  .package(url: "https://github.com/mtzaquia/departure.git", exact: "3.0.0-beta.1"),
]
```

## Five-minute start

Create route data and its destination, then pass the map to `WithRouter`.

```swift
import Departure
import SwiftUI

struct SettingsRoute: Route, Equatable {}

@MainActor
enum SettingsFeature {
  static let destination = RouteDestination(SettingsRoute.self) { _, context in
    Button("Done") {
      Task { await context.unwindRoute() }
    }
  }
}

@main
struct ExampleApp: App {
  private let routes = RootRouteMap {
    Sheet(SettingsFeature.destination)
  }

  var body: some Scene {
    WindowGroup {
      WithRouter(routes: routes) { HomeView() }
    }
  }
}

struct HomeView: View {
  @Environment(\.router) private var router

  var body: some View {
    Button("Settings") {
      Task { await router.present(SettingsRoute()) }
    }
  }
}
```

The map owns definitions independently of mounted views. `WithRouter` and destinations bind their scopes automatically. When a scope declares pushes, explicitly supply `NavigationStack { content.routing() }`, placing `.routing()` on the root content inside the stack. Destinations choose their containers explicitly.

## Documentation

- [Getting started](docs/getting-started.md) — maps, destinations, and view bindings.
- [Routing](docs/routing.md) — lookup, presentation styles, context, and guarded routes.
- [Actions](docs/actions.md) — route-aware work and interception.
- [Unwinding](docs/unwinding.md) — dismissing flows and returning values.
- [Branches](docs/branches.md) — tabs, concurrent columns, and replacement selections.
- [Priority](docs/priority.md) — high and critical root presentations.
- [Rewrite specifications](docs/specs/README.md) — agreed contracts and implementation inventory.

## Sample app

Open `SampleApp/SampleApp.xcodeproj`. The app exercises tabs, concurrent split columns, replacements, actions, payloads, elevated windows, and nested-modal unwind snapshots.

## License

Copyright (c) 2026 @mtzaquia

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
