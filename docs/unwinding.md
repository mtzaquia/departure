# Unwinding

Use the router to return to a known point in a flow.

```swift
await router.unwind(to: .root)
await router.unwind(to: .previous)
await router.unwind(to: .id("settings-flow"))
```

Tag a scope to make it a stable target.

```swift
SettingsFlowView()
  .routes(id: "settings-flow") {
    Push(AdvancedSettingsRoute.self)
  }
```

`unwind(to:)` returns whether it found a target. Await it before continuing a flow.

```swift
if await router.unwind(to: .id("settings-flow")) {
  await router.present(LoginRoute())
}
```

## Dismiss from a route

`unwindRoute` is the local dismissal action. It stays tied to the scope where it was read, making it ideal for child views and callbacks.

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

Next: [Branches](branches.md)
