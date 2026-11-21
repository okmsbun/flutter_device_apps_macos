/// A user-selected folder registered for app discovery.
final class MacosAppSearchFolder {
  const MacosAppSearchFolder({required this.id, required this.path});

  /// Decodes a search folder registered by the macOS plugin.
  factory MacosAppSearchFolder.fromMap(Map<String, Object?> map) =>
      MacosAppSearchFolder(
        id: map['id'] as String,
        path: map['path'] as String,
      );

  /// The stable identifier used to remove the folder from discovery.
  final String id;

  /// The last known absolute path, including when the volume is unavailable.
  final String path;
}
