# flutter_device_apps_macos

Independent macOS app discovery and management plugin for Flutter.

Requires macOS 12+, Flutter 3.44+, and Dart 3.12+.
Swift Package Manager and CocoaPods are supported.

## List apps

```dart
import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';

final List<MacosAppInfo> apps = await FlutterDeviceAppsMacos.listApps(
  includeSystem: false,
  onlyLaunchable: true,
  includeIcons: false,
  includeArchitectures: false,
  includeSize: false,
  includeSigningInfo: false,
  bundleIdentifierPrefix: null, // Optional: 'com.apple.'.
  bundleIdentifierContains: null, // Optional: 'Safari'.
);
```

- Scans `/Applications`, `~/Applications`, `/System/Applications`, and
  `/System/Library/CoreServices`, including non-package subdirectories.
- Filters are case-sensitive and combined with AND; `null` or `''` disables each.
- Returns `[]` when no apps match. Different paths with the same bundle ID remain separate.
- Icons are optional 64×64 PNG bytes; use `Image.memory(app.iconBytes!)` to display them.
- `isAgent` and `isBackgroundOnly` describe bundle declarations.
- Architectures, logical bundle size, and signature Team ID are optional;
  unavailable values are `null`. Size calculation can be expensive.
- `isSystem` is a location heuristic. `onlyLaunchable` excludes agents,
  background-only apps, and apps without an executable; launch success is not guaranteed.
- App Sandbox and file access can limit discovery. Unreadable bundles are skipped;
  `ERR_LIST` is thrown if all existing search directories are inaccessible.

Call `WidgetsFlutterBinding.ensureInitialized()` when querying before `runApp()`.
Calls from `initState()` and UI callbacks need no extra initialization.

See [TODO](TODO.md) for planned APIs and [API capabilities](doc/api-capabilities.md)
for discovery behavior and limitations.

## Development

```bash
flutter pub get
flutter analyze
cd example
flutter run -d macos
```

## License

[MIT](LICENSE) © 2026 okmsbun
