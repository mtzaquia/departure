# Unwinding

Use `@UnwindRoute` to read a captured action, or call `router.unwind` to choose a boundary when issuing a command. Both accept `Router.UnwindTarget`:

```swift
@UnwindRoute(.nearestModal) private var unwindModal

// Either call dismisses the nearest sheet or cover, including its pushed screens.
await unwindModal()
await router.unwind(.nearestModal)
```

| Policy | Result |
| --- | --- |
| `.current` | Dismisses the current destination and its descendants. This is the reader's default. |
| `.nearestModal` | Dismisses the nearest sheet or cover and all its descendants, regardless of push depth. Includes the current destination. |
| `.root` | Resets the receiving priority space and retains its root and outer presentation. |

Lookup starts at the captured source scope and stays within its priority space. Covered spaces reject ordinary unwinds. A reset removes every branch owned by a removed container; inactive pushes survive only in branches owned by the retained space root.

A default local action at an elevated root removes that entire space; the permanent default root cannot be dismissed. `router.dismissSpace()` removes the receiving top elevated space from any descendant. `RootRouter.dismissSpace(_:)` and `dismissSpaces()` coordinate removal explicitly, including covered spaces, and finish after native teardown.

`unwind` returns whether the request was accepted and finishes after native teardown. Await it before continuing a flow. If the unwind removes the requesting destination, obtain a fresh router from the owning `RootRouter` for the next presentation:

```swift
if await router.unwind(from: SettingsRoute.self) {
  await rootRouter.current.present(LoginRoute())
}
```

## Dismiss from a route

`@UnwindRoute` reads a local dismissal action. `RouteContext.unwindRoute` supplies the same `UnwindRouteAction` in destination builders. Actions stay tied to the exact scope where they were read, making them suitable for child views and callbacks.

```swift
struct EditorView: View {
  @UnwindRoute private var unwindRoute

  var body: some View {
    Button("Done") {
      Task { await unwindRoute() }
    }
  }
}
```

## Dismiss an enclosing flow

Supply a route type to read the nearest matching destination in the current scope's logical ancestry:

```swift
struct CheckoutConfirmationView: View {
  @UnwindRoute(CheckoutRoute.self) private var unwindCheckout

  var body: some View {
    Button("Done") {
      Task { await unwindCheckout() }
    }
  }
}
```

Use the same route type with the router's `from:` overload:

```swift
await router.unwind(from: CheckoutRoute.self)
await router.unwind(from: CheckoutRoute.self, payload: CheckoutResult.completed)
```

The action dismisses the matched `CheckoutRoute` and all its descendants. No publication modifier or custom environment key is needed. Lookup includes the current destination, crosses push and ordinary modal boundaries within its priority space, and never searches sibling branches or other priority spaces. If the route type appears more than once, the nearest occurrence wins.

Each read captures the resolved boundary. Newly pushed descendants are included when the action runs. A stored action never searches again or switches to a replacement route instance. Dismissal actions remain usable while that destination is live, even after the child that read them has popped. The `.root` policy also captures its requesting scope for authority and handler delivery; both the requester and root must remain live.

A missing match returns `false` and emits a warning when invoked, including in Release builds and when debug logging is disabled. A removed capture returns `false`. Neither case falls back to dismissing another destination.

The existing covered-space restrictions apply when an action is invoked. Lookup can capture a live covered ancestor, but that action cannot unwind until its space is eligible again. Typed payload delivery and native teardown completion are identical for local and ancestor actions.

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

Handlers report explicit unwind or dismissal requests, including native Back and explicit whole-space removal. Presenting a route does not notify handlers, even when finding its declaration, reusing an equal destination, or replacing a presentation removes existing destinations.

Native and explicit unwinds enter the matching handler before committing the path change, while the outgoing source is still live. The handler may start asynchronous work; the unwind continues once it suspends and does not wait for that work to finish. A presentation requested by the handler waits for unwind completion and then rechecks its captured source and routing rules. A default-flow presentation proceeds after the higher space is removed; it is dropped if a reset or partial unwind leaves that space covering its source.

Handlers are found from the surviving landing scope toward its space root, then from each surviving lower space's current scope toward its root, nearest priority first. Only the first matching handler receives the notification and payload. Whole-space removal starts directly with lower spaces; a combined removal skips spaces being removed by that operation. Covered scopes can receive this notification without gaining navigation authority.

An outgoing scope stops participating when it leaves navigation, even if its view is retained for dismissal. Multiple `.hooks` modifiers compose handlers keyed by route and expected payload type. A `String` handler and an `Int` handler for the same route coexist; duplicating the `String` key warns and disables only that key until one declaration remains. A conflicting applicable key stops lookup, including fallback to ancestors and lower spaces. A different payload key does not shadow a matching ancestor handler.

For a provided payload, a handler for its exact type takes precedence in the receiving scope. Otherwise, one compatible typed handler may receive it through the same cast used by the typed builder. Multiple compatible types without an exact match warn and stop lookup instead of selecting by installation order.

`UnwindHandler(Route.self) { ... }` handles only payload-free requests, including native dismissal. It does not run for a provided payload, even when no typed handler matches. An optional `nil` passed through `unwind(payload:)` remains a typed optional payload; use the payload-free overload to request a payload-free unwind.

Next: [Branches](branches.md)
