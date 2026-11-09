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

The requesting scope must be live, including when another route covers it. External entry points can use `rootRouter.root.perform(...)`. Consumers decide when their app should dispatch actions.

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

Multiple `.hooks` modifiers in the same scope compose distinct keys. An interceptor's key is its action type; an unwind handler's key includes its route and expected payload type, with a separate payload-free key. Duplicate keys warn and disable only that hook until one declaration remains. A conflicting interceptor consumes the request; it does not run the action without interception.

An outgoing scope's hooks stop participating as soon as the scope leaves navigation, even while its view remains alive for dismissal. Calling a retained invocation after its intercepting scope leaves navigation throws `CancellationError`.

If an invocation asks to reroute, it throws `CancellationError` back to the interceptor. Departure automatically routes using the usual rules, waits for the destination to install, then retries the action once through the new scope's interceptor.

The retry uses the exact destination accepted by that routing request. A rejected request cannot transfer the action to an unrelated foreground route. An admitted reroute into a global destination can retry there.

Next: [Unwinding](unwinding.md)
