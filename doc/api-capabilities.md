# macOS API capabilities

`flutter_device_apps_macos` discovers and inspects macOS app bundles.
Currently implemented: `FlutterDeviceAppsMacos.listApps` and `MacosAppInfo`.
See [TODO](../TODO.md) for planned APIs.

## Discovery scope

`listApps` scans these locations and their non-package subdirectories:

- `/Applications`
- `~/Applications`
- `/System/Applications`
- `/System/Library/CoreServices`

It does not scan inside app bundles, hidden locations, other folders, or additional
volumes. Symbolic links to app bundles are resolved; aliases to the same resolved
path are deduplicated. Spotlight and custom search roots are not currently used.

## App identity

The resolved `appPath` identifies an app copy. Multiple copies can share the same
`bundleIdentifier`; each distinct path remains in the result. An app can also lack
a bundle identifier.

Results are sorted by localized app name and then path. No matches returns `[]`.

## Filters and icons

| Parameter | Default | Behavior |
| --- | --- | --- |
| `includeSystem` | `false` | Includes apps in system locations. |
| `onlyLaunchable` | `true` | Requires a declared executable file with execute permission; excludes `LSBackgroundOnly` and `LSUIElement` apps. |
| `includeIcons` | `false` | Loads 64×64 PNG icons after filtering. |
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
category, minimum macOS version, and icon bytes.

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
- [App Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
