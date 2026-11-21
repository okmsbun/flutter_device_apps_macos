/// The install source suggested by metadata available on a macOS app bundle.
enum MacosAppInstallSource {
  /// An App Store receipt marker is present inside the app bundle.
  macAppStore,

  /// Launch Services quarantine metadata marks the app as a web download.
  webDownload,

  /// Available metadata gives no supported source indication.
  unknown,
}

/// Install source indicators for an accessible macOS app bundle.
///
/// These are local signals that can be absent, copied, or modified.
final class MacosAppInstallSourceInfo {
  const MacosAppInstallSourceInfo({
    required this.source,
    required this.hasAppStoreReceipt,
    this.quarantineAgentName,
    this.quarantineAgentBundleIdentifier,
  });

  /// Decodes install source indicators returned by the macOS plugin.
  factory MacosAppInstallSourceInfo.fromMap(Map<String, Object?> map) =>
      MacosAppInstallSourceInfo(
        source: switch (map['source']) {
          'macAppStore' => MacosAppInstallSource.macAppStore,
          'webDownload' => MacosAppInstallSource.webDownload,
          _ => MacosAppInstallSource.unknown,
        },
        hasAppStoreReceipt: map['hasAppStoreReceipt'] == true,
        quarantineAgentName: map['quarantineAgentName'] as String?,
        quarantineAgentBundleIdentifier:
            map['quarantineAgentBundleIdentifier'] as String?,
      );

  /// The install source suggested by the observed indicators.
  final MacosAppInstallSource source;

  /// Whether a receipt file was found. Its signature and contents are unchecked.
  final bool hasAppStoreReceipt;

  /// Name of the quarantining app, when available.
  final String? quarantineAgentName;

  /// Bundle identifier of the quarantining app, when available.
  final String? quarantineAgentBundleIdentifier;
}
