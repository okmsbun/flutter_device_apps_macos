import 'dart:typed_data';

import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';
import 'package:material_ui/material_ui.dart';

typedef _AppLookup<T> =
    Future<T> Function({String? bundleIdentifier, String? appPath});

/// Looks up and manages one app by bundle identifier or app path.
class GetAppDialog extends StatefulWidget {
  const GetAppDialog({super.key, this.appPath, this.onAppTrashed});

  /// An optional app path to inspect immediately when the dialog opens.
  final String? appPath;
  final VoidCallback? onAppTrashed;

  @override
  State<GetAppDialog> createState() => _GetAppDialogState();
}

class _GetAppDialogState extends State<GetAppDialog> {
  late final TextEditingController _target;
  late bool _byPath;
  bool _includeIcon = false;
  bool _includeArchitectures = false;
  bool _includeSize = false;
  bool _includeSigningInfo = false;
  Future<MacosAppInfo?>? _lookup;
  Future<Uint8List?>? _iconLookup;
  Future<String>? _message;

  @override
  void initState() {
    super.initState();
    _target = TextEditingController(text: widget.appPath ?? '');
    _byPath = widget.appPath != null;
    if (_byPath) {
      _lookup = _loadApp();
    }
  }

  Future<MacosAppInfo?> _loadApp() {
    final lookup = FlutterDeviceAppsMacos.getApp(
      bundleIdentifier: _byPath ? null : _target.text,
      appPath: _byPath ? _target.text : null,
      includeIcon: _includeIcon,
      includeArchitectures: _includeArchitectures,
      includeSize: _includeSize,
      includeSigningInfo: _includeSigningInfo,
    );
    // FutureBuilder subscribes on the next build. Observe early failures now;
    // the original future still delivers its error to the builder for display.
    lookup.ignore();
    return lookup;
  }

  void _search() {
    final lookup = _loadApp();
    setState(() {
      _clearResults();
      _lookup = lookup;
    });
  }

  void _loadIcon() {
    final lookup = FlutterDeviceAppsMacos.getAppIcon(
      bundleIdentifier: _byPath ? null : _target.text,
      appPath: _byPath ? _target.text : null,
    );
    lookup.ignore();
    setState(() {
      _clearResults();
      _iconLookup = lookup;
    });
  }

  void _checkApp(String label, _AppLookup<bool?> check) {
    _inspectApp(check, (result) {
      final value = switch (result) {
        true => 'Yes',
        false => 'No',
        null => 'Unavailable',
      };
      return '$label: $value';
    });
  }

  void _inspectApp<T>(_AppLookup<T> lookup, String Function(T) describe) {
    _showMessage(
      lookup(
        bundleIdentifier: _byPath ? null : _target.text,
        appPath: _byPath ? _target.text : null,
      ).then(describe),
    );
  }

  String _describeTechnologies(MacosAppTechnologies? technologies) {
    if (technologies == null) return 'App not found or inaccessible.';
    String name(MacosAppTechnology technology) => switch (technology) {
      MacosAppTechnology.flutter => 'Flutter',
      MacosAppTechnology.electron => 'Electron',
      MacosAppTechnology.qt => 'Qt Core',
      MacosAppTechnology.unity => 'Unity',
      MacosAppTechnology.javaRuntime => 'Java Runtime',
      MacosAppTechnology.qtWidgets => 'Qt Widgets',
      MacosAppTechnology.qtQuick => 'Qt Quick',
      MacosAppTechnology.chromiumEmbeddedFramework =>
        'Chromium Embedded Framework',
      MacosAppTechnology.godot => 'Godot',
      MacosAppTechnology.dart => 'Dart',
    };
    final categories = {
      'Frameworks': technologies.frameworks,
      'Programming languages': technologies.programmingLanguages,
      'UI toolkits': technologies.uiToolkits,
      'Game engines': technologies.gameEngines,
      'Runtimes': technologies.runtimes,
      'Libraries': technologies.libraries,
    };
    final rows = [
      for (final category in categories.entries)
        if (category.value.isNotEmpty)
          '${category.key}: ${category.value.map(name).join(', ')}',
    ];
    return rows.isEmpty
        ? 'No supported technology indicators found.'
        : rows.join('\n');
  }

  String _describeInstallSource(MacosAppInstallSourceInfo? info) {
    if (info == null) return 'App not found or inaccessible.';
    final source = switch (info.source) {
      MacosAppInstallSource.macAppStore => 'Mac App Store receipt found',
      MacosAppInstallSource.webDownload => 'Web download',
      MacosAppInstallSource.unknown => 'Unknown',
    };
    final agent =
        info.quarantineAgentName ?? info.quarantineAgentBundleIdentifier;
    return [
      'Install source: $source',
      if (agent != null) 'Quarantine agent: $agent',
    ].join('\n');
  }

  String _describeCapabilities(MacosAppDeclaredCapabilities? capabilities) {
    if (capabilities == null) return 'App not found or inaccessible.';

    List<String> describe(Map<String, Object?>? fields) {
      if (fields == null) return ['Unavailable'];
      if (fields.isEmpty) return ['None'];
      final keys = fields.keys.toList()..sort();
      return [for (final key in keys) '$key: ${fields[key]}'];
    }

    return [
      'Usage descriptions',
      ...describe(capabilities.usageDescriptions),
      '',
      'Entitlements',
      ...describe(capabilities.entitlements),
    ].join('\n');
  }

  Future<void> _confirmTrash(String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move app to Trash?'),
        content: SelectableText(path),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final onAppTrashed = widget.onAppTrashed;
    _showMessage(
      FlutterDeviceAppsMacos.moveAppToTrash(appPath: path).then((_) {
        onAppTrashed?.call();
        return 'App moved to Trash.';
      }),
    );
  }

