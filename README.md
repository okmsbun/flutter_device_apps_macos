# flutter_device_apps_macos

<p align="center">
<a href="https://pub.dev/packages/flutter_device_apps_macos"><img src="https://img.shields.io/pub/v/flutter_device_apps_macos.svg?color=0175C2" alt="Pub"></a>
<a href="https://pub.dev/packages/flutter_device_apps_macos/score"><img src="https://img.shields.io/pub/points/flutter_device_apps_macos" alt="flutter_device_apps_macos Pub points"></a>
<a href="https://github.com/okmsbun/flutter_device_apps"><img src="https://img.shields.io/github/stars/okmsbun/flutter_device_apps.svg?style=flat&logo=github&colorB=deeppink&label=stars" alt="GitHub stars for flutter_device_apps"></a>
<a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/license-MIT-purple.svg" alt="License: MIT"></a>
<a href="https://pub.dev/packages/flutter_device_apps"><img src="https://img.shields.io/badge/Main%20Package-orange.svg" alt="Main Package"></a>
</p>

A Flutter plugin to list installed macOS apps, get app icons, check installation
status, launch apps, and find file handlers. Also detects packaged frameworks.

## Requirements

Requires macOS 12+, Flutter 3.44+, and Dart 3.12+.
Swift Package Manager and CocoaPods are supported.

[API reference](https://pub.dev/documentation/flutter_device_apps_macos/latest/flutter_device_apps_macos/)
· [Guide: macOS API capabilities](doc/api-capabilities.md)

## Main package

`flutter_device_apps` provides a single entry point for Android and macOS APIs
and uses this plugin on macOS. [Main package](https://pub.dev/packages/flutter_device_apps) · [Main package README](https://github.com/okmsbun/flutter_device_apps#readme)

## Usage

Add the macOS package to your Flutter app.

```sh
flutter pub add flutter_device_apps_macos
```

```dart
import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';
```

Call `WidgetsFlutterBinding.ensureInitialized()` if you use the API before
`runApp()`. The binding is already available in `initState()` and UI callbacks.

### List installed macOS apps

```dart
final apps = await FlutterDeviceAppsMacos.listApps(
  includeSystem: false,
  onlyLaunchable: true,
  includeIcons: false,
  includeSpotlight: false,
  bundleIdentifierPrefix: null, // e.g. 'com.apple.'
  bundleIdentifierContains: null, // e.g. 'TextEdit'
);
```

Both bundle ID filters are case-sensitive and must match when provided.
Use `null` or `''` to disable a filter. Set `includeSpotlight: true` to also
include accessible results from the Spotlight index.

### Get apps by bundle ID or path

```dart
final app = await FlutterDeviceAppsMacos.getApp(
  bundleIdentifier: 'com.apple.TextEdit',
  includeIcon: true,
);

final apps = await FlutterDeviceAppsMacos.getApps(
  ['com.apple.TextEdit', '/Applications/Example Editor.app'],
  includeIcons: true,
);
```

A bundle ID selects the preferred copy. An absolute path selects a specific copy.
`getApp()` returns `null` if the app is unavailable. `getApps()` returns results
in input order and deduplicates by resolved path. It returns `[]` when no apps
are found.

### Detect packaged app frameworks

```dart
final frameworks = await FlutterDeviceAppsMacos.detectAppFrameworks(
  bundleIdentifier: 'com.example.editor',
);
```

Detects packaged indicators for **Flutter, Electron, Qt, Unity, and Java Runtime**.
Matches describe packaged components. An empty list means the scan found no supported indicator.
An unavailable app returns `null`.

### List running apps

```dart
final runningApps = await FlutterDeviceAppsMacos.listRunningApps();
```

Returns a snapshot with one entry per running app instance.

### Find apps that can open a file

```dart
const filePath = '/Users/me/Documents/Report.pdf';

final reader = await FlutterDeviceAppsMacos.getDefaultAppForFile(
  filePath: filePath,
);
final handlers = await FlutterDeviceAppsMacos.listAppsForFile(filePath: filePath);
```

Use a handler's `appPath` with `openFileWithApp` to open the file in that app.
In the example, use **Open with** → **Choose file** → **List compatible apps**.

## More APIs

All methods below belong to `FlutterDeviceAppsMacos`.

| Method | Purpose |
| --- | --- |
| `getAppIcon` | Get 64×64 PNG icon bytes. |
| `isAppInstalled` | Check whether the app is installed and accessible. |
| `isSystemApp` | Check system app status using the app's location. |
| `isAppLaunchable` | Check whether the app passes the launch preflight. |
| `getInstallSourceInfo` | Get App Store receipt and quarantine indicators. |
| `getDeclaredCapabilities` | Get usage descriptions and embedded entitlements. |
| `openApp` | Launch the app. |
| `revealAppInFinder` | Show and select the app in Finder. |
| `moveAppToTrash` | Move the app bundle to Trash using its resolved path. |
| `openFileWithApp` | Open a file using the selected app path. |
| `addAppSearchFolder` | Select and save an additional discovery folder. |
| `listAppSearchFolders` | List saved discovery folders. |
| `removeAppSearchFolder` | Remove a folder from future discovery scans. |

## macOS setup

The generated `Info.plist` is sufficient for standard app discovery and
management. macOS applies App Sandbox and filesystem permissions to each
operation.

For a sandboxed app that lets users choose files or folders, set **User Selected
File** to **Read Only** under **Signing & Capabilities**. In a Flutter app, add
the key inside `<dict>` in `macos/Runner/DebugProfile.entitlements` and
`macos/Runner/Release.entitlements`. [Apple App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

```xml
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

Add the app-scoped bookmark entitlement if you use `addAppSearchFolder` to
keep access to search folders across launches. [Apple bookmark entitlements](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)

```xml
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
```

The example includes both entitlements. For `openFileWithApp`, keep file access
active until the call completes. `moveAppToTrash` requires write access to the
bundle. [Discovery and access details](doc/api-capabilities.md)

## Community Standards

[Issues](https://github.com/okmsbun/flutter_device_apps_macos/issues) · [Contributing](CONTRIBUTING.md) · [Code of Conduct](CODE_OF_CONDUCT.md) · [Security Policy](SECURITY.md)

## License

[MIT](LICENSE) © 2026 okmsbun
