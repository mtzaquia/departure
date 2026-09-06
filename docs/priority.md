# Priority

Use elevated priority for flows that must appear above normal app navigation, such as authentication or a critical outage.

```swift
.routes {
  Sheet(ProfileRoute.self)
  Cover(LoginRoute.self, priority: .high)
  Cover(SystemOutageRoute.self, priority: .critical)
}
```

| Priority | Use |
| --- | --- |
| `.normal` | Everyday navigation. |
| `.high` | Important flows above normal navigation. |
| `.critical` | Urgent flows above everything else. |

High and critical presentations use their own window. If their destination relies on a custom environment value, forward it with `windowDestination`.

```swift
WithRouter {
  AppRoot()
} windowDestination: { destination, environment in
  destination
    .environment(\.myCustomKey, environment.myCustomKey)
}
```

Elevated flows are for interruption, not ordinary stacking. A high or critical request from normal content replaces an active presentation at that priority; from an equal- or higher-priority context, it continues as local routing. Lower-priority requests outside an active elevated context do not present.

An elevated flow's lifetime follows the scope that declares it. Declare it at the router root when it should survive changes to lower-priority routes. When you unwind away from a declaring scope, its elevated flow is also cleared, including elevated flows declared inside it. For example, removing a normal destination clears a high flow declared there and a critical flow declared inside that high flow. A critical flow declared at the router root remains independent. An explicit `.root` unwind clears all priorities.

Next: [Getting started](getting-started.md)
