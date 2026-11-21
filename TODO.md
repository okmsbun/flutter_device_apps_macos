# macOS API roadmap

Implement and verify one API at a time in this package and its example.
Keep the static `FlutterDeviceAppsMacos` entry point, `Future` results, optional
named parameters, native method-channel maps, and immutable models.
Use bundle identifiers, app paths, and macOS metadata throughout the API.

## Completed

- [x] Independent macOS plugin with Swift Package Manager and CocoaPods support.
- [x] `MacosAppInfo` with `fromMap`, optional fields, and optional PNG bytes.
- [x] Agent/background declarations and optional architecture, logical size, and Team ID metadata.
- [x] `listApps`: standard directories, system/launchable filters, bundle ID
      prefix and substring filters, path deduplication, optional icons, and `[]` for no matches.
- [x] `getApp`: preferred-copy bundle ID lookup or exact app path, optional metadata,
      and null when the selected app is unavailable or inaccessible.
- [x] `getApps`: ordered batch lookup by bundle ID or app path, deduplicated by resolved path.
- [x] `getAppIcon`: standalone PNG icon lookup by bundle ID or app path.
- [x] `isAppInstalled`: check for an accessible app bundle and document negative lookup results.
- [x] `isSystemApp`: apply the same location heuristic as `MacosAppInfo.isSystem`.
- [x] `isAppLaunchable`: apply the same preflight as `listApps(onlyLaunchable: true)`.
- [x] `openApp`: open the resolved app and report the asynchronous macOS result.
- [x] `revealAppInFinder`: request Finder selection for the resolved app bundle.
- [x] `moveAppToTrash`: move the resolved bundle path to Trash with confirmation in the example.
- [x] `detectAppFrameworks`: report Flutter, Electron, and Qt bundle indicators.
- [x] `getInstallSourceInfo`: report App Store receipt and web-download indicators with an unknown fallback.
- [x] `getDeclaredCapabilities`: read usage descriptions and embedded entitlements.
- [x] Additional search folders with persistent, read-only security-scoped bookmarks.
- [x] Example with filters, icons, refresh, empty results, and errors.
- [x] Dart, widget, and native fixture tests; sandbox discovery smoke check.
- [x] GitHub Actions for quality checks, Dart/widget tests, and native macOS tests.
- [x] Release builds verified with Swift Package Manager and CocoaPods fallback.

## Next APIs

- [ ] `appChanges`: watch accessible discovery locations, reconcile snapshots,
      and document missed/coalesced events and stream lifecycle.

## Later

- [ ] Assess Spotlight supplementation without promising complete discovery.

See [API capabilities](doc/api-capabilities.md) for discovery behavior and limitations.
