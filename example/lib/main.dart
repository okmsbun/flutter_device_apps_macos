import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';
import 'package:material_ui/material_ui.dart';

import 'get_app_dialog.dart';
import 'get_apps_dialog.dart';

void main() {
  runApp(const MaterialApp(home: MacosPluginExample()));
}

/// Lists app bundles using the independent macOS plugin.
class MacosPluginExample extends StatefulWidget {
  const MacosPluginExample({super.key});

  @override
  State<MacosPluginExample> createState() => _MacosPluginExampleState();
}

class _MacosPluginExampleState extends State<MacosPluginExample> {
  final _prefix = TextEditingController();
  final _contains = TextEditingController();
  bool _includeSystem = false;
  bool _onlyLaunchable = true;
  bool _includeIcons = false;
  bool _includeArchitectures = false;
  bool _includeSize = false;
  bool _includeSigningInfo = false;
  late Future<List<MacosAppInfo>> _apps;

  @override
  void initState() {
    super.initState();
    _apps = _loadApps();
  }

  Future<List<MacosAppInfo>> _loadApps() => FlutterDeviceAppsMacos.listApps(
    includeSystem: _includeSystem,
    onlyLaunchable: _onlyLaunchable,
    includeIcons: _includeIcons,
    includeArchitectures: _includeArchitectures,
    includeSize: _includeSize,
    includeSigningInfo: _includeSigningInfo,
    bundleIdentifierPrefix: _prefix.text,
    bundleIdentifierContains: _contains.text,
  );

  void _reload() {
    if (!mounted) return;
    final apps = _loadApps();
    setState(() {
      _apps = apps;
    });
  }

  Future<void> _openAppLookup({String? appPath}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => GetAppDialog(appPath: appPath, onAppTrashed: _reload),
    );
  }

  @override
  void dispose() {
    _prefix.dispose();
    _contains.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_device_apps_macos'),
        actions: [
          IconButton(
            onPressed: _openAppLookup,
            tooltip: 'Get app',
            icon: const Icon(Icons.manage_search),
          ),
          IconButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const GetAppsDialog(),
            ),
            tooltip: 'Get apps',
            icon: const Icon(Icons.list_alt),
          ),
          IconButton(
            onPressed: _reload,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _prefix,
                        decoration: const InputDecoration(
                          labelText: 'Bundle ID prefix',
                        ),
                        onSubmitted: (_) => _reload(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _contains,
                        decoration: const InputDecoration(
                          labelText: 'Bundle ID contains',
                        ),
                        onSubmitted: (_) => _reload(),
                      ),
                    ),
                    IconButton(
                      onPressed: _reload,
                      tooltip: 'Apply filters',
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    FilterChip(
                      label: const Text('Include system'),
                      selected: _includeSystem,
                      onSelected: (value) {
                        _includeSystem = value;
                        _reload();
                      },
                    ),
                    FilterChip(
                      label: const Text('Only launchable'),
                      selected: _onlyLaunchable,
                      onSelected: (value) {
                        _onlyLaunchable = value;
                        _reload();
                      },
                    ),
                    FilterChip(
                      label: const Text('Icons'),
                      selected: _includeIcons,
                      onSelected: (value) {
                        _includeIcons = value;
                        _reload();
                      },
                    ),
                    FilterChip(
                      label: const Text('Architectures'),
                      selected: _includeArchitectures,
                      onSelected: (value) {
                        _includeArchitectures = value;
                        _reload();
                      },
                    ),
                    FilterChip(
                      label: const Text('Size'),
                      selected: _includeSize,
                      onSelected: (value) {
                        _includeSize = value;
                        _reload();
                      },
                    ),
                    FilterChip(
                      label: const Text('Signing info'),
                      selected: _includeSigningInfo,
                      onSelected: (value) {
                        _includeSigningInfo = value;
                        _reload();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Standard application directories only. Access restrictions may limit results.',
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MacosAppInfo>>(
              future: _apps,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Could not load apps: ${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                          onPressed: _reload,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final apps = snapshot.data ?? const <MacosAppInfo>[];
                if (apps.isEmpty) {
                  return const Center(child: Text('No apps found.'));
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '${apps.length} ${apps.length == 1 ? 'app' : 'apps'}',
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: apps.length,
                        itemBuilder: (context, index) {
                          final app = apps[index];
                          final icon = app.iconBytes;
                          return ListTile(
                            onTap: () => _openAppLookup(appPath: app.appPath),
                            leading: icon == null
                                ? const Icon(Icons.apps)
                                : Image.memory(icon, width: 40, height: 40),
                            title: Text(
                              app.appName ??
                                  app.bundleIdentifier ??
                                  'Unknown app',
                            ),
                            subtitle: Text(
                              [
                                if (app.bundleIdentifier != null)
                                  app.bundleIdentifier!,
                                if (app.versionName != null)
                                  'Version: ${app.versionName}',
                                if (app.buildNumber != null)
                                  'Build: ${app.buildNumber}',
                                if (app.isAgent != null)
                                  'Agent: ${app.isAgent}',
                                if (app.isBackgroundOnly != null)
                                  'Background only: ${app.isBackgroundOnly}',
                                if (_includeArchitectures)
                                  'Architectures: ${app.supportedArchitectures?.join(', ') ?? 'Unavailable'}',
                                if (_includeSize)
                                  'Bundle size: ${app.bundleSizeBytes == null ? 'Unavailable' : '${app.bundleSizeBytes} bytes'}',
                                if (_includeSigningInfo)
                                  'Team ID: ${app.teamIdentifier ?? 'Unavailable'}',
                                if (app.appPath != null) app.appPath!,
                              ].join('\n'),
                            ),
                            trailing: app.isSystem == true
                                ? const Chip(label: Text('System'))
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
