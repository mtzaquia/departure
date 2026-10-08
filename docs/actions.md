# Actions

An action represents user intent that should run in the scope captured by the receiving router. It can ask Departure to route first.

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

Calling `invocation()` runs the original action. Omitting it consumes the action—for example, after a confirmation prompt is declined. Only the scope captured by the receiving router participates in interception.

Multiple `.hooks` modifiers in the same scope compose distinct action and route types. Duplicate declarations for one type disable that hook and report a diagnostic until only one declaration remains. A conflicting interceptor consumes the request; it does not run the action without interception.

An outgoing scope's hooks stop participating as soon as the scope leaves navigation, even while its view remains alive for dismissal. Calling a retained invocation after its intercepting scope leaves navigation throws `CancellationError`.

If an invocation asks to reroute, it throws `CancellationError` back to the interceptor. Departure automatically routes using the usual rules, waits for the destination to install, then retries the action once through the new scope's interceptor.

Next: [Unwinding](unwinding.md)
