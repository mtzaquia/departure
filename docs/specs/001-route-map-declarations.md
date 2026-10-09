# Route maps and view bindings

Status: Implemented on `zaquia/predefined-route-maps`; validation is recorded in specification 4.

Departure knows its route definitions independently of mounted views. Applications declare the navigation structure ahead of time using `RootRouteMap`, and features compose reusable declarations using `RouteMap`. Views connect to that structure without defining which routes exist through their lifecycle.

This specification records the map declaration API and the view bindings that connect it to presentation. The Swift examples use the implemented surface.

Presentation declarations accept typed `RouteDestination` values, as defined in [Route destinations and context](002-route-destinations.md). In the examples below, `Destinations` represents feature-owned destination values; the map infers each value's domain route type.

## Map types

`RootRouteMap` describes the complete navigation definition for one routing container. Its initializer accepts a primary route declaration builder and up to two additional trailing builders, labeled `highPriority` and `criticalPriority`. Both additional builders default to empty.

`RouteMap` describes reusable declarations that can be inserted into a map builder or a route's child builder. Composition contributes those declarations to the receiving scope; it does not introduce a new scope by itself.

`RouteMap(id:)` optionally names that receiving scope for `.unwind(to: .id(...))`. A scope accepts one explicit ID across its root/presentation declaration and composed maps. Unnamed fragments compose freely. Multiple explicit IDs report a diagnostic and disable the explicit target while leaving the route definitions available.

`ModalRouteMap` is the restricted composition type for elevated entries. Its builder accepts sheets, covers, and other modal maps. Ordinary `RouteMap` values belong in the main builder or inside an entry modal.

Only `RootRouteMap` exposes the priority builders. A `RouteMap` cannot define high- or critical-priority root presentations, and a `RootRouteMap` cannot be embedded as a feature subtree.

## Root declaration

```swift
enum AppRoutes {
    static let root = RootRouteMap {
        Push(Destinations.profile) {
            Sheet(Destinations.editProfile)
        }

        settings
    } highPriority: {
        Cover(Destinations.login) {
            Push(Destinations.resetPassword)
        }

        Sheet(Destinations.maintenance)
    } criticalPriority: {
        Cover(Destinations.sessionExpired)
    }

    static let settings = RouteMap {
        Push(Destinations.appearance)

        Push(Destinations.account) {
            Sheet(Destinations.changePassword)
        }
    }
}
```

The priority builders are optional independently. A root map can supply neither, either one, or both. When both are supplied, `highPriority` precedes `criticalPriority`.

```swift
let ordinaryRoutes = RootRouteMap {
    Push(Destinations.profile)
}

let routesWithHighPriority = RootRouteMap {
    Push(Destinations.profile)
} highPriority: {
    Cover(Destinations.login)
}

let routesWithCriticalPriority = RootRouteMap {
    Push(Destinations.profile)
} criticalPriority: {
    Cover(Destinations.sessionExpired)
}
```

## Nested declarations

Retain the presentation DSL: `Push`, `Sheet`, `Cover`, and `Replace`. Each accepts an optional trailing builder for declarations belonging to its destination scope. A leaf keeps its concise spelling.

Route declarations do not accept `priority:` or `providesNavigation:`. Root map builders determine priority, and destination views explicitly provide any navigation containers they need.

```swift
Push(Destinations.profile)

Push(Destinations.profile) {
    Sheet(Destinations.editProfile) {
        Push(Destinations.avatarPicker)
    }
}
```

Sibling declarations belong to the same scope. A child builder describes navigation available within each presented instance of its parent route; it does not require that child to be presented or create a separate navigation stack by itself.

The same route type may be declared in different scopes with different presentation styles and children. Definitions describe route types and their placement in the map; route instances carry the data for a particular presentation.

Each placement requires a distinct internal declaration identity, even when it reuses a destination or composed map. Route discoverability stays exactly as it is today, including nearest eligible declaration lookup from the originating scope. [Route lookup and navigation semantics](003-route-addressing.md) is a reference for that retained behavior.

