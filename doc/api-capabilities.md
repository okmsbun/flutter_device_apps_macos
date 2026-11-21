# macOS API capabilities

`flutter_device_apps_macos` discovers and inspects macOS app bundles.
Currently implemented: `FlutterDeviceAppsMacos.listApps`, `getApp`, `getApps`, and `MacosAppInfo`.
See [TODO](../TODO.md) for planned APIs.

## Discovery scope

`listApps` scans these locations and their non-package subdirectories:

- `/Applications`
- `~/Applications`
- `/System/Applications`
- `/System/Library/CoreServices`

Discovery skips app bundle contents, hidden locations, other folders, and additional
volumes. Optional size calculation traverses matched bundles. Symbolic links to
app bundles are resolved; aliases to the same resolved
path are deduplicated. Spotlight and custom search roots are not currently used.

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

## Filters and icons

| Parameter | Default | Behavior |
| --- | --- | --- |
| `includeSystem` | `false` | Includes apps in system locations. |
| `onlyLaunchable` | `true` | Requires a declared executable file with execute permission; excludes `LSBackgroundOnly` and `LSUIElement` apps. |
| `includeIcons` | `false` | Loads 64×64 PNG icons after filtering. |
| `includeArchitectures` | `false` | Reads CPU architecture families from the main executable. |
| `includeSize` | `false` | Calculates the logical byte size of regular file entries inside each matched bundle. |
| `includeSigningInfo` | `false` | Reads the Team ID from the embedded code signature. |
| `bundleIdentifierPrefix` | `null` | Case-sensitive bundle ID prefix. |
| `bundleIdentifierContains` | `null` | Case-sensitive bundle ID substring. |

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

| Field | Option | Meaning |
| --- | --- | --- |
| `supportedArchitectures` | `includeArchitectures` | Sorted CPU architecture families reported by `Bundle.executableArchitectures`, such as `arm64` and `x86_64`. This covers the main executable, not CPU subtypes or embedded helper executables. Unknown CPU types use `cpu-<number>`. |
| `bundleSizeBytes` | `includeSize` | Sum of logical byte lengths of regular file entries, including hidden files and nested bundles. Symlinks are not followed or counted; hard-linked entries are counted individually. Incomplete traversal returns null. |
| `teamIdentifier` | `includeSigningInfo` | Team ID reported by the embedded signature. Unsigned or ad-hoc signed apps normally have no Team ID. This read does not verify signature validity or notarization. |

Logical bundle size is not allocated disk usage; APFS sharing and compression
are not reflected. It also excludes app data stored outside the bundle.

Build numbers are strings so dotted `CFBundleVersion` values remain intact.
Unavailable metadata stays null. Filesystem timestamps are not treated as an
installation history.

## Access and errors

App Sandbox and filesystem permissions can limit discovery. Unreadable bundles
and subdirectories are skipped. If all existing search directories are
inaccessible, the method throws `PlatformException` with code `ERR_LIST`.

The example keeps App Sandbox enabled. Native tests cover standard-directory
access in that configuration. Discovery in other environments can differ.
User-granted access and persistent security-scoped bookmarks are planned.

## Sources

- [File enumeration](https://developer.apple.com/documentation/foundation/filemanager/enumerator(at:includingpropertiesforkeys:options:errorhandler:))
- [Bundle metadata](https://developer.apple.com/documentation/foundation/bundle/infodictionary)
- [File icons](https://developer.apple.com/documentation/appkit/nsworkspace/icon(forfile:))
- [Default app lookup](https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication(withbundleidentifier:))
- [Executable architectures](https://developer.apple.com/documentation/foundation/bundle/executablearchitectures)
- [File sizes](https://developer.apple.com/documentation/foundation/urlresourcevalues/filesize)
- [Code-signing metadata](https://developer.apple.com/documentation/security/signing-information-dictionary-keys)
- [App Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
