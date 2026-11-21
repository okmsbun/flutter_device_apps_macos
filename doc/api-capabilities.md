# List installed macOS apps in Flutter

Use `FlutterDeviceAppsMacos.listApps()` to list installed apps that your Flutter
app can access. Read app names, bundle identifiers, and paths from the results,
or load PNG icons and other bundle metadata on demand.

Requires macOS 12+, Flutter 3.44+, and Dart 3.12+.

## List installed apps

```bash
flutter pub add flutter_device_apps_macos
```

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';

Future<void> printInstalledMacosApps() async {
  final apps = await FlutterDeviceAppsMacos.listApps();
  for (final app in apps) {
    final name = app.appName ?? 'Unknown app';
    final identifier = app.bundleIdentifier ?? app.appPath ?? 'Unknown app';
    debugPrint('$name ($identifier)');
  }
}
```

Call this after Flutter initializes. The default list includes accessible,
launchable user apps. Set `includeIcons: true` to load icons or
`includeSystem: true` to include system apps. If an app is outside the default
search folders, use a [user-selected folder](#additional-search-folders) or
include [Spotlight results](#spotlight-results).

See the [macOS API reference](https://pub.dev/documentation/flutter_device_apps_macos/latest/flutter_device_apps_macos/)
or the [Flutter guide for Android and macOS](https://github.com/okmsbun/flutter_device_apps/blob/HEAD/doc/list-installed-android-apps.md).

## Discovery scope

`listApps` scans these locations and their non-package subdirectories:

- `/Applications`
- `~/Applications`
- `/System/Applications`
- `/System/Library/CoreServices`

Discovery also includes accessible user-selected search folders. It skips
app bundle contents and hidden entries in each search root. Optional size
calculation traverses matched bundles. Symbolic links to app bundles resolve
to their actual paths, and aliases to the same path are deduplicated.

### Additional search folders

`addAppSearchFolder` opens a macOS folder picker and persists an app-scoped,
read-only bookmark. Saved folders use the same filters and path deduplication as
standard directories. Bookmark access is active during scans and direct app
operations. Unavailable volumes are skipped and stay in
`listAppSearchFolders`. Use `removeAppSearchFolder` with the saved folder ID to
remove its bookmark.

Sandboxed host apps enable `com.apple.security.files.user-selected.read-only`
and `com.apple.security.files.bookmarks.app-scope`. Both entitlements are
configured in the example. [Apple – App Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

### Spotlight results

The `includeSpotlight` option defaults to `false`. When enabled, `listApps`
queries Spotlight for application bundles on the local computer and merges
readable matches with the folder scan. Both sources use the same filters and
resolved-path deduplication. Spotlight candidates inside app or package
bundles and hidden app entries are skipped.

The query uses the results gathered within up to two seconds. If none are
available, the folder scan supplies the results. App Sandbox, filesystem
permissions, and Spotlight indexing determine which apps can be listed.
[Apple – NSMetadataQuery](https://developer.apple.com/documentation/foundation/nsmetadataquery)

## App identity

The resolved `appPath` identifies an app copy. Multiple copies can share the same
`bundleIdentifier`; each distinct path remains in the result. An app can also lack
a bundle identifier.

Results are sorted by localized app name and then path. No matches returns `[]`.

## Single app lookup

`getApp` returns one `MacosAppInfo`, or null when the selected app is missing,
unreadable, or not a valid app bundle. Supply exactly one named target:

- `bundleIdentifier`: resolves the default copy using
  `NSWorkspace.urlForApplication(withBundleIdentifier:)` and verifies an exact,
  case-sensitive match against the bundle's metadata.
- `appPath`: accepts an absolute filesystem path and resolves symlinks. It can
  inspect accessible bundles outside the standard discovery directories.

Bundle ID lookup does not enumerate discovery roots or choose another copy when
the preferred one is inaccessible. Use an explicit path to select a specific copy.
Relative paths, `~/` expansion, and `file://` URLs are not accepted.

The method includes system apps, agent/background apps, hidden bundles, and apps
without executables. List filters are not applied. `includeIcon` defaults to false;
`includeArchitectures`, `includeSize`, and `includeSigningInfo` behave as in `listApps`.

Missing, blank, conflicting, or invalid targets throw `ArgumentError` in Dart.
Malformed direct method-channel arguments produce `ARG`. Unexpected native
lookup failures produce `ERR_GET`; they are not treated as a missing app.

## Batch app lookup

`getApps` accepts bundle IDs and absolute app paths in a single ordered list.
Each entry uses the single app lookup rules. Missing or inaccessible apps are
skipped, and the first match for each resolved path is returned in input order.
Distinct copies with the same bundle ID remain separate. Empty input or no
matches returns `[]`.

The batch shares `includeIcons`, `includeArchitectures`, `includeSize`, and
`includeSigningInfo` options across all matches. Invalid targets throw
`ArgumentError`. Unexpected lookup failures produce `ERR_GET_APPS`.

