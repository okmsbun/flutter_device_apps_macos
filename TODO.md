# macOS API roadmap

Implement and verify one API at a time in this package and its example.
Keep the static `FlutterDeviceAppsMacos` entry point, `Future` results, optional
named parameters, native method-channel maps, and immutable models consistent
with the existing packages. Use macOS-specific identifiers and metadata where
Android fields have no equivalent. Do not add a platform interface dependency.

## Completed

- [x] Independent macOS plugin with Swift Package Manager and CocoaPods support.
- [x] `MacosAppInfo` with `fromMap`, optional fields, and optional PNG bytes.
- [x] `listApps`: standard directories, system/launchable filters, bundle ID
  prefix and substring filters, path deduplication, optional icons, and `[]` for no matches.
- [x] Example with filters, icons, refresh, empty results, and errors.
- [x] Dart, widget, and native fixture tests; sandbox discovery smoke check.

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
- [ ] `detectAppFrameworks`: define macOS indicators and a separate framework enum;
  distinguish packaged components from the primary UI framework.
- [ ] `appChanges`: watch accessible discovery locations, reconcile snapshots,
  and document missed/coalesced events and stream lifecycle.
- [ ] `getRequestedPermissions`: decide on a macOS-specific declared-capabilities
  contract; usage descriptions and entitlements do not expose other apps' TCC grants.
- [ ] `getInstallSourceInfo`: define a macOS-specific provenance model;
  unknown installer/source information must remain unknown.
- [ ] `uninstallApp`: decide on an explicit `moveAppToTrash` contract and user
  confirmation; moving a bundle does not remove support files or privileged helpers.

## No direct Android equivalent

- [ ] `isAppEnabled`: assess whether any useful separate API is needed;
  login-item state is not package enabled state.
- [ ] `openAppSettings`: assess a separate `revealAppInFinder` API;
  macOS has no documented universal per-app settings screen.

## Later

- [ ] Assess additional discovery roots and user-granted access with security-scoped bookmarks.
- [ ] Assess Spotlight supplementation without promising complete discovery.
- [ ] Verify release builds and CocoaPods integration before publishing.
- [ ] Connect and export from the umbrella package only when requested.

See [API capabilities](doc/api-capabilities.md) for the full comparison.
