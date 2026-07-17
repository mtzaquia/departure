# 🛫 Departure

`Departure` is a robust, expressive routing framework for SwiftUI.

Declare the destinations a screen owns. Request them from wherever the user’s intent starts. Departure finds the closest eligible owner, presents with the right style, and gives actions a route-aware place to run.

- Push, sheet, and cover routes from one small API.
- Preserve navigation state across tabs and other selection-based containers.
- Reroute guarded flows, unwind precisely, and intercept route-scoped actions.
- Raise a critical flow above the app when it truly cannot wait.

```swift
await router.present(SettingsRoute())
```

## Install

Departure supports iOS 17+ and macOS 14+ and is available through Swift Package Manager.

```swift
dependencies: [
  .package(url: "https://github.com/mtzaquia/departure.git", from: "2.0.0"),
],
```

## Five-minute start

Install `WithRouter`, make a route, declare how `HomeView` presents it, then request it.

```swift
@main
struct ExampleApp: App {
  var body: some Scene {
    WindowGroup {
      WithRouter {
        NavigationStack {
          HomeView()
        }
      }
    }
  }
}

struct SettingsRoute: Route {
  func destination() -> some View {
    SettingsView()
  }
}

struct SettingsView: View {
  var body: some View { Text("Settings") }
}

struct HomeView: View {
  @Environment(Router.self) private var router

  var body: some View {
    Button("Settings") {
      Task { await router.present(SettingsRoute()) }
    }
    .routes {
      Sheet(SettingsRoute.self)
    }
  }
}
```

That’s the core idea: the screen that owns the presentation declares it; the screen that starts the flow simply asks for the route.

> [!NOTE]
> Declare `Push(...)` inside a `NavigationStack`.

## Documentation

- [Getting started](docs/getting-started.md) — setup, routes, and declarations.
- [Routing](docs/routing.md) — presentation styles, ownership, and guarded routes.
- [Actions](docs/actions.md) — route-aware work and interception.
- [Unwinding](docs/unwinding.md) — dismissing flows and returning values.
- [Branches](docs/branches.md) — routing in tabs and other selection containers.
- [Priority](docs/priority.md) — high- and critical-priority presentations.

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