## App icon lookup

`getAppIcon` uses the single app lookup rules and returns only the 64×64 PNG
bytes. An inaccessible app or unavailable PNG returns `null`. Invalid targets
throw `ArgumentError`, and unexpected native failures produce `ERR_GET_ICON`.

## App status checks

All three methods use the single app lookup rules for bundle IDs and absolute
app paths.

- `isAppInstalled` returns `true` for an accessible app bundle. A `false`
  result covers missing apps, inaccessible apps, and inaccessible preferred
  copies.
- `isSystemApp` applies the same location heuristic as `MacosAppInfo.isSystem`
  and returns `null` when the target is unavailable.
- `isAppLaunchable` uses the same preflight as `listApps(onlyLaunchable: true)`.
  It requires a declared regular executable file with execute permission and
  both agent and background-only flags disabled. An unavailable app returns
  `false`. Actual launch can still fail under macOS runtime conditions.

Invalid targets throw `ArgumentError`. Unexpected native lookup failures
produce `ERR_QUERY`.

## App metadata inspection

These APIs use the single app lookup rules and return `null` when the app is
unavailable. They inspect the selected bundle without scanning discovery roots.

- `detectAppFrameworks` checks for Flutter, Electron, Qt, and Unity binaries
  under `Contents/Frameworks` and for a packaged JVM under `Contents/runtime`
  or `Contents/jbr`. It returns all matches, or `[]` when no supported indicators
  are visible.
  Matches describe packaged components. Helpers and nested bundles are outside
  the scan scope, and the primary UI framework remains unspecified.
- `getInstallSourceInfo` uses the `Contents/_MASReceipt/receipt` file as a
  `macAppStore` indicator. Without that marker, Launch Services web-download
  quarantine metadata yields `webDownload`. Otherwise the source is `unknown`.
  Receipt signatures are unchecked. Quarantine data can be absent or copied
  with a bundle. If available, the quarantine agent name and bundle ID describe
  the quarantining app. Homebrew, installer packages, and other origins may
  remain unknown.
- `getDeclaredCapabilities` returns string keys ending in `UsageDescription`
  from the base `Info.plist` and the main app's embedded entitlements. The
  entitlement map is empty when the readable signature has no entitlements
  and `null` when signing information or the entitlement dictionary is
  unavailable. Binary values are byte arrays and dates are ISO 8601 strings.
  macOS manages runtime privacy grants separately through TCC.

Invalid targets throw `ArgumentError`. Unexpected native lookup failures
produce `ERR_FRAMEWORK_SCAN`, `ERR_INSTALL_SOURCE`, or `ERR_CAPABILITIES`.

## Running apps and default file handlers

- `listRunningApps` captures the current `NSWorkspace.runningApplications`
  snapshot. It returns separate entries for each running instance, including
  instances with the same bundle ID. Name, bundle ID, app path, and PID are
  optional. `isActive` describes the app at the time of the query.
- `getDefaultAppForFile` takes an absolute `filePath` and asks macOS for its
  default handler. The result uses the handler's exact app bundle and the
  `MacosAppInfo` model. Missing files or unavailable handlers yield `null`.
  Invalid paths throw `ArgumentError`.
- `listAppsForFile` takes an absolute `filePath` and returns the accessible apps
  reported as handlers by macOS. Results follow macOS's order with duplicates
  removed by resolved app path. An unavailable file or empty handler list
  yields `[]`.
- `openFileWithApp` takes absolute file and app paths and completes when macOS
  reports the result. The selected app applies to that open request.
  An unavailable app produces `APP_UNAVAILABLE`. Open failures produce
  `ERR_OPEN_FILE` with native error details.

For sandboxed hosts, select files outside the app's accessible folders through
the macOS file picker and keep the resulting file access active until opening
completes. The example's **Choose file** button keeps that access for the dialog.

## App actions

- `openApp` accepts a bundle ID or absolute app path and uses the single app
  lookup rules. Its future completes when `NSWorkspace` reports launch success.
  macOS decides whether the resolved app can open.
- `revealAppInFinder` accepts the same targets and completes once the selection
  request is sent to Finder. The native API provides no selection confirmation.
- `moveAppToTrash` takes the resolved absolute `MacosAppInfo.appPath`. The
  caller should show this path and ask the user to confirm. Symlinks that
  resolve to a different path are rejected. The future completes after
  `FileManager` moves the bundle. App Sandbox and filesystem permissions apply.
  App data, support files, and helpers outside the bundle remain in place.

Invalid arguments throw `ArgumentError`. An unavailable target produces
`APP_UNAVAILABLE`. Operation failures produce `ERR_OPEN`, `ERR_REVEAL`, or
`ERR_TRASH` with a message and native error details.

## Filters and icons

