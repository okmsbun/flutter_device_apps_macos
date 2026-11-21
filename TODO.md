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
- [x] Example with filters, icons, refresh, empty results, and errors.
- [x] Dart, widget, and native fixture tests; sandbox discovery smoke check.
- [x] GitHub Actions for quality checks, Dart/widget tests, and native macOS tests.
- [x] Release builds verified with Swift Package Manager and CocoaPods fallback.

## Next APIs

- [ ] `openApp`: use NSWorkspace and report asynchronous launch success/errors.
- [ ] `detectAppFrameworks`: define framework indicators and a result enum;
      distinguish packaged components from the primary UI framework.
- [ ] `appChanges`: watch accessible discovery locations, reconcile snapshots,
      and document missed/coalesced events and stream lifecycle.
- [ ] `getDeclaredCapabilities`: read usage descriptions and entitlements;
      do not report them as another app's actual TCC grants.
- [ ] `getInstallSourceInfo`: define a macOS-specific provenance model;
      unknown installer/source information must remain unknown.
- [ ] `moveAppToTrash`: define the contract and user
      confirmation; moving a bundle does not remove support files or privileged helpers.
- [ ] `revealAppInFinder`: reveal the selected app bundle using NSWorkspace.

## Later

- [ ] Assess additional discovery roots and user-granted access with security-scoped bookmarks.
- [ ] Assess Spotlight supplementation without promising complete discovery.

See [API capabilities](doc/api-capabilities.md) for discovery behavior and limitations.
