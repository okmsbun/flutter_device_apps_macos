/// Independent macOS app discovery and management APIs for Flutter.
library;

import 'package:flutter/services.dart';

import 'macos_app_declared_capabilities.dart';
import 'macos_app_info.dart';
import 'macos_app_install_source_info.dart';
import 'macos_app_search_folder.dart';
import 'macos_running_app_info.dart';

export 'macos_app_declared_capabilities.dart' show MacosAppDeclaredCapabilities;
export 'macos_app_info.dart' show MacosAppInfo;
export 'macos_app_install_source_info.dart'
    show MacosAppInstallSource, MacosAppInstallSourceInfo;
export 'macos_app_search_folder.dart' show MacosAppSearchFolder;
export 'macos_running_app_info.dart' show MacosRunningAppInfo;

/// Framework components identified by known files in a macOS app bundle.
enum MacosAppFramework {
  /// The Flutter macOS engine.
  flutter,

  /// The Electron framework.
  electron,

  /// The Qt Core framework.
  qt,

  /// The Unity player library.
  unity,

  /// A Java virtual machine packaged with the application.
  javaRuntime,
}

/// Discovers, inspects, and manages macOS app bundles.
abstract final class FlutterDeviceAppsMacos {
  static const MethodChannel _mch = MethodChannel(
    'flutter_device_apps_macos/methods',
  );

  static List<MacosAppInfo> _decodeApps(List<dynamic>? raw) =>
      (raw ?? const <dynamic>[])
          .map(
            (entry) =>
                MacosAppInfo.fromMap(Map<String, Object?>.from(entry as Map)),
          )
          .toList();

  static Map<String, String?> _lookupArguments(
    String? bundleIdentifier,
    String? appPath,
  ) {
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
    return {'bundleIdentifier': bundleIdentifier, 'appPath': appPath};
  }

