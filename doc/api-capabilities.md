# Android API compatibility on macOS

Assessment for Mac mini M4 on current macOS, using public Apple APIs.
This is an implementation plan; the APIs below are not implemented yet.

## Scope and identity

macOS apps are `.app` bundles, not Android packages. Apps can exist in
`/Applications`, `/System/Applications`, `~/Applications`, other folders, and
mounted volumes. Multiple copies can share the same bundle identifier.

Use the bundle URL/path as the identity of an app instance and expose
`bundleIdentifier` separately. Bundle ID lookups should explicitly define whether
they return the system-preferred copy or all discovered copies. Do not deduplicate
the complete inventory by bundle identifier alone.

Directory scanning can provide an inventory of accessible search roots. Spotlight
can supplement it but depends on indexing and access. NSWorkspace resolves known
apps and launches them; its public API does not provide a complete installed-app
inventory. `runningApplications` lists running apps, not installed apps.

## Method comparison

**Supported** means a useful public native equivalent exists for an accessible
app. **Limited** means coverage or semantics differ. **No direct equivalent**
means the Android contract should not be copied into the macOS API.

| Android API | macOS assessment | Implementation and limits |
| --- | --- | --- |
| `listApps` | Limited | Scan configured accessible roots for `.app` bundles; optionally supplement with Spotlight. Results are scoped to discovery locations, not guaranteed to cover the entire Mac. |
| `getApp` | Supported within lookup scope | Resolve a bundle ID with NSWorkspace, or inspect an explicit app URL. Read `Info.plist` for name, bundle ID, and versions. A missing result does not prove no copy exists elsewhere. |
| `getApps` | Supported within lookup scope | Batch the same lookups in one channel request. Define order, missing entries, and how duplicate bundle IDs are handled. |
| `getAppIcon` | Supported | Use `NSWorkspace.icon(forFile:)`, rasterize to a documented size, and return PNG bytes. |
| `isAppInstalled` | Limited | Check resolved/discovered accessible bundles. A negative result only means no app was found within the lookup scope. |
| `isSystemApp` | Limited | A location-based classification is possible for system directories. Android's `FLAG_SYSTEM` has no direct equivalent. Prefer an explicit property such as `isInSystemLocation`; an Apple bundle ID is not proof of system ownership. |
| `isAppEnabled` | No direct equivalent | macOS has no general Android-style per-app enabled/disabled package state. Login-item status is a different concept. |
| `isAppLaunchable` | Limited | Inspect the bundle, executable, and compatibility hints. Signing, Gatekeeper, permissions, and runtime conditions can still prevent launch. A preflight result cannot guarantee launch success. |
| `getRequestedPermissions` | Limited; different API recommended | Read declared `Info.plist` usage descriptions and code-signing entitlements when accessible. These are different concepts, do not enumerate every possible permission, and do not reveal another app's actual TCC grants. Prefer `getDeclaredCapabilities`. |
| `openApp` | Supported | Use `NSWorkspace.openApplication(at:configuration:completionHandler:)` and report its asynchronous success/error. |
| `appChanges` | Limited | Observe accessible discovery roots with file-system events and reconcile inventory snapshots. Events can be coalesced or missed; changes outside watched roots are outside scope. NSWorkspace launch/termination notifications are not install/uninstall events. |
| `openAppSettings` | No direct equivalent | There is no documented universal Android-style per-app settings screen. A separate `revealAppInFinder` method can use `activateFileViewerSelecting`. |
| `uninstallApp` | Limited; different API recommended | An accessible, writable `.app` can be moved to Trash. This does not remove support files, privileged helpers, extensions, or package receipts and has no universal Android-style uninstall confirmation. Prefer an explicit `moveAppToTrash` API. |
| `getInstallSourceInfo` | Limited; different model required | Receipts, signatures, and provenance metadata can provide indicators, not a reliable universal installer identity or installation history. Missing evidence must remain unknown. Do not copy Android installer fields. |
| `detectAppFrameworks` | Limited | Inspect readable bundle contents and, if needed, Mach-O dependencies for platform-specific indicators. Android `.so` fingerprints cannot be reused. Static linking and packaging variations cause false negatives; a packaged dependency does not identify the primary UI framework. |

## Listing parameters

| Android parameter | macOS design |
| --- | --- |
| `includeIcons` | Direct equivalent; load icons after discovery and filtering. |
| `packageNamePrefix` / `packageNameContains` | Use `bundleIdentifierPrefix` / `bundleIdentifierContains`; document case sensitivity and AND behavior. |
| `includeSystem` | Requires an explicit, documented definition of system locations. |
| `onlyLaunchable` | Requires a definition for normal apps, background-only apps, and agent apps; preflight cannot promise a successful launch. |

## Sandbox and access

Flutter macOS examples enable App Sandbox by default. Sandboxed and
non-sandboxed hosts can have different discovery and bundle-reading capabilities.
Some files can still be inaccessible outside App Sandbox due to filesystem
permissions and other macOS protections.

Keep the example's default sandbox enabled. Validate standard discovery roots in
that configuration before promising coverage. Where a user grants access through
an open panel, security-scoped bookmarks can preserve authorized access.

Do not depend on private LaunchServices APIs, private TCC databases, or shell
commands that are assumed to bypass the host app's access restrictions.

## Suggested implementation order

1. Define `MacosAppInfo`, discovery roots, app URL identity, and duplicate handling.
2. Implement `listApps`, `getApp`, `getApps`, and `getAppIcon`.
3. Implement scoped `isAppInstalled`, `openApp`, and `revealAppInFinder`.
4. Add framework indicators and watched-root change events with explicit limits.
5. Assess declared capabilities, provenance, and Trash actions as separate APIs.

The independent package owns its Dart API, models, method channel, and Swift
implementation. It does not import a platform interface. Once APIs are ready,
`flutter_device_apps` can depend on it and export `FlutterDeviceAppsMacos` and
the macOS models.

## Sources

- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [Bundle identifier lookups](https://developer.apple.com/documentation/appkit/nsworkspace/urlsforapplications(withbundleidentifier:))
- [Application launch](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:))
- [File icons](https://developer.apple.com/documentation/appkit/nsworkspace/icon(forfile:))
- [Bundle metadata](https://developer.apple.com/documentation/foundation/bundle/infodictionary)
- [Declared protected resources](https://developer.apple.com/documentation/bundleresources/protected-resources)
- [Code-signing information and entitlements](https://developer.apple.com/documentation/security/signing-information-dictionary-keys)
- [App Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [File System Events](https://developer.apple.com/documentation/coreservices/file_system_events)
- [Move an item to Trash](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))
- [Flutter plugin development](https://docs.flutter.dev/packages-and-plugins/developing-packages)
