# Unwinding

Use the router to return to a known point in a flow.

```swift
await router.unwind(to: .root)
await router.unwind(to: .topmostAncestor)
await router.unwind(to: .id("settings-flow"))
```

The environment router resolves targets from its captured scope. `.nearestBranch` clears
that scope’s enclosing branch; `.topmostAncestor` dismisses that scope and its descendants.
`.root` resets only the receiving priority space and keeps its root visible. Inactive pushes survive only in branches owned by that retained root; removing a nested container removes all its branches from live navigation. Unwind targets stay within that space. Covered spaces reject ordinary unwinds.

`unwindRoute()` dismisses the captured destination. At an elevated root it removes the entire space; the permanent default root cannot be dismissed. `router.dismissSpace()` removes the receiving top elevated space from any descendant. `RootRouter.dismissSpace(_:)` and `dismissSpaces()` coordinate removal explicitly, including covered spaces, and finish after native teardown.

Name a mapped scope to target it explicitly:

```swift
RootRouteMap(id: "app-root") {
  Sheet(SettingsFeature.destination) {
    RouteMap(id: "settings-flow") {
      Push(SettingsFeature.advancedDestination)
    }
  }
}
```

A map ID names its receiving root, branch root, or destination; it adds no navigation scope. Use distinct IDs to distinguish repeated route types in an ancestry. One scope accepts one explicit ID, including an ID supplied on its containing root or presentation declaration. Conflicting IDs disable the explicit target and report a diagnostic; its destinations remain usable.

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

Native and explicit unwinds enter the matching handler before committing the path change, while the outgoing source is still live. The handler may start asynchronous work; the unwind continues once it suspends and does not wait for that work to finish. A presentation requested by the handler waits for unwind completion and then rechecks its captured source and routing rules. A default-flow presentation proceeds after the higher space is removed; it is dropped if a reset or partial unwind leaves that space covering its source.

Handlers are found from the surviving landing scope toward its space root, then from each surviving lower space's current scope toward its root, nearest priority first. Only the first matching handler receives the notification and payload. Whole-space removal starts directly with lower spaces; a combined removal skips spaces being removed by that operation. Covered scopes can receive this notification without gaining navigation authority.

An outgoing scope stops participating when it leaves navigation, even if its view is retained for dismissal. Distinct hook types compose across `.hooks` modifiers in the same scope; duplicate handlers for one route type disable that handler and report a diagnostic. An ambiguous handler stops lookup, including fallback to lower spaces.

Next: [Branches](branches.md)
