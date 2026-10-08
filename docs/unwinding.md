# Unwinding

Use the router to return to a known point in a flow.

```swift
await router.unwind(to: .root)
await router.unwind(to: .topmostAncestor)
await router.unwind(to: .id("settings-flow"))
```

The environment router resolves targets from its captured scope. `.nearestBranch` clears
that scope’s enclosing branch; `.topmostAncestor` dismisses that scope and its descendants.
`.root` resets only the receiving priority space and keeps its root visible. Inactive pushes survive only in branches owned by that retained root; removing a nested container removes all its branches from live navigation. Targets and payload handlers never cross a space boundary. Covered spaces reject ordinary unwinds.

`unwindRoute()` dismisses the captured destination. At an elevated root it removes the entire space; the permanent normal root cannot be dismissed. `router.dismissSpace()` removes the receiving top elevated space from any descendant. `RootRouter.dismissSpace(_:)` and `dismissSpaces()` coordinate removal explicitly, including covered spaces, and finish after native teardown.

Name a mapped scope to target it explicitly:

```swift
RootRouteMap(id: "app-root") {
  Sheet(SettingsFeature.destination, id: "settings-flow") {
    Push(SettingsFeature.advancedDestination)
  }
}
```

`unwind(to:)` returns whether it found a target. Await it before continuing a flow.

```swift
if await router.unwind(to: .id("settings-flow")) {
  await router.present(LoginRoute())
}
```

## Dismiss from a route

`RouteContext.unwindRoute` and the environment `unwindRoute` are local dismissal actions. It stays tied to the scope where it was read, making it ideal for child views and callbacks.

```swift
struct EditorView: View {
  @Environment(\.unwindRoute) private var unwindRoute

  var body: some View {
    Button("Done") {
      Task { await unwindRoute() }
    }
  }
}
```

## Return a value

Pass a payload with an unwind and receive it with a typed handler.

```swift
.hooks {
  UnwindHandler(EditorRoute.self, expecting: SaveResult.self) { result in
    showToast(for: result)
  }
}

await unwindRoute(payload: SaveResult.saved)
```

SwiftUI’s `dismiss()` follows the same payload-free unwind path and triggers a matching handler.

Handlers are found from the surviving landing scope toward its space root. An outgoing scope stops participating when it leaves navigation, even if its view is retained for dismissal. Distinct hook types compose across `.hooks` modifiers in the same scope; duplicate handlers for one route type disable that handler and report a diagnostic. An ambiguous handler does not fall back to an ancestor's handler.

Next: [Branches](branches.md)
