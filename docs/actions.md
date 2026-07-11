# Actions

An action represents user intent that should run in the active route scope. It can ask Departure to route first.

```swift
struct SaveDraftAction: Action {
  func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
    guard context.isRunning(in: EditorRoute.self) else {
      throw .reroute(EditorRoute())
    }

    // Save the draft.
  }
}
```

Run it through the router:

```swift
Task {
  await router.perform(SaveDraftAction())
}
```

When an action throws `.reroute(route)`, Departure presents that route and retries the action once.

## Intercept an action

Attach an interceptor to a route scope when it needs to wrap, replace, or observe a matching action.

```swift
.hooks {
  ActionInterceptor(SaveDraftAction.self) { invocation in
    do {
      try await invocation()
    } catch {
      // Show a save error.
    }
  }
}
```

Calling `invocation()` runs the original action. Omitting it consumes the action—for example, after a confirmation prompt is declined. Only the active route scope participates in interception.

If that invocation asks to reroute, it throws `CancellationError` back to the interceptor. Departure automatically routes using the usual rules, then retries the action once in its new scope.

Next: [Unwinding](unwinding.md)