| Parameter                  | Default | Behavior                                                                                                         |
| -------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------- |
| `includeSystem`            | `false` | Includes apps in system locations.                                                                               |
| `onlyLaunchable`           | `true`  | Requires a declared executable file with execute permission; excludes `LSBackgroundOnly` and `LSUIElement` apps. |
| `includeIcons`             | `false` | Loads 64×64 PNG icons after filtering.                                                                           |
| `includeArchitectures`     | `false` | Reads CPU architecture families from the main executable.                                                        |
| `includeSize`              | `false` | Calculates the logical byte size of regular file entries inside each matched bundle.                             |
| `includeSigningInfo`       | `false` | Reads the Team ID from the embedded code signature.                                                              |
| `bundleIdentifierPrefix`   | `null`  | Case-sensitive bundle ID prefix.                                                                                 |
| `bundleIdentifierContains` | `null`  | Case-sensitive bundle ID substring.                                                                              |

Bundle ID filters use AND. `null` or an empty string disables each filter
independently. Apps without a bundle ID are excluded when either filter is active.

`isSystem` is a location heuristic: system discovery roots and resolved paths in
`/System` count as system locations, excluding the writable
`/System/Volumes/Data` subtree. It does not verify code signing or ownership.

`onlyLaunchable` is a preflight. Gatekeeper, compatibility, permissions, and runtime
conditions can still prevent an app from opening.

## Metadata

`MacosAppInfo` contains optional bundle metadata: name, bundle identifier, version,
build number, app path, executable path, system-location classification, app
category, minimum macOS version, and icon bytes. `isAgent` and `isBackgroundOnly`
reflect the `LSUIElement` and `LSBackgroundOnly` declarations, defaulting to false
when the keys are absent. They do not describe the current running state.

The following metadata is loaded only when its corresponding option is enabled,
after discovery filters are applied. Unrequested or unavailable values remain
null; optional metadata failures do not discard the app.

| Field                    | Option                 | Meaning                                                                                                                                                                                                                              |
| ------------------------ | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `supportedArchitectures` | `includeArchitectures` | Sorted CPU architecture families reported by `Bundle.executableArchitectures`, such as `arm64` and `x86_64`. This covers the main executable, not CPU subtypes or embedded helper executables. Unknown CPU types use `cpu-<number>`. |
| `bundleSizeBytes`        | `includeSize`          | Sum of logical byte lengths of regular file entries, including hidden files and nested bundles. Symlinks are not followed or counted; hard-linked entries are counted individually. Incomplete traversal returns null.               |
| `teamIdentifier`         | `includeSigningInfo`   | Team ID reported by the embedded signature. Unsigned or ad-hoc signed apps normally have no Team ID. This read does not verify signature validity or notarization.                                                                   |

Logical bundle size is not allocated disk usage; APFS sharing and compression
are not reflected. It also excludes app data stored outside the bundle.

Build numbers are strings so dotted `CFBundleVersion` values remain intact.
Unavailable metadata stays null. Filesystem timestamps are not treated as an
installation history.

## Access and errors

App Sandbox and filesystem permissions can limit discovery. Unreadable bundles
and subdirectories are skipped. If all existing search directories are
inaccessible and no apps are found, the method throws `PlatformException`
with code `ERR_LIST`.

The example keeps App Sandbox enabled. Native tests cover standard-directory
access and bookmark restoration in that configuration. Discovery in other
environments can differ.

## Sources

- [File enumeration](<https://developer.apple.com/documentation/foundation/filemanager/enumerator(at:includingpropertiesforkeys:options:errorhandler:)>)
- [Bundle metadata](https://developer.apple.com/documentation/foundation/bundle/infodictionary)
- [File icons](<https://developer.apple.com/documentation/appkit/nsworkspace/icon(forfile:)>)
- [Default app lookup](<https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication(withbundleidentifier:)>)
- [Running applications](https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications)
- [Default file handler](https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication%28toopen%3A%29-7qkzf)
- [Available file handlers](https://developer.apple.com/documentation/appkit/nsworkspace/urlsforapplications%28toopen%3A%29-ualk)
- [Open a file with an app](https://developer.apple.com/documentation/appkit/nsworkspace/open%28_%3AwithApplicationAt%3Aconfiguration%3AcompletionHandler%3A%29)
- [Bundle contents and framework locations](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)
- [App Store receipts](https://developer.apple.com/documentation/appstorereceipts/validating-receipts-on-the-device)
- [Quarantine properties](https://developer.apple.com/documentation/foundation/urlresourcekey/quarantinepropertieskey)
- [App launch](<https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)>)
- [Finder selection](<https://developer.apple.com/documentation/appkit/nsworkspace/activatefileviewerselecting(_:)>)
- [Move to Trash](<https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)>)
- [Executable architectures](https://developer.apple.com/documentation/foundation/bundle/executablearchitectures)
- [File sizes](https://developer.apple.com/documentation/foundation/urlresourcevalues/filesize)
- [Code-signing metadata](https://developer.apple.com/documentation/security/signing-information-dictionary-keys)
- [App Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