  /// Lists accessible app bundles in macOS application directories.
  ///
  /// Scans `/Applications`, `~/Applications`, `/System/Applications`, and
  /// `/System/Library/CoreServices`, including their non-package subdirectories.
  /// Also scans accessible folders registered by [addAppSearchFolder].
  /// Discovery skips app bundle contents.
  /// App Sandbox and filesystem permissions can limit the results.
  ///
  /// [includeSystem] includes apps in system locations (default: false).
  /// [includeSpotlight] also checks accessible app bundles found in the Spotlight
  /// index for local volumes (default: false). Coverage depends on indexing and access.
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
  /// if all existing search directories are inaccessible and no apps are found.
  static Future<List<MacosAppInfo>> listApps({
    bool includeSystem = false,
    bool includeSpotlight = false,
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
          'includeSpotlight': includeSpotlight,
          'onlyLaunchable': onlyLaunchable,
          'includeIcons': includeIcons,
          'includeArchitectures': includeArchitectures,
          'includeSize': includeSize,
          'includeSigningInfo': includeSigningInfo,
          'bundleIdentifierPrefix': bundleIdentifierPrefix,
          'bundleIdentifierContains': bundleIdentifierContains,
        });
    return _decodeApps(raw);
  }

  /// Returns a snapshot of the running applications reported by macOS.
  ///
  /// Multiple running instances with the same bundle identifier are included.
  /// Optional fields are null when the system does not report them.
  static Future<List<MacosRunningAppInfo>> listRunningApps() async {
    final apps = await _mch.invokeListMethod<Map>('listRunningApps');
    return [
      for (final app in apps ?? const <Map>[])
        MacosRunningAppInfo.fromMap(app.cast<String, Object?>()),
    ];
  }

  /// Gets the application that macOS would use to open an existing file.
  ///
  /// Supply an absolute [filePath]. Returns null when the file or its default
  /// app is unavailable. Invalid paths throw [ArgumentError].
  static Future<MacosAppInfo?> getDefaultAppForFile({
    required String filePath,
  }) async {
    final map = await _mch.invokeMapMethod<String, Object?>(
      'getDefaultAppForFile',
      {'filePath': _absolutePath(filePath, 'filePath')},
    );
    return map == null ? null : MacosAppInfo.fromMap(map);
  }

  /// Lists accessible applications that macOS associates with an existing file.
  ///
  /// Supply an absolute [filePath]. Returns an empty list when the file is
  /// unavailable or no handlers can be read. Invalid paths throw [ArgumentError].
  static Future<List<MacosAppInfo>> listAppsForFile({
    required String filePath,
  }) async {
    final apps = await _mch.invokeListMethod<dynamic>('listAppsForFile', {
      'filePath': _absolutePath(filePath, 'filePath'),
    });
    return _decodeApps(apps);
  }

  /// Opens a file in the selected app bundle.
  ///
  /// Supply absolute paths for both [filePath] and [appPath]. Invalid paths
  /// throw [ArgumentError]. The future completes after macOS reports the result.
  /// In a sandboxed app, keep any user-granted file access active until the
  /// future completes.
  /// A [PlatformException] reports `APP_UNAVAILABLE` for an unavailable app
  /// or `ERR_OPEN_FILE` for a native open failure.
  static Future<void> openFileWithApp({
    required String filePath,
    required String appPath,
  }) async {
    await _mch.invokeMethod<void>('openFileWithApp', {
      'filePath': _absolutePath(filePath, 'filePath'),
      'appPath': _absolutePath(appPath, 'appPath'),
    });
  }

  static String _absolutePath(String path, String argument) {
    if (!path.startsWith('/') || path.contains('\u0000')) {
      throw ArgumentError.value(
        path,
        argument,
        'Use an absolute filesystem path.',
      );
    }
    return path;
  }

  /// Opens the macOS folder picker and registers the selected folder for [listApps].
  ///
  /// The read-only bookmark persists across launches of the host app.
  /// Returns null on cancellation. A [PlatformException] with
  /// `ERR_SEARCH_FOLDERS` reports a bookmark creation or storage failure.
  static Future<MacosAppSearchFolder?> addAppSearchFolder() async {
    final map = await _mch.invokeMapMethod<String, Object?>(
      'addAppSearchFolder',
    );
    return map == null ? null : MacosAppSearchFolder.fromMap(map);
  }

  /// Lists the host app's saved search folders, including unavailable folders.
  static Future<List<MacosAppSearchFolder>> listAppSearchFolders() async {
    final folders = await _mch.invokeListMethod<Map>('listAppSearchFolders');
    return [
      for (final folder in folders ?? const <Map>[])
        MacosAppSearchFolder.fromMap(folder.cast<String, Object?>()),
    ];
  }

  /// Stops including the saved folder with this [id] in future scans.
  static Future<void> removeAppSearchFolder({required String id}) async {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    await _mch.invokeMethod<void>('removeAppSearchFolder', {'id': id});
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
    final Map<dynamic, dynamic>? raw = await _mch
        .invokeMapMethod<dynamic, dynamic>('getApp', {
          ..._lookupArguments(bundleIdentifier, appPath),
          'includeIcon': includeIcon,
          'includeArchitectures': includeArchitectures,
          'includeSize': includeSize,
          'includeSigningInfo': includeSigningInfo,
        });
    return raw == null
        ? null
        : MacosAppInfo.fromMap(Map<String, Object?>.from(raw));
  }

  /// Looks up bundle IDs and absolute app paths in one native request.
  ///
  /// Entries starting with `/` select an exact path. Other entries are bundle
  /// IDs and select the preferred copy, following [getApp] semantics.
  /// Returns accessible apps in input order, keeping the first match for each
  /// resolved path. Distinct copies with the same bundle ID remain separate.
  /// Empty input or no matches returns an empty list.
  ///
  /// Blank entries, NUL characters, and entries with a slash outside an
  /// absolute path throw [ArgumentError]. Unexpected lookup failures throw a
  /// [PlatformException] with `ERR_GET_APPS`.
  static Future<List<MacosAppInfo>> getApps(
    List<String> targets, {
    bool includeIcons = false,
    bool includeArchitectures = false,
    bool includeSize = false,
    bool includeSigningInfo = false,
  }) async {
    if (targets.isEmpty) return [];
    for (final target in targets) {
      if (target.trim().isEmpty ||
          target.contains('\u0000') ||
          (target.contains('/') && !target.startsWith('/'))) {
        throw ArgumentError.value(
          target,
          'targets',
          'Use a bundle identifier or an absolute app path.',
        );
      }
    }

    final List<dynamic>? raw = await _mch.invokeListMethod<dynamic>('getApps', {
      'targets': targets,
      'includeIcons': includeIcons,
      'includeArchitectures': includeArchitectures,
      'includeSize': includeSize,
      'includeSigningInfo': includeSigningInfo,
    });
    return _decodeApps(raw);
  }

  /// Gets a 64×64 PNG icon for a bundle ID or an absolute app path.
  ///
  /// Supply exactly one target, using the lookup rules of [getApp].
  /// Returns null if the app is unavailable or the icon cannot be encoded.
  /// Invalid targets throw [ArgumentError]. Unexpected native failures throw
  /// a [PlatformException] with `ERR_GET_ICON`.
  static Future<Uint8List?> getAppIcon({
    String? bundleIdentifier,
    String? appPath,
  }) async => _mch.invokeMethod<Uint8List>(
    'getAppIcon',
    _lookupArguments(bundleIdentifier, appPath),
  );

  /// Checks for an accessible app bundle using the single app lookup rules of [getApp].
  ///
  /// Supply exactly one of [bundleIdentifier] and [appPath]. A false result
  /// includes missing apps and apps outside the caller's access.
  static Future<bool> isAppInstalled({
    String? bundleIdentifier,
    String? appPath,
  }) async =>
      await _checkApp('isAppInstalled', bundleIdentifier, appPath) ?? false;

  /// Classifies a resolved app using the location heuristic of [MacosAppInfo.isSystem].
  ///
  /// Supply exactly one of [bundleIdentifier] and [appPath]. Returns null
  /// when the selected app is unavailable or inaccessible.
  static Future<bool?> isSystemApp({
    String? bundleIdentifier,
    String? appPath,
  }) => _checkApp('isSystemApp', bundleIdentifier, appPath);

  /// Checks if an app passes the same preflight as [listApps] with onlyLaunchable enabled.
  ///
  /// Supply exactly one of [bundleIdentifier] and [appPath]. The app must have
  /// a regular file with execute permission and both the agent and background
  /// flags disabled. Actual launch can still fail under macOS runtime conditions.
  static Future<bool> isAppLaunchable({
    String? bundleIdentifier,
    String? appPath,
  }) async =>
      await _checkApp('isAppLaunchable', bundleIdentifier, appPath) ?? false;

  /// Identifies supported framework components packaged in a macOS app.
  ///
  /// Supply exactly one target using the lookup rules of [getApp]. Matches are
  /// limited to supported files present in the bundle. Multiple components can
  /// match, without identifying the app's primary UI framework.
  /// Returns an empty list when no indicators are found or null when the app
  /// is unavailable. Invalid targets throw [ArgumentError]. Unexpected native
  /// failures throw a [PlatformException] with `ERR_FRAMEWORK_SCAN`.
  static Future<List<MacosAppFramework>?> detectAppFrameworks({
    String? bundleIdentifier,
    String? appPath,
  }) async {
    final names = await _mch.invokeListMethod<String>(
      'detectAppFrameworks',
      _lookupArguments(bundleIdentifier, appPath),
    );
    return names == null
        ? null
        : MacosAppFramework.values
              .where((framework) => names.contains(framework.name))
              .toList();
  }

  /// Reads the selected app's App Store receipt and quarantine indicators.
  ///
  /// Supply exactly one target using the lookup rules of [getApp]. Returns null
  /// for an unavailable app and [MacosAppInstallSource.unknown] in the result
  /// when the source cannot be inferred. Invalid targets throw [ArgumentError].
  /// Unexpected native failures throw a [PlatformException] with
  /// `ERR_INSTALL_SOURCE`.
  static Future<MacosAppInstallSourceInfo?> getInstallSourceInfo({
    String? bundleIdentifier,
    String? appPath,
  }) async {
    final map = await _mch.invokeMapMethod<String, Object?>(
      'getInstallSourceInfo',
      _lookupArguments(bundleIdentifier, appPath),
    );
    return map == null ? null : MacosAppInstallSourceInfo.fromMap(map);
  }

  /// Reads the selected app's usage descriptions and embedded entitlements.
  ///
  /// Supply exactly one target using the lookup rules of [getApp]. Returns null
  /// for an unavailable app. The result describes bundle metadata, while
  /// macOS manages runtime privacy grants separately.
  /// Invalid targets throw [ArgumentError]. Unexpected native lookup failures
  /// throw a [PlatformException] with `ERR_CAPABILITIES`.
  static Future<MacosAppDeclaredCapabilities?> getDeclaredCapabilities({
    String? bundleIdentifier,
    String? appPath,
  }) async {
    final map = await _mch.invokeMapMethod<String, Object?>(
      'getDeclaredCapabilities',
      _lookupArguments(bundleIdentifier, appPath),
    );
    return map == null ? null : MacosAppDeclaredCapabilities.fromMap(map);
  }

  /// Opens the selected app and waits for macOS to report the launch result.
  ///
  /// Supply exactly one target using the lookup rules of [getApp]. Invalid
  /// targets throw [ArgumentError]. A [PlatformException] reports
  /// `APP_UNAVAILABLE` for a lookup miss or `ERR_OPEN` for a native failure.
  static Future<void> openApp({
    String? bundleIdentifier,
    String? appPath,
  }) async {
    await _mch.invokeMethod<void>(
      'openApp',
      _lookupArguments(bundleIdentifier, appPath),
    );
  }

  /// Requests that Finder show and select the app bundle.
  ///
  /// Supply exactly one target using the lookup rules of [getApp]. The future
  /// completes after sending the request. Invalid targets throw [ArgumentError].
  /// A [PlatformException] reports `APP_UNAVAILABLE` for a lookup miss or
  /// `ERR_REVEAL` for a native failure.
  static Future<void> revealAppInFinder({
    String? bundleIdentifier,
    String? appPath,
  }) async {
    await _mch.invokeMethod<void>(
      'revealAppInFinder',
      _lookupArguments(bundleIdentifier, appPath),
    );
  }

  /// Moves only the app bundle at [appPath] to Trash.
  ///
  /// Pass the resolved absolute path from [MacosAppInfo.appPath]. Show that path
  /// to the user and get confirmation before calling this method. Invalid
  /// arguments throw [ArgumentError]. A [PlatformException] reports
  /// `APP_UNAVAILABLE` for a lookup miss or `ERR_TRASH` for an unresolved path
  /// or a native failure such as insufficient permissions.
  static Future<void> moveAppToTrash({required String appPath}) async {
    await _mch.invokeMethod<void>(
      'moveAppToTrash',
      _lookupArguments(null, appPath),
    );
  }

  static Future<bool?> _checkApp(
    String method,
    String? bundleIdentifier,
    String? appPath,
  ) async => _mch.invokeMethod<bool>(
    method,
    _lookupArguments(bundleIdentifier, appPath),
  );
}
