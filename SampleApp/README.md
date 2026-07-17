# Departure Sample App

The sample app registers the `departure-sample` URL scheme so every sample `Route` can be created from a URL and requested through `Router.present(_:)`.

Open a link in the booted simulator with:

```sh
xcrun simctl openurl booted 'departure-sample://route/message'
```

Deep links use the routing graph exactly as it currently exists. The app does not unwind, reset tabs, or construct presentation stacks itself. The nearest installed declaration therefore continues to decide the presentation owner and style. Open links whose owner is `Landing` after entering the sample, and open nested links while their owner is presented.

Each concrete route also has a failable `init?(url:)` through `SampleDeepLinkRoute`:

```swift
let url = URL(string: "departure-sample://route/message")!
let route = MessageRoute(url: url)
```

## Deep-link catalogue

| Route | URL | Declaration context / result |
| --- | --- | --- |
| `LandingRoute` | `departure-sample://route/landing` | Start |
| `StartInfoRoute` | `departure-sample://route/start-info` | Start |
| `LoginRoute` | `departure-sample://route/login` | Landing; high-priority cover |
| `LoginReplacementRoute` | `departure-sample://route/login-replacement` | Landing; high-priority replacement cover |
| `LoginDetailRoute` | `departure-sample://route/login-detail` | Login; push |
| `LoginNoticeRoute` | `departure-sample://route/login-notice` | Login; high-priority sheet |
| `ProfileRoute` | `departure-sample://route/profile` | Home branch; reroutes to Login while signed out |
| `AuthenticationSettingsRoute` | `departure-sample://route/authentication-settings` | Settings branch; push |
| `TopLevelSheetRoute` | `departure-sample://route/top-level-sheet` | Nearest installed declaration; normally Landing |
| `TopLevelCoverRoute` | `departure-sample://route/top-level-cover` | Landing; cover |
| `TopLevelReplacementCoverRoute` | `departure-sample://route/top-level-replacement-cover` | Landing; replacement cover |
| `HighPriorityPassthroughSheetRoute` | `departure-sample://route/high-priority-passthrough-sheet` | Landing; high-priority sheet with background interaction |
| `HighPriorityBlockingSheetRoute` | `departure-sample://route/high-priority-blocking-sheet` | Landing; blocking high-priority sheet |
| `PendingPriorityRoute` | `departure-sample://route/pending-priority` | Settings branch; high-priority cover |
| `NavigationBarFadeOcclusionRoute` | `departure-sample://route/navigation-bar-fade-occlusion` | Home branch; fade cover |
| `AppearanceSettingsRoute` | `departure-sample://route/appearance-settings` | Settings branch; push |
| `AlertRoute` | `departure-sample://route/alert` | Landing; high-priority fade cover |
| `CriticalRoute` | `departure-sample://route/critical` | Landing; critical fade cover |
| `CriticalReplacementRoute` | `departure-sample://route/critical-replacement` | Landing; critical replacement cover |
| `MessageRoute` | `departure-sample://route/message` | Home branch; fade cover |
| `DismissProbeRoute` | `departure-sample://route/dismiss-probe` | Home branch; sheet |
| `NestedModalRoute` | `departure-sample://route/nested-modal` | Dismiss Probe; nested sheet |
| `SettingsModalRoute` | `departure-sample://route/settings-modal` | Settings branch; sheet |
| `RerouteChainStartRoute` | `departure-sample://route/reroute-chain-start` | Resolves through Intermediate to Final |
| `RerouteChainIntermediateRoute` | `departure-sample://route/reroute-chain-intermediate` | Resolves to Final |
| `RerouteChainFinalRoute` | `departure-sample://route/reroute-chain-final` | Settings branch; sheet |
| `DroppedRoute` | `departure-sample://route/dropped` | Deliberately drops during route resolution |
| `UndeclaredRoute` | `departure-sample://route/undeclared` | Deliberately has no declaration and no-ops |

## Query parameters

- `departure-sample://route/login?next=profile` sets `LoginRoute.nextRoute`. `next` accepts any catalogue path.
- `departure-sample://route/authentication-settings?local-route=true` starts with its optional local sheet declaration attached. Accepted values are `true`, `false`, `1`, and `0`.
- `departure-sample://route/appearance-settings?value=01234567-89AB-CDEF-0123-456789ABCDEF` supplies the route's optional UUID value.

Invalid schemes, hosts, paths, UUIDs, and Boolean parameter values are ignored.
