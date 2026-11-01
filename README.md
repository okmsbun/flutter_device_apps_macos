# flutter_device_apps_macos

Independent macOS app discovery and management plugin for Flutter.

**Status:** Initial scaffold. App APIs are not implemented yet.

- Requires macOS 12+, Flutter 3.44+, and Dart 3.12+.
- No dependency on `flutter_device_apps_platform_interface` or `plugin_platform_interface`.
- Swift plugin registration supports Swift Package Manager and CocoaPods.
- Planned entry point: `FlutterDeviceAppsMacos` with static methods.
- The umbrella package can depend on this package and export its public API.

See the [Android API comparison](doc/api-capabilities.md) before implementing APIs.

## Development

```bash
flutter pub get
flutter analyze
cd example
flutter run -d macos
```

## License

[MIT](LICENSE) © 2026 okmsbun
