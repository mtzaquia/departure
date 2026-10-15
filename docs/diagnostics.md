# Diagnostics

Set `Departure.debug` before the router host appears to choose diagnostic detail in a Debug build:

```swift
Departure.debug = .trace

WithRouter(routes: AppRoutes.root) {
  AppView()
}
```

| Level | Optional output |
| --- | --- |
| `.off` | No engine diagnostic events; this is the default. |
| `.normal` | Requests, routing decisions, outcomes, and resulting paths. |
| `.trace` | Normal events plus the adopted map tree, destination bindings, lookup strategy, lifecycle, and waiting details. |

## Inspect the adopted map

At `.trace`, `WithRouter` emits one tree when its adopted root first appears. Rebuilding or remounting the same routing owner does not repeat it. Enable trace before startup; temporary host values that never appear do not emit a tree.

```text
[map] ✓ adopted routing map owner=12345678
root
├─ default
│  └─ branches (concurrent)
│     ├─ branch #1 (AppTab)
│     │  └─ push ProfileRoute → destination #1
│     └─ branch #2 (AppTab)
│        └─ sheet ProfileRoute → destination #1
└─ high
   └─ cover.slide LoginRoute → destination #2
```

The complete tree is printed as one standard-output block, preserving its indentation. Unified logging truncates large interpolated strings by encoded size, so the tree uses standard output rather than multiple log records. It remains limited to `.trace` in Debug builds and is emitted once per routing owner.

Destination numbers identify the resolved builder values within this tree, in first-declaration order. Copies and repeated contributions of the same value retain the same number. They identify builders, not the views those builders eventually produce; rendering the trace does not evaluate a destination.

The tree includes all defined branches and destination children, including those that have not mounted. It marks missing destinations, destination conflicts, duplicate declarations, duplicate branch values, and conflicting branch containers. A builder match does not make an unpresented child's declaration immediately navigable; ordinary route lookup still determines eligibility.

## Debug a push that does not appear

At `.normal` and `.trace`, an `appended ... to path` event confirms the routing state changed. Its `style`, `owner`, and `host` fields identify the presentation style, owning route type (or `root`/`branch` scope), and selected automatic or explicit routing host. A missing host is reported as `host=missing`. The event does not confirm that the destination mounted; the existing `scope installed in view` event provides that confirmation at `.trace`.

When a push uses an automatic host on a modal destination, the append event also includes a hint:

```text
[route][r:12345678] ✓ appended DetailRoute#42 to path | style=push owner=SettingsRoute host=automatic
  path: SettingsRoute#settings › DetailRoute#42
  hint: SettingsRoute has no explicit routing host. If its RouteDestination creates a NavigationStack, add `.routing()` to the root content inside that stack.
```

For a stack created inside the destination builder, attach `.routing()` to its root content:

```swift
RouteDestination(SettingsRoute.self) { _, _ in
  NavigationStack {
    SettingsView().routing()
  }
}
```

The hint describes the registered host and suggests a placement to check; it does not infer the contents of the destination builder. An explicit host suppresses the hint.

Invoking `@UnwindRoute` or `router.unwind` with a missing route type or modal emits a warning identifying the requested boundary, including in Release builds and with `Departure.debug = .off`. The request returns `false` and does not dismiss a different destination.

## Logging and privacy

Engine events use unified logging with subsystem `eu.lelfe.departure` and category `Departure`; the adoption tree is the standard-output exception described above. The bracketed domain, such as `[map]` or `[route]`, distinguishes event kinds. Route, action, and unwind operations retain their existing task-local correlation IDs; the adoption event identifies its routing owner.

The adoption tree prints presentation metadata, route type names, and branch type names with ordinals. It omits branch values, explicit map IDs, route instances, payloads, captured dependencies, and destination view contents. Existing navigation events use compact application-supplied route and path identifiers.

Optional diagnostics and the adoption-tree formatter are compiled out of Release builds. Invalid configuration warnings remain available independently of `Departure.debug`.

Next: [Routing](routing.md)
