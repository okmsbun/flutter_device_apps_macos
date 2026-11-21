import 'package:flutter/services.dart';
import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';
import 'package:material_ui/material_ui.dart';

class DefaultAppForFileDialog extends StatefulWidget {
  const DefaultAppForFileDialog({super.key});

  @override
  State<DefaultAppForFileDialog> createState() =>
      _DefaultAppForFileDialogState();
}

class _DefaultAppForFileDialogState extends State<DefaultAppForFileDialog> {
  static const _filePicker = MethodChannel(
    'flutter_device_apps_macos_example/file_picker',
  );
  final _path = TextEditingController();
  Future<List<MacosAppInfo>>? _result;
  Future<void>? _opening;
  String? _selectedFileId;
  bool _picking = false;
  String? _message;

  bool get _busy => _picking || _opening != null;

  Future<void> _chooseFile() async {
    setState(() {
      _picking = true;
      _message = null;
    });
    try {
      final file = await _filePicker.invokeMapMethod<String, String>(
        'chooseFile',
      );
      if (file == null) return;
      final id = file['id']!;
      if (!mounted) {
        _releaseFile(id);
        return;
      }
      _releaseSelection();
      _selectedFileId = id;
      _path.text = file['path']!;
      _result = null;
    } catch (error) {
      _message = 'Could not choose a file: $error';
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  static void _releaseFile(String id) {
    _filePicker.invokeMethod<void>('releaseFile', id).ignore();
  }

  void _releaseSelection() {
    final id = _selectedFileId;
    if (id == null) return;
    _selectedFileId = null;
    final pending = _opening ?? _result;
    if (pending == null) {
      _releaseFile(id);
    } else {
      pending.whenComplete(() => _releaseFile(id)).ignore();
    }
  }

  void _lookup({bool allApps = false}) {
    final path = _path.text;
    final result = allApps
        ? FlutterDeviceAppsMacos.listAppsForFile(filePath: path)
        : FlutterDeviceAppsMacos.getDefaultAppForFile(
            filePath: path,
          ).then((app) => [?app]);
    result.ignore();
    setState(() {
      _result = result;
      _message = null;
    });
  }

  Future<void> _open(String appPath) async {
    final opening = FlutterDeviceAppsMacos.openFileWithApp(
      filePath: _path.text,
      appPath: appPath,
    );
    setState(() {
      _opening = opening;
      _message = null;
    });
    String message;
    try {
      await opening;
      message = 'File opened.';
    } catch (error) {
      message = 'Could not open the file: $error';
    }
    if (!mounted) return;
    setState(() {
      _opening = null;
      _message = message;
    });
  }

  @override
  void dispose() {
    _releaseSelection();
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open with'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _path,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Absolute file path',
              ),
              onChanged: (_) {
                _releaseSelection();
                setState(() {
                  _result = null;
                  _message = null;
                });
              },
              onSubmitted: (_) => _lookup(),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _chooseFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose file'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              FutureBuilder<List<MacosAppInfo>>(
                future: _result,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text('Could not look up apps: ${snapshot.error}');
                  }
                  final apps = snapshot.requireData;
                  if (apps.isEmpty) {
                    return const Text('No apps available for this file.');
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final app in apps)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            app.appName ??
                                app.bundleIdentifier ??
                                'Unknown app',
                          ),
                          subtitle: Text(
                            [?app.bundleIdentifier, ?app.appPath].join('\n'),
                          ),
                          trailing: switch (app.appPath) {
                            final path? => TextButton(
                              onPressed: _busy ? null : () => _open(path),
                              child: const Text('Open'),
                            ),
                            null => null,
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
            if (_opening != null)
              const LinearProgressIndicator()
            else if (_message case final message?)
              Text(message),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: _busy ? null : _lookup,
          child: const Text('Find default app'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _lookup(allApps: true),
          child: const Text('List compatible apps'),
        ),
      ],
    );
  }
}
