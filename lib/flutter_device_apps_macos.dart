/// Independent macOS app discovery and management APIs for Flutter.
library;

import 'package:flutter/services.dart';

import 'macos_app_info.dart';

export 'macos_app_info.dart' show MacosAppInfo;

/// Lists installed macOS app bundles from standard application directories.
///
/// Methods and models are owned by this package without a platform interface.
abstract final class FlutterDeviceAppsMacos {
  static const MethodChannel _mch = MethodChannel(
    'flutter_device_apps_macos/methods',
  );

  /// Lists accessible app bundles in standard macOS application directories.
  ///
  /// Scans `/Applications`, `~/Applications`, `/System/Applications`, and
  /// `/System/Library/CoreServices`, including their non-package subdirectories.
  /// Does not scan inside app bundles or enumerate other folders and volumes.
  /// App Sandbox and filesystem permissions can limit the results.
  ///
  /// [includeSystem] includes apps in system locations (default: false).
  /// [onlyLaunchable] requires an executable and excludes background-only and
  /// agent apps (default: true). This is a preflight, not a launch guarantee.
  /// [includeIcons] loads 64×64 PNG icons after filtering (default: false).
  /// [bundleIdentifierPrefix] and [bundleIdentifierContains] are case-sensitive,
  /// combined with AND, and disabled independently by null or an empty string.
  /// Apps without a bundle identifier only match when both filters are disabled.
  ///
  /// Returns an empty list when there are no matches. Different app paths with
  /// the same bundle identifier remain separate; symlink aliases are deduplicated.
  /// Results are sorted by app name and then path. Unreadable bundles and
  /// subdirectories are skipped. Throws a [PlatformException] with `ERR_LIST`
  /// if all existing search directories are inaccessible.
  static Future<List<MacosAppInfo>> listApps({
    bool includeSystem = false,
    bool onlyLaunchable = true,
    bool includeIcons = false,
    String? bundleIdentifierPrefix,
    String? bundleIdentifierContains,
  }) async {
    final List<dynamic>? raw = await _mch
        .invokeListMethod<dynamic>('listApps', {
          'includeSystem': includeSystem,
          'onlyLaunchable': onlyLaunchable,
          'includeIcons': includeIcons,
          'bundleIdentifierPrefix': bundleIdentifierPrefix,
          'bundleIdentifierContains': bundleIdentifierContains,
        });
    return (raw ?? const <dynamic>[])
        .map(
          (entry) =>
              MacosAppInfo.fromMap(Map<String, Object?>.from(entry as Map)),
        )
        .toList();
  }
}
