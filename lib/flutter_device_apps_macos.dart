/// Independent macOS app discovery and management APIs for Flutter.
library;

import 'package:flutter/services.dart';

import 'macos_app_info.dart';

export 'macos_app_info.dart' show MacosAppInfo;

/// Discovers and inspects installed macOS app bundles.
abstract final class FlutterDeviceAppsMacos {
  static const MethodChannel _mch = MethodChannel(
    'flutter_device_apps_macos/methods',
  );

  /// Lists accessible app bundles in standard macOS application directories.
  ///
  /// Scans `/Applications`, `~/Applications`, `/System/Applications`, and
  /// `/System/Library/CoreServices`, including their non-package subdirectories.
  /// Discovery skips app bundle contents and other folders and volumes.
  /// App Sandbox and filesystem permissions can limit the results.
  ///
  /// [includeSystem] includes apps in system locations (default: false).
  /// [onlyLaunchable] requires an executable and excludes background-only and
  /// agent apps (default: true). This is a preflight, not a launch guarantee.
  /// [includeIcons] loads 64×64 PNG icons after filtering (default: false).
  /// [includeArchitectures] reads main executable CPU families (default: false).
  /// [includeSize] totals regular file lengths inside each matched bundle
  /// (default: false). Large bundles can make this expensive.
  /// [includeSigningInfo] reads the embedded signature's Team ID without
  /// verifying the signature (default: false).
  /// Optional metadata is null when not requested or unavailable; a failure
  /// reading it does not discard the app or return a partial bundle size.
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
    bool includeArchitectures = false,
    bool includeSize = false,
    bool includeSigningInfo = false,
    String? bundleIdentifierPrefix,
    String? bundleIdentifierContains,
  }) async {
    final List<dynamic>? raw = await _mch
        .invokeListMethod<dynamic>('listApps', {
          'includeSystem': includeSystem,
          'onlyLaunchable': onlyLaunchable,
          'includeIcons': includeIcons,
          'includeArchitectures': includeArchitectures,
          'includeSize': includeSize,
          'includeSigningInfo': includeSigningInfo,
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

  /// Gets one accessible macOS app by bundle ID or an absolute app bundle path.
  ///
  /// Supply exactly one of [bundleIdentifier] and [appPath]. Bundle ID lookup
  /// uses macOS's preferred copy and verifies its exact bundle identifier.
  /// Path lookup resolves symlinks and can inspect apps outside the standard
  /// discovery directories, subject to App Sandbox and filesystem permissions.
  ///
  /// Includes system apps, agents, background-only apps, and apps without an
  /// executable. No list filters are applied and discovery roots are not scanned.
  /// [includeIcon], [includeArchitectures], [includeSize], and [includeSigningInfo]
  /// enable the same optional metadata as [listApps]; all default to false.
  ///
  /// Returns null if the selected app is missing, unreadable, or not a valid app
  /// bundle. If the preferred copy is inaccessible, no other copy is substituted.
  /// Invalid targets throw [ArgumentError]. Unexpected native lookup failures
  /// throw a [PlatformException] with `ERR_GET`.
  static Future<MacosAppInfo?> getApp({
    String? bundleIdentifier,
    String? appPath,
    bool includeIcon = false,
    bool includeArchitectures = false,
    bool includeSize = false,
    bool includeSigningInfo = false,
  }) async {
    if ((bundleIdentifier == null) == (appPath == null)) {
      throw ArgumentError(
        'Provide exactly one of bundleIdentifier or appPath.',
      );
    }
    final target = bundleIdentifier ?? appPath!;
    if (target.trim().isEmpty || target.contains('\u0000')) {
      throw ArgumentError.value(
        target,
        bundleIdentifier == null ? 'appPath' : 'bundleIdentifier',
      );
    }
    if (appPath != null && !appPath.startsWith('/')) {
      throw ArgumentError.value(
        appPath,
        'appPath',
        'Use an absolute filesystem path.',
      );
    }
    final Map<dynamic, dynamic>? raw = await _mch
        .invokeMapMethod<dynamic, dynamic>('getApp', {
          'bundleIdentifier': bundleIdentifier,
          'appPath': appPath,
          'includeIcon': includeIcon,
          'includeArchitectures': includeArchitectures,
          'includeSize': includeSize,
          'includeSigningInfo': includeSigningInfo,
        });
    return raw == null
        ? null
        : MacosAppInfo.fromMap(Map<String, Object?>.from(raw));
  }
}