## Root presentation priorities

Top-level declarations in `highPriority` and `criticalPriority` describe presentations from the routing container's root, above ordinary navigation. The root map builders determine presentation priority. Individual `Sheet` and `Cover` declarations do not expose a `priority:` parameter.

A root presentation's nested declarations describe local navigation within that presentation. For example, `ResetPasswordRoute` pushes inside the presented Login destination; it does not become a separate root presentation because its definition is nested under `highPriority`.

Only the owner's `RootRouteMap` can declare elevated catalogs. Its type cannot be embedded inside a route's child builder or a feature map. High-space sources can still request root-declared critical entries while eligible; the owner presents an independent space rather than nesting critical ownership inside high. Nested sheets and covers remain local to their existing space.

The exact rules for replacing, dismissing, and resolving competing root presentations belong to the runtime routing specification.

## Router installation

The `routes:` parameter of `WithRouter` accepts only `RootRouteMap`. A reusable `RouteMap` must be composed into a root map before installation.

```swift
WithRouter(routes: AppRoutes.root) {
    AppView()
}
```

Backward compatibility with existing initializers is not required. An optional `router:` argument preserves an explicit routing handle. A `windowDestination:` trailing closure customizes detached presentation content and receives its source environment.

## View bindings

`WithRouter` automatically annotates and wires its root content for the root map. Departure also automatically annotates and wires each presented destination for that route's definition. Ordinary content therefore does not need to repeat a routing modifier solely to establish its scope.

The public view binding surface has three forms:

| Modifier | Responsibility |
| --- | --- |
| `.routing()` | Connect presentation at this view to the current mapped scope. |
| `.routing(AppTab.home)` | Annotate and wire branch content for the matching `Branch` in the current mapped scope. |
| `.routing(branch: $tab)` | Connect presentation at the branch container and its selection binding to the current mapped scope. |

A receiving scope accepts exactly one `Branches` group across its containing and composed maps. `Branch` expressions are accepted only inside that group. Concurrency belongs to the group, rather than individual branches or view bindings. Multiple groups diagnose and disable the branch container while retaining sibling routes.

The container's selected value belongs to the model. A mounted container accepts exactly one external selection owner through `.routing(branch:)`; multiple owners diagnose and disable selection changes until one remains. An unmounted container retains its model selection and mapped discoverability. Selection callbacks belong to the existing routing attachment and leave with that attachment. Branch values must be representable by the binding's selection type; an incompatible activation diagnoses the types and leaves navigation unchanged.

The branch-value form replaces the proposed `.routeBranch` spelling. The binding form applies to the container, while the value form applies to each branch's content. Neither form contributes declarations to the map.

The unqualified modifier uses the current scope; it does not create another one. A branch-value modifier connects to a mapped child branch scope. Repeated wiring for the same scope must not create duplicate route scopes or competing presentation owners. Exact host reconciliation is an implementation concern.

An explicit `.routing()` or `.routing(branch: binding)` takes presentation ownership over automatic wiring at the same scope. Use it inside a custom container to capture environment values applied there. The binding form also synchronizes branch selection, so it needs no additional `.routing()`. This changes physical host placement without adding a logical scope.

Routing is independent of `NavigationStack`. A view can host sheets, covers, or replacement content without providing stack navigation. `.routing()` does not create a stack, and a branch does not imply one either.

## Explicit navigation stacks

For pushes, application code creates a native `NavigationStack` and applies `.routing()` to its root content inside the stack:

```swift
NavigationStack {
    HomeView()
        .routing()
}
```

Automatic root or destination wiring establishes the scope, while `.routing()` inside the stack connects presentation at the appropriate location. It does not create a second scope. Departure provides no navigation-stack wrapper.

Departure never automatically wraps root content or a presented destination in a navigation stack. Automatic routing annotation only connects the view to its mapped scope and presentation machinery. The destination itself decides whether to construct a `NavigationStack` with `.routing()` on its root content, another container, or no navigation container.

For example, a sheet with nested push declarations supplies its stack explicitly in the destination:

