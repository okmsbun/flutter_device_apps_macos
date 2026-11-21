import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';
import 'package:material_ui/material_ui.dart';

class DefaultAppForFileDialog extends StatefulWidget {
  const DefaultAppForFileDialog({super.key});

  @override
  State<DefaultAppForFileDialog> createState() =>
      _DefaultAppForFileDialogState();
}

class _DefaultAppForFileDialogState extends State<DefaultAppForFileDialog> {
  final _path = TextEditingController();
  Future<MacosAppInfo?>? _result;

  void _lookup() {
    final result = FlutterDeviceAppsMacos.getDefaultAppForFile(
      filePath: _path.text,
    );
    result.ignore();
    setState(() {
      _result = result;
    });
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Default app for a file'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _path,
              decoration: const InputDecoration(
                labelText: 'Absolute file path',
              ),
              onChanged: (_) => setState(() => _result = null),
              onSubmitted: (_) => _lookup(),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              FutureBuilder<MacosAppInfo?>(
                future: _result,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text(
                      'Could not find the default app: ${snapshot.error}',
                    );
                  }
                  final app = snapshot.data;
                  if (app == null) {
                    return const Text('File or default app unavailable.');
                  }
                  return SelectableText(
                    [
                      app.appName ?? 'Default app',
                      ?app.bundleIdentifier,
                      ?app.appPath,
                    ].join('\n'),
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
        FilledButton(onPressed: _lookup, child: const Text('Find app')),
      ],
    );
  }
}
