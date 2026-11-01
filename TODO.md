# macOS API roadmap

Implement and verify one API at a time in this package and its example.
Keep the static `FlutterDeviceAppsMacos` entry point, `Future` results, optional
named parameters, native method-channel maps, and immutable models.
Use bundle identifiers, app paths, and macOS metadata throughout the API.

## Completed

- [x] Independent macOS plugin with Swift Package Manager and CocoaPods support.
- [x] `MacosAppInfo` with `fromMap`, optional fields, and optional PNG bytes.
- [x] `listApps`: standard directories, system/launchable filters, bundle ID
  prefix and substring filters, path deduplication, optional icons, and `[]` for no matches.
- [x] Example with filters, icons, refresh, empty results, and errors.
- [x] Dart, widget, and native fixture tests; sandbox discovery smoke check.
- [x] GitHub Actions for quality checks, Dart/widget tests, and native macOS tests.

## Next APIs

- [ ] `getApp`: lookup by bundle ID or app path; define preferred-copy behavior
  and return null when no accessible match is found.
- [ ] `getApps`: batch lookup in one native request; preserve requested order
  and define duplicate/missing entry handling.
- [ ] `getAppIcon`: retrieve PNG bytes without loading all app metadata.
- [ ] `isAppInstalled`: document the limits of a negative lookup result.
- [ ] `isSystemApp`: use the same documented location heuristic as `MacosAppInfo.isSystem`.
- [ ] `isAppLaunchable`: define preflight semantics without promising launch success.
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
- [ ] Verify release builds and CocoaPods integration before publishing.

See [API capabilities](doc/api-capabilities.md) for discovery behavior and limitations.
