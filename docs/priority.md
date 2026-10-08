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

Either additional builder may be omitted independently. Elevated base builders accept `Sheet`, `Cover`, and restricted `ModalRouteMap` compositions; unsupported expressions fail at compile time. Compose ordinary `RouteMap` values inside their nested builders. Child declarations use default local styles within that elevated flow; they inherit its effective priority. Priorities belong to the root builders, so `Push`, `Replace`, `Sheet`, and `Cover` have no priority argument.

Only `RootRouteMap` declares high and critical entries. A high destination cannot declare or host a critical space inside its child map. It may request a critical entry from the owner's root catalog while high is top; the owner presents that independent critical space. A nested sheet inside high is local navigation within high and keeps the existing high root.

| Priority | Presentation owner |
| --- | --- |
| `.default` | The matching local scope. |
| `.high` | The router root, above default navigation. |
| `.critical` | The router root, above high navigation. |

The entry destination becomes the space root at X0/Y0. Its outer modal presents that space; local modals advance Y within it. Replacement commits a new root before waiting for the outgoing presentation, so it never exposes a temporary lower space.

Only the top space may originate navigation or dispatch actions. Covered scoped routers cannot push, replace, unwind, select a branch, perform an action, or open another priority. Deferred interceptor invocations recheck this authority before running. Lookup and unwind IDs stop at the space root; the owner's elevated entry definitions remain discoverable separately. Detached environment forwarding comes from the owner and does not establish navigation ancestry.

Use `rootRouter.default` for deep links and notifications. It captures a scope in the default flow and rejects commands while covered, so an external entry point cannot navigate behind or dismiss a critical lockscreen. Presentation attempts during an unfinished navigation operation wait and check coverage on resumption; they still drop if the lockscreen remains. `rootRouter.current` captures the top space; use it when acting deliberately in that space. Unrelated application background work remains independent of router command authority.

`router.unwind(to: .root)` resets only its space and retains the entry and outer presentation. `router.dismissSpace()` or the elevated root's `unwindRoute()` removes the whole space. An explicit owner can also remove a covered space:

```swift
@State private var rootRouter = RootRouter()

WithRouter(routes: routes, router: rootRouter) { AppRoot() }

await rootRouter.dismissSpace(.high)
await rootRouter.default.present(ProfileRoute())
// Or remove every elevated space present when the call is accepted:
await rootRouter.dismissSpaces()
```

Dismissing the elevated entry's outer sheet or cover dismantles that entire space, including every branch and descendant. Final teardown of that entry's current managed root also removes the exact space if it remains live. A stale callback from an outgoing root cannot remove its replacement. Retained outgoing views have no routing authority after logical removal.

Pending requests, transactions, and outgoing snapshots share one owner-level pipeline. After removal commits, the surviving top space becomes eligible immediately; its next presentation waits for required native teardown. A matched lower-space unwind handler runs before commit and can buffer that follow-up. A stored router from the removed space remains inactive.

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