  void _showMessage(Future<String> message) {
    message.ignore();
    setState(() {
      _clearResults();
      _message = message;
    });
  }

  void _clearResults() {
    _lookup = null;
    _iconLookup = null;
    _message = null;
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Get app'),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Bundle ID')),
                ButtonSegment(value: true, label: Text('App path')),
              ],
              selected: {_byPath},
              onSelectionChanged: (value) {
                setState(() {
                  _byPath = value.single;
                  _target.clear();
                  _clearResults();
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('get-app-target'),
              controller: _target,
              decoration: InputDecoration(
                labelText: _byPath ? 'Absolute app path' : 'Bundle identifier',
                hintText: _byPath
                    ? '/Applications/Safari.app'
                    : 'com.apple.Safari',
              ),
              onSubmitted: (_) => _search(),
              onChanged: (_) => setState(_clearResults),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _checkApp(
                    'Installed',
                    FlutterDeviceAppsMacos.isAppInstalled,
                  ),
                  child: const Text('Installed?'),
                ),
                TextButton(
                  onPressed: () => _checkApp(
                    'System app',
                    FlutterDeviceAppsMacos.isSystemApp,
                  ),
                  child: const Text('System?'),
                ),
                TextButton(
                  onPressed: () => _checkApp(
                    'Launchable',
                    FlutterDeviceAppsMacos.isAppLaunchable,
                  ),
                  child: const Text('Launchable?'),
                ),
                TextButton(
                  onPressed: () => _inspectApp(
                    FlutterDeviceAppsMacos.openApp,
                    (_) => 'macOS reported launch success.',
                  ),
                  child: const Text('Open app'),
                ),
                TextButton(
                  onPressed: () => _inspectApp(
                    FlutterDeviceAppsMacos.revealAppInFinder,
                    (_) => 'Finder request sent.',
                  ),
                  child: const Text('Show in Finder'),
                ),
                TextButton(
                  onPressed: () => _inspectApp(
                    FlutterDeviceAppsMacos.detectAppTechnologies,
                    _describeTechnologies,
                  ),
                  child: const Text('Technologies'),
                ),
                TextButton(
                  onPressed: () => _inspectApp(
                    FlutterDeviceAppsMacos.getInstallSourceInfo,
                    _describeInstallSource,
                  ),
                  child: const Text('Install source'),
                ),
                TextButton(
                  onPressed: () => _inspectApp(
                    FlutterDeviceAppsMacos.getDeclaredCapabilities,
                    _describeCapabilities,
                  ),
                  child: const Text('Capabilities'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Icon'),
                  selected: _includeIcon,
                  onSelected: (value) => setState(() {
                    _includeIcon = value;
                    _lookup = null;
                  }),
                ),
                FilterChip(
                  label: const Text('Architectures'),
                  selected: _includeArchitectures,
                  onSelected: (value) => setState(() {
                    _includeArchitectures = value;
                    _lookup = null;
                  }),
                ),
                FilterChip(
                  label: const Text('Size'),
                  selected: _includeSize,
                  onSelected: (value) => setState(() {
                    _includeSize = value;
                    _lookup = null;
                  }),
                ),
                FilterChip(
                  label: const Text('Signing info'),
                  selected: _includeSigningInfo,
                  onSelected: (value) => setState(() {
                    _includeSigningInfo = value;
                    _lookup = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_message != null)
              FutureBuilder<String>(
                future: _message,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text(
                      'Could not complete request: ${snapshot.error}',
                    );
                  }
                  return Text(snapshot.requireData);
                },
              ),
            if (_iconLookup != null)
              FutureBuilder<Uint8List?>(
                future: _iconLookup,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text('Could not load icon: ${snapshot.error}');
                  }
                  final icon = snapshot.data;
                  return icon == null
                      ? const Text('App icon unavailable.')
                      : Image.memory(icon, width: 64, height: 64);
                },
              ),
            if (_lookup != null)
              FutureBuilder<MacosAppInfo?>(
                future: _lookup,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text('Could not get app: ${snapshot.error}');
                  }
                  final app = snapshot.data;
                  if (app == null) {
                    return const Text('App not found or inaccessible.');
                  }
                  final icon = app.iconBytes;
                  final path = app.appPath;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (icon != null)
                        Image.memory(icon, width: 64, height: 64),
                      SelectableText(
                        [
                          'Name: ${app.appName ?? 'Unavailable'}',
                          'Bundle ID: ${app.bundleIdentifier ?? 'Unavailable'}',
                          'Path: ${app.appPath ?? 'Unavailable'}',
                          'Version: ${app.versionName ?? 'Unavailable'}',
                          'Build: ${app.buildNumber ?? 'Unavailable'}',
                          'Executable: ${app.executablePath ?? 'Unavailable'}',
                          'System location: ${app.isSystem ?? 'Unavailable'}',
                          'Agent: ${app.isAgent ?? 'Unavailable'}',
                          'Background only: ${app.isBackgroundOnly ?? 'Unavailable'}',
                          if (_includeArchitectures)
                            'Architectures: ${app.supportedArchitectures?.join(', ') ?? 'Unavailable'}',
                          if (_includeSize)
                            'Bundle size: ${app.bundleSizeBytes == null ? 'Unavailable' : '${app.bundleSizeBytes} bytes'}',
                          if (_includeSigningInfo)
                            'Team ID: ${app.teamIdentifier ?? 'Unavailable'}',
                        ].join('\n'),
                      ),
                      if (path != null)
                        TextButton(
                          onPressed: () => _confirmTrash(path),
                          child: const Text('Move to Trash…'),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        TextButton(onPressed: _loadIcon, child: const Text('Load icon')),
        FilledButton(onPressed: _search, child: const Text('Lookup')),
      ],
    );
  }
}
