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

Destination numbers identify the resolved builder values within this tree, in first-declaration order. Copies and repeated contributions of the same value retain the same number. They identify builders, not the views those builders eventually produce; rendering the trace does not evaluate a destination.

The tree includes all defined branches and destination children, including those that have not mounted. It marks missing destinations, destination conflicts, duplicate declarations, duplicate branch values, and conflicting branch containers. A builder match does not make an unpresented child's declaration immediately navigable; ordinary route lookup still determines eligibility.

## Logging and privacy

Events use unified logging with subsystem `eu.lelfe.departure` and category `Departure`. The bracketed domain, such as `[map]` or `[route]`, distinguishes event kinds. Route, action, and unwind operations retain their existing task-local correlation IDs; the adoption event identifies its routing owner.

The adoption tree prints presentation metadata, route type names, and branch type names with ordinals. It omits branch values, explicit map IDs, route instances, payloads, captured dependencies, and destination view contents. Existing navigation events use compact application-supplied route and path identifiers.

Optional diagnostics and the adoption-tree formatter are compiled out of Release builds. Invalid configuration warnings remain available independently of `Departure.debug`.

Next: [Routing](routing.md)
