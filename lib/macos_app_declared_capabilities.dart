import 'dart:typed_data';

/// Usage descriptions and code-signing entitlements declared by a macOS app.
final class MacosAppDeclaredCapabilities {
  MacosAppDeclaredCapabilities({
    required Map<String, String> usageDescriptions,
    Map<String, Object?>? entitlements,
  }) : usageDescriptions = Map.unmodifiable(usageDescriptions),
       entitlements = entitlements == null ? null : _freezeMap(entitlements);

  /// Decodes declarations returned by the macOS plugin.
  factory MacosAppDeclaredCapabilities.fromMap(Map<String, Object?> map) =>
      MacosAppDeclaredCapabilities(
        usageDescriptions: (map['usageDescriptions'] as Map)
            .cast<String, String>(),
        entitlements: (map['entitlements'] as Map?)?.cast<String, Object?>(),
      );

  /// String entries ending in `UsageDescription` in the app's base Info.plist.
  final Map<String, String> usageDescriptions;

  /// The main app's embedded entitlements, or null when unavailable.
  ///
  /// An empty map means the readable signature contains no entitlements.
  /// Binary data is represented as [Uint8List] and dates as ISO 8601 strings.
  final Map<String, Object?>? entitlements;

  static Map<String, Object?> _freezeMap(Map<Object?, Object?> map) =>
      Map.unmodifiable({
        for (final entry in map.entries)
          entry.key as String: _freezeValue(entry.value),
      });

  static Object? _freezeValue(Object? value) => switch (value) {
    Uint8List bytes => Uint8List.fromList(bytes).asUnmodifiableView(),
    Map<Object?, Object?> map => _freezeMap(map),
    List<Object?> list => List.unmodifiable(list.map(_freezeValue)),
    _ => value,
  };
}
