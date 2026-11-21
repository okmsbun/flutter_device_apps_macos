/// A running application instance reported by macOS.
final class MacosRunningAppInfo {
  const MacosRunningAppInfo({
    this.appName,
    this.bundleIdentifier,
    this.appPath,
    this.processIdentifier,
    required this.isActive,
  });

  /// Decodes a running application returned by the macOS plugin.
  factory MacosRunningAppInfo.fromMap(Map<String, Object?> map) =>
      MacosRunningAppInfo(
        appName: map['appName'] as String?,
        bundleIdentifier: map['bundleIdentifier'] as String?,
        appPath: map['appPath'] as String?,
        processIdentifier: map['processIdentifier'] as int?,
        isActive: map['isActive'] == true,
      );

  /// The localized application name, when available.
  final String? appName;

  /// The running application's bundle identifier, when available.
  final String? bundleIdentifier;

  /// The application bundle path reported by macOS, when available.
  final String? appPath;

  /// The process identifier at the time of the query, when available.
  final int? processIdentifier;

  /// Whether the application was active at the time of the query.
  final bool isActive;
}
