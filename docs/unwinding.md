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

Lookup starts at the captured source and follows its navigation ancestry.

A global route uses ordinary captured dismissal. A captured ancestor action can remove the global and its descendants. The permanent application root cannot be dismissed.

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

The action dismisses the matched `CheckoutRoute` and all its descendants. No publication modifier or custom environment key is needed. Lookup includes the current destination, crosses push and modal boundaries, and never searches sibling branches. If the route type appears more than once, the nearest occurrence wins.

Each read captures the resolved boundary. Newly pushed descendants are included when the action runs. A stored action never searches again or switches to a replacement route instance. Dismissal actions remain usable while that destination is live, even after the child that read them has popped.

A missing match returns `false` and emits a warning when invoked, including in Release builds and when debug logging is disabled. A removed capture returns `false`. Neither case falls back to dismissing another destination.

Consumers control whether to request dismissal and whether gestures are enabled in their destination views. Departure applies ordinary ancestor removal and reconciles native dismissal events. Typed payload delivery and native teardown completion are identical for local and ancestor actions.

## Reset navigation to the application root

Use a reset to clear navigation while retaining the application root:

```swift
await router.resetToRoot()
await router.resetToRoot(payload: SaveResult.saved)
```

A reset includes global presentations. Reset is a router command; it is not an `@UnwindRoute` policy.

The captured source must be live. Empty navigation and removed sources return `false`. Accepted resets use the requesting source route for unwind-handler matching and finish after native teardown.

Reset removes every branch owned by a removed container. Inactive pushes survive only in branches owned by the retained application root.

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

Handlers report explicit unwind or dismissal requests, including native Back. Presenting a route does not notify handlers, even when finding its declaration, reusing an equal destination, or replacing a presentation removes existing destinations.

Native and explicit unwinds enter the matching handler before committing the path change, while the outgoing source is still live. The handler may start asynchronous work; the unwind continues once it suspends and does not wait for that work to finish. A presentation requested by the handler waits for unwind completion and then rechecks its captured source and routing rules. A follow-up presentation proceeds only if the resulting phase and protection rules permit it.

Handlers are found from the surviving landing scope toward the application root. Only the first matching handler receives the notification and payload. A surviving inactive scope may receive notification; a follow-up request still checks protection.

An outgoing scope stops participating when it leaves navigation, even if its view is retained for dismissal. Multiple `.hooks` modifiers compose handlers keyed by route and expected payload type. A `String` handler and an `Int` handler for the same route coexist; duplicating the `String` key warns and disables only that key until one declaration remains. A conflicting applicable key stops lookup, including fallback to ancestors. A different payload key does not shadow a matching ancestor handler.

For a provided payload, a handler for its exact type takes precedence in the receiving scope. Otherwise, one compatible typed handler may receive it through the same cast used by the typed builder. Multiple compatible types without an exact match warn and stop lookup instead of selecting by installation order.

`UnwindHandler(Route.self) { ... }` handles only payload-free requests, including native dismissal. It does not run for a provided payload, even when no typed handler matches. An optional `nil` passed through `unwind(payload:)` remains a typed optional payload; use the payload-free overload to request a payload-free unwind.

Next: [Branches](branches.md)
