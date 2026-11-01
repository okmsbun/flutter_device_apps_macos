import 'package:flutter/material.dart';
import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';

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
    bundleIdentifierPrefix: _prefix.text,
    bundleIdentifierContains: _contains.text,
  );

  void _reload() {
    final apps = _loadApps();
    setState(() {
      _apps = apps;
    });
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
