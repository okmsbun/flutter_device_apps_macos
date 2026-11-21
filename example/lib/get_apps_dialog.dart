import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';
import 'package:material_ui/material_ui.dart';

class GetAppsDialog extends StatefulWidget {
  const GetAppsDialog({super.key});

  @override
  State<GetAppsDialog> createState() => _GetAppsDialogState();
}

class _GetAppsDialogState extends State<GetAppsDialog> {
  final _targets = TextEditingController();
  Future<List<MacosAppInfo>>? _lookup;

  void _search() {
    final targets = _targets.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final lookup = FlutterDeviceAppsMacos.getApps(targets);
    lookup.ignore();
    setState(() {
      _lookup = lookup;
    });
  }

  @override
  void dispose() {
    _targets.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Get apps'),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('get-apps-targets'),
              controller: _targets,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Bundle IDs or absolute app paths',
                helperText: 'Enter one target per line.',
              ),
              onChanged: (_) => setState(() {
                _lookup = null;
              }),
            ),
            if (_lookup != null) ...[
              const SizedBox(height: 16),
              FutureBuilder<List<MacosAppInfo>>(
                future: _lookup,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text('Could not get apps: ${snapshot.error}');
                  }
                  final apps = snapshot.requireData;
                  if (apps.isEmpty) {
                    return const Text('No matching apps.');
                  }
                  return Column(
                    children: [
                      for (final app in apps)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(app.appName ?? 'Unknown app'),
                          subtitle: Text(
                            app.appPath ?? app.bundleIdentifier ?? '',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(onPressed: _search, child: const Text('Look up apps')),
      ],
    );
  }
}
