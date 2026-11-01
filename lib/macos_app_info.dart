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
    this.category,
    this.minimumSystemVersion,
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
    category: map['category']?.toString(),
    minimumSystemVersion: map['minimumSystemVersion']?.toString(),
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

  /// App category identifier from `LSApplicationCategoryType`.
  final String? category;

  /// Minimum macOS version declared by `LSMinimumSystemVersion`.
  final String? minimumSystemVersion;

  /// 64×64 PNG icon bytes, when requested and available.
  final Uint8List? iconBytes;
}
