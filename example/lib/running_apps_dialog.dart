import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';
import 'package:material_ui/material_ui.dart';

class RunningAppsDialog extends StatefulWidget {
  const RunningAppsDialog({super.key});

  @override
  State<RunningAppsDialog> createState() => _RunningAppsDialogState();
}

class _RunningAppsDialogState extends State<RunningAppsDialog> {
  late Future<List<MacosRunningAppInfo>> _apps =
      FlutterDeviceAppsMacos.listRunningApps();

  void _refresh() {
    final apps = FlutterDeviceAppsMacos.listRunningApps();
    apps.ignore();
    setState(() {
      _apps = apps;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Running apps'),
      content: SizedBox(
        width: 520,
        height: 340,
        child: FutureBuilder<List<MacosRunningAppInfo>>(
          future: _apps,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text('Could not list running apps: ${snapshot.error}');
            }
            final apps = snapshot.requireData;
            if (apps.isEmpty) return const Text('No running apps available.');
            return ListView.builder(
              itemCount: apps.length,
              itemBuilder: (context, index) {
                final app = apps[index];
                final details = [
                  ?app.bundleIdentifier,
                  ?app.appPath,
                  if (app.processIdentifier case final pid?) 'PID $pid',
                ];
                return ListTile(
                  title: Text(
                    app.appName ?? app.bundleIdentifier ?? 'Unknown app',
                  ),
                  subtitle: details.isEmpty ? null : Text(details.join('\n')),
                  trailing: app.isActive ? const Text('Active') : null,
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _refresh,
          child: const Text('Refresh snapshot'),
        ),
      ],
    );
  }
}
