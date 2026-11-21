import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';
import 'package:material_ui/material_ui.dart';

class AppSearchFoldersDialog extends StatefulWidget {
  const AppSearchFoldersDialog({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<AppSearchFoldersDialog> createState() => _AppSearchFoldersDialogState();
}

class _AppSearchFoldersDialogState extends State<AppSearchFoldersDialog> {
  late Future<List<MacosAppSearchFolder>> _folders = _loadFolders();
  bool _working = false;
  Object? _error;

  Future<List<MacosAppSearchFolder>> _loadFolders() {
    final folders = FlutterDeviceAppsMacos.listAppSearchFolders();
    folders.ignore();
    return folders;
  }

  Future<void> _change(Future<bool> Function() change) async {
    final onChanged = widget.onChanged;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (await change()) {
        onChanged();
        if (mounted) _folders = _loadFolders();
      }
    } catch (error) {
      _error = error;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search folders'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Text('Could not update search folders: $_error'),
            FutureBuilder<List<MacosAppSearchFolder>>(
              future: _folders,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text(
                    'Could not load search folders: ${snapshot.error}',
                  );
                }
                final folders = snapshot.requireData;
                if (folders.isEmpty) {
                  return const Text('No extra search folders.');
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final folder in folders)
                      ListTile(
                        title: Text(folder.path),
                        trailing: IconButton(
                          tooltip: 'Remove search folder',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _working
                              ? null
                              : () => _change(() async {
                                  await FlutterDeviceAppsMacos.removeAppSearchFolder(
                                    id: folder.id,
                                  );
                                  return true;
                                }),
                        ),
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
          child: const Text('Done'),
        ),
        FilledButton(
          onPressed: _working
              ? null
              : () => _change(
                  () async =>
                      await FlutterDeviceAppsMacos.addAppSearchFolder() != null,
                ),
          child: const Text('Add folder'),
        ),
      ],
    );
  }
}
