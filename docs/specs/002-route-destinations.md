# Route destinations and context

Status: Implemented on `zaquia/predefined-route-maps`; validation is recorded in specification 4.

The destination API passes route data and presentation context directly to view building. A destination should be able to use its scope's unwind action, inspect how it was presented, and read environment values without introducing a view solely to capture those values.

Domain modules own `Route` types without depending on feature views. Features define typed `RouteDestination` values, and maps bind those values to presentation declarations. The new design replaces the current `Route` and `RouteViewProviding` destination paths. It requires neither extensions of domain routes nor retroactive destination-provider conformances.

This specification records the destination binding and context surface. Its examples use the implemented API.

## Domain routes

`Route` remains a domain-facing contract for navigation requests and their data. It has no view-building requirement, no `Destination: View` associated type, and no fallback destination. This specification does not redesign route identity or resolution.

```swift
// Domain module
public struct EditProfileRoute: Route {
    public let userID: UUID

    public init(userID: UUID) {
        self.userID = userID
    }
}
```

The feature module binds this type to a view without extending the route or adding a provider conformance.

## Typed destination builders

`RouteDestination` is a value initialized with a route type and a view builder. Its builder receives the typed route instance and a `RouteContext` for the particular scope being rendered:

```swift
// Feature module
let editProfile = RouteDestination(EditProfileRoute.self) { route, context in
    EditProfileView(
        userID: route.userID,
        dismissalStyle: context.presentation.style == .push ? .back : .close,
        onDismiss: { await context.unwindRoute() }
    )
}
```

`EditProfileView` and its parameters are illustrative application APIs. The example passes presentation information and an action directly into the destination; it does not require an intermediate environment-reading view.

The destination value carries the route type as part of its generic contract. No explicit cast, retroactive conformance, or competing protocol witness is needed. Dependencies can be captured when creating the value; builders need not be global or static.

## Map integration

Presentation declarations describe route types and their child navigation. The map's separate `destinations:` closure supplies typed view builders:

```swift
let profileRoutes = RouteMap {
    Push(ProfileRoute.self) {
        Sheet(EditProfileRoute.self) {
            Push(AvatarPickerRoute.self)
        }
    }
} destinations: {
    ProfileFeature.destinations
}

RootRouteMap {
    profileRoutes
} destinations: {
    AvatarFeature.destination
}
```

`RouteDestinations` composes individual `RouteDestination` values and other collections, with optional, conditional, and loop-generated groups. Composition stores builders without evaluating views. Collections retain repeated route types without resolving duplicates themselves.

Map composition contributes to one destination catalog without adding navigation scopes. The catalog includes every branch, destination child, and elevated entry before declarations are bound. Repeated contributions of the same destination value are allowed, including copies and repeated collections. Distinct destination values for one route type report a diagnostic and block that type throughout the tree, regardless of map location or order. The root can supply missing values; there is no override precedence.

The complete root is compiled and bound when the owner is configured, before any destination or branch view mounts. Missing builders report diagnostics. A request matching an unbound declaration leaves navigation unchanged and cannot fall back to another declaration. Registering a builder does not itself declare a route or make nested route definitions discoverable.

`Push`, `Sheet`, `Cover`, and `Replace` no longer accept destination values or inline view builders. Their trailing closures declare children only. The same route type can appear at multiple declaration scopes with different styles and children, using the same destination builder. Separate routing owners can bind it to different values. `ModalRouteMap` also contributes destination values for its restricted modal declarations.

Requests still carry domain route instances. Resolution, equality reuse, and nearest eligible declaration lookup retain their existing behavior. Once presented, a scope retains the selected destination builder and its own routing context.

## Context surface

The context exposes four values:

| Property | Meaning |
| --- | --- |
| `router: Router` | The router bound to the destination's own scope. |
| `unwindRoute: UnwindRouteAction` | An action that unwinds this exact destination scope, including payload delivery. |
| `presentation: RoutePresentation` | The destination's presentation style and priority. |
| `environment: EnvironmentValues` | Environment values visible to the destination at this rendering point. |

