import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(home: MacosPluginExample()));
}

/// Development host for the macOS plugin scaffold.
class MacosPluginExample extends StatelessWidget {
  const MacosPluginExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_device_apps_macos')),
      body: const Center(
        child: Text('macOS plugin scaffold. App APIs are not implemented yet.'),
      ),
    );
  }
}
