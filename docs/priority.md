# Priority

High and critical presentations are declared at the routing root. They appear above default app navigation and retain independent navigation state.

```swift
let routes = RootRouteMap {
  Sheet(ProfileFeature.destination)
} highPriority: {
  Cover(LoginFeature.destination) {
    Push(LoginFeature.challengeDestination)
  }
} criticalPriority: {
  Cover(SystemOutageFeature.destination, transition: .fade)
}
```

Either additional builder may be omitted independently. Elevated base builders accept only `Sheet` and `Cover`; unsupported expressions fail at compile time. Compose `RouteMap` values inside their nested builders. Child declarations use default local styles within that elevated flow; they inherit its effective priority. Priorities belong to the root builders, so `Push`, `Replace`, `Sheet`, and `Cover` have no priority argument.

| Priority | Presentation owner |
| --- | --- |
| `.default` | The matching local scope. |
| `.high` | The router root, above default navigation. |
| `.critical` | The router root, above high navigation. |

The entry destination becomes the space root at X0/Y0. Its outer modal presents that space; local modals advance Y within it. Replacement commits a new root before waiting for the outgoing presentation, so it never exposes a temporary lower space.

Only the top space may originate navigation or dispatch actions. Covered scoped routers cannot push, replace, unwind, select a branch, perform an action, or open another priority. Deferred interceptor invocations recheck this authority before running. Lookup and unwind IDs stop at the space root; the owner's elevated entry definitions remain discoverable separately. Detached environment forwarding comes from the owner and does not establish navigation ancestry.

Use `rootRouter.default` for deep links and notifications. It captures a scope in the default flow and rejects commands while covered, so an external entry point cannot navigate behind or dismiss a critical lockscreen. `rootRouter.current` captures the top space; use it when acting deliberately in that space. Unrelated application background work remains independent of router command authority.

`router.unwind(to: .root)` resets only its space and retains the entry and outer presentation. `router.dismissSpace()` or the elevated root's `unwindRoute()` removes the whole space. An explicit owner can also remove a covered space:

```swift
@State private var rootRouter = RootRouter()

WithRouter(routes: routes, router: rootRouter) { AppRoot() }

await rootRouter.dismissSpace(.high)
await rootRouter.default.present(ProfileRoute())
// Or remove every elevated space present when the call is accepted:
await rootRouter.dismissSpaces()
```

Pending requests, transactions, and outgoing snapshots share one owner-level pipeline. After removal commits, the surviving top space becomes eligible immediately; its next presentation waits for required native teardown. A stored router from the removed space remains inactive.

## Forward detached environment values

High and critical presentations use detached hosts, as do fade covers. Forward custom values with `windowDestination`:

```swift
WithRouter(routes: routes) {
  AppRoot()
} windowDestination: { destination, environment in
  destination.environment(\.myCustomKey, environment.myCustomKey)
}
```

High and critical forwarding comes from the router root. Default fade-cover forwarding comes from its local presentation host. The destination context receives the same effective environment as its view.

Next: [Getting started](getting-started.md)