`RouteContext` and `RoutePresentation` are the public names. Context construction and destination building run on the main actor, consistent with scope-bound routing actions and view construction. The initial context has no additional phase property.

The context is supplied by Departure. Application code does not construct a context or recover the appropriate scope through a global router lookup.

## Presentation information

Presentation style and priority describe separate facts. `RoutePresentation` has:

- `style`: `.push`, `.replace`, `.sheet`, or cover with its declared transition.
- `priority: RoutePriority`: `.default`, `.high`, or `.critical`, according to the root map builder containing this presentation or its enclosing flow.

A push within a high-priority Login flow reports `.push` style and `.high` priority. It does not report cover style merely because the enclosing flow was presented as a cover. The same route type can receive different presentation information when requested through different map declarations.

This information describes the matched runtime presentation, including after route resolution. It is not inferred solely from the route type or the first declaration of that type in the map.

The destination can use it to choose controls or explicit navigation containers. Departure does not automatically select a back-button design or construct a navigation stack from this metadata.

## Scoped actions

`context.router` and `context.unwindRoute` refer to the destination being built, rather than to its presenter or whichever route is current when an action runs. Their identity remains tied to that scope when passed into destination views or captured by callbacks.

A retained action must not fall back to another active scope after its original scope leaves navigation state. Exact command completion, cancellation, and inactive-scope behavior belongs to the runtime routing specification.

The context should remain consistent with routing values injected into the destination's SwiftUI environment. Passing context explicitly should not create an alternative scope owner.

## Environment access

Environment access should allow destination construction to configure its view directly:

```swift
let profile = RouteDestination(ProfileRoute.self) { route, context in
    ProfileView(userID: route.userID)
        .tint(context.environment.appAccentColor)
}
```

`appAccentColor` represents an illustrative app-defined environment entry. The environment must include values inherited by this destination and its own routing values. It must not expose another scope's router or unwind action simply because construction starts from the presenter's environment.

Environment values are a snapshot for a rendering evaluation. SwiftUI environment changes must participate in destination updates; retaining an old context does not provide a live environment lookup. Observation and builder reevaluation are implementation requirements to validate, rather than an application-level API choice.

## Environment inheritance and forwarding

Local presentations inherit environment values from their presentation host. Top-level high and critical presentations use the router root as their environment source. Children inside those elevated flows inherit locally from their own presentation hosts.

The existing detached-host environment forwarding and customization capability continues. For high and critical root presentations, it forwards from the router root rather than the requesting presentation host. This preserves the ability to carry app-defined environment values into detached hosts without making a root presentation depend on the local scope that requested it.

The destination view and `context.environment` must expose the same effective forwarded values, with routing values bound to the destination's own scope. Existing forwarding/customization remains the mechanism for app-specific values that do not automatically cross a detached host boundary.

## Route phase

Do not add a dedicated `RouteContext.phase` property in the initial API. Route phase remains in SwiftUI's environment and can be read through `context.environment.routePhase` during destination evaluation.

## Navigation containers

As agreed in [Route maps and view bindings](001-route-map-declarations.md), route declarations accept neither `priority:` nor `providesNavigation:`. Context carries presentation information without reinstating automatic stack wrapping.

```swift
let account = RouteDestination(AccountRoute.self) { route, context in
    NavigationStack {
        AccountView(onClose: { await context.unwindRoute() })
            .routing()
    }
}
```

The destination explicitly constructs the stack and applies `.routing()` to its root content inside it. A destination that needs no stack returns its content directly.

## Work for later specifications

Route discoverability remains unchanged. [Route lookup and navigation semantics](003-route-addressing.md) records retained lookup, equality, unwinding, and scope-bound action behavior. The implementation connects those rules to the maps and destination builders. Compatibility with the old destination protocols is not required.