```swift
// In the destination builder for EditProfileRoute:
NavigationStack {
    EditProfileView()
        .routing()
}
```

Nested `Push` declarations do not cause Departure to infer or create a stack. Application code supplies both the stack and its root's routing modifier.

## Branched scopes

`Branches` groups the named child scopes of a branch container. Its `BranchDeclarationBuilder` accepts only `Branch` expressions, including conditional and loop-generated branches. Other route declarations are siblings of the group in the enclosing map. Each `Branch` has its own declarations and navigation state within an instance of the owning scope. `RouteMap` composition remains transparent: inserting a reusable map within a branch contributes declarations to that branch rather than creating another scope.

Branches split the X path into independent sub-paths while sharing the Y modal lane. They do not create independent modal presentation capacity. Each lane can own at most one modal, which creates the next lane. The complete X/Y/Z mental model is recorded in [Route lookup and navigation semantics](003-route-addressing.md).

```swift
static let root = RootRouteMap {
    Sheet(Destinations.help)

    Branches {
        Branch(AppTab.home) {
            home
        }

        Branch(AppTab.settings) {
            settings
        }
    }
}
```

Declarations outside `Branches` belong to the containing scope. Declarations inside a `Branch` belong to that branch's child scope. Nested route builders can declare their own `Branches`, allowing branch containers within presented destinations. Branch values are interpreted within their owning mapped scope, so different containers can reuse the same values.

The view connects the container and its content separately:

```swift
WithRouter(routes: AppRoutes.root) {
    TabView(selection: $tab) {
        NavigationStack {
            HomeView()
                .routing()
        }
        .routing(AppTab.home)
        .tag(AppTab.home)

        SettingsView()
            .routing(AppTab.settings)
            .tag(AppTab.settings)
    }
    .routing(branch: $tab)
}
```

The example deliberately gives only Home a navigation stack. Each branch's map must match the presentation capabilities of its view hierarchy; the Settings branch can use modal or replacement navigation without a stack.

Branch definitions are known before their content mounts. The view binding connects a live host to the corresponding logical branch scope; it does not discover or define that scope. Unmounting a host must not remove branch definitions. Runtime state retention and presentation readiness are specified separately.

`Branches(concurrent: true)` declares that its branches participate together, as in a split view. The ordinary form uses exclusive participation, as in a tab container. This setting belongs to the map and stays the same when a split view collapses. The selection binding connects the container's selected or preferred branch; changing it does not redefine the map. Branch discovery and targeting retain their current behavior as recorded in specification 3.

## Definition lifetime

The complete definition is available to the router independently of whether destination views or branch views have mounted. Registering or removing a live view may change which presentation hosts are available; it must not install or remove the route definitions themselves.

Knowing a nested definition does not by itself construct missing ancestor route instances or expand lookup eligibility. Retain current discoverability. Navigation through unpresented ancestors and new deep-link path APIs are outside the current scope.

[Implementation architecture and simplification](004-implementation.md) specifies persistent definitions and accumulated view path contexts. View bindings project state without installing declarations through lifecycle callbacks.

## Related contracts and deferred work

- Specification 3 records branch activation, discoverability, shared modal arbitration, priorities, and unwind behavior.
- Specification 4 records readiness, snapshots, binding ownership, and the implemented simplification.
- Builders support conditionals, optional groups, and arrays. Elevated root builders accept modal declarations and reject top-level branches, pushes, and replacements.
- Additional physical presentation hosts or replacement slots in one mapped scope, runtime map replacement, and recursive definition references remain outside this API.

### Elevated entry builder constraint (2026-10-08)

The base `highPriority` and `criticalPriority` closures use `ModalRouteDeclarationBuilder`: `Sheet`, `Cover`, and restricted `ModalRouteMap` compositions are accepted. `Push`, `Replace`, and branch containers belong inside an entry modal's ordinary nested route builder. The entry modal is the origin and logical root of that priority space. Composable `RouteMap` values remain available inside those nested builders; an ID on such a map names the entry's scope. Unsupported entry expressions fail at compile time.
