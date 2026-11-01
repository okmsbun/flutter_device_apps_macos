import 'dart:typed_data';

/// Metadata for a discovered macOS app bundle.
///
/// [appPath] identifies an app copy; multiple copies can share a bundle ID.
class MacosAppInfo {
  /// Creates app metadata. Unknown or unavailable fields can be null.
  const MacosAppInfo({
    this.bundleIdentifier,
    this.appName,
    this.versionName,
    this.buildNumber,
    this.appPath,
    this.executablePath,
    this.isSystem,
    this.isAgent,
    this.isBackgroundOnly,
    this.category,
    this.minimumSystemVersion,
    this.supportedArchitectures,
    this.bundleSizeBytes,
    this.teamIdentifier,
    this.iconBytes,
  });

  /// Creates app metadata from a native method-channel map.
  factory MacosAppInfo.fromMap(Map<String, Object?> map) => MacosAppInfo(
    bundleIdentifier: map['bundleIdentifier']?.toString(),
    appName: map['appName']?.toString(),
    versionName: map['versionName']?.toString(),
    buildNumber: map['buildNumber']?.toString(),
    appPath: map['appPath']?.toString(),
    executablePath: map['executablePath']?.toString(),
    isSystem: map['isSystem'] == null
        ? null
        : bool.tryParse(map['isSystem'].toString()),
    isAgent: map['isAgent'] == null
        ? null
        : bool.tryParse(map['isAgent'].toString()),
    isBackgroundOnly: map['isBackgroundOnly'] == null
        ? null
        : bool.tryParse(map['isBackgroundOnly'].toString()),
    category: map['category']?.toString(),
    minimumSystemVersion: map['minimumSystemVersion']?.toString(),
    supportedArchitectures: map['supportedArchitectures'] is List
        ? List<String>.unmodifiable(map['supportedArchitectures']! as List)
        : null,
    bundleSizeBytes: map['bundleSizeBytes'] == null
        ? null
        : int.tryParse(map['bundleSizeBytes'].toString()),
    teamIdentifier: map['teamIdentifier']?.toString(),
    iconBytes: switch (map['iconBytes']) {
      Uint8List bytes => bytes,
      List<int> bytes => Uint8List.fromList(bytes),
      _ => null,
    },
  );

  /// `CFBundleIdentifier`; not unique across app copies and not always present.
  final String? bundleIdentifier;

  /// Localized display name, with a bundle name or filename fallback.
  final String? appName;

  /// User-facing version from `CFBundleShortVersionString`.
  final String? versionName;

  /// Build identifier from `CFBundleVersion`, preserving dotted values as text.
  final String? buildNumber;

  /// Absolute app bundle path with symlinks resolved.
  final String? appPath;

  /// Declared executable path; presence alone does not guarantee launch success.
  final String? executablePath;

  /// Whether the app is in a system location, based on its path.
  ///
  /// This is a location heuristic, not a code-signing or ownership check.
  final bool? isSystem;

  /// Whether `LSUIElement` declares an agent app that does not appear in the Dock.
  ///
  /// This is a bundle declaration, not the app's current running state.
  final bool? isAgent;

  /// Whether `LSBackgroundOnly` declares an app that runs only in the background.
  ///
  /// This is a bundle declaration, not the app's current running state.
  final bool? isBackgroundOnly;

  /// App category identifier from `LSApplicationCategoryType`.
  final String? category;

  /// Minimum macOS version declared by `LSMinimumSystemVersion`.
  final String? minimumSystemVersion;

  /// CPU architecture families supported by the main executable, when requested.
  ///
  /// Values include `arm64`, `x86_64`, `i386`, `arm`, `ppc`, and `ppc64`.
  /// Unrecognized CPU types use `cpu-<number>`. CPU subtypes and embedded helper
  /// executables are not represented. Null when not requested or unavailable.
  final List<String>? supportedArchitectures;

  /// Total logical byte length of regular file entries in the bundle, when requested.
  ///
  /// Includes hidden files and nested bundles. Symlinks are not followed or
  /// counted; hard-linked file entries are counted individually. This is not
  /// allocated disk usage and includes no app data stored outside the bundle.
  /// Null when not requested or when a complete traversal is unavailable.
  final int? bundleSizeBytes;

  /// Team ID reported by the embedded code signature, when requested and available.
  ///
  /// Reading this value does not verify the signature or notarization. Unsigned
  /// and ad-hoc signed apps normally have no Team ID. Null is not a trust verdict.
  final String? teamIdentifier;

  /// 64×64 PNG icon bytes, when requested and available.
  final Uint8List? iconBytes;
}
