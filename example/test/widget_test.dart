import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_device_apps_macos_example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const channel = MethodChannel('flutter_device_apps_macos/methods');
  final calls = <MethodCall>[];
  Object? response;
  Object? getResponse;
  Uint8List? iconResponse;
  PlatformException? lookupError;
  bool fail = false;

  setUp(() {
    calls.clear();
    fail = false;
    lookupError = null;
    iconResponse = null;
    getResponse = {
      'appName': 'Lookup Editor',
      'bundleIdentifier': 'com.example.lookup',
      'appPath': '/Applications/Lookup Editor.app',
      'isAgent': false,
      'isBackgroundOnly': false,
      'supportedArchitectures': ['arm64'],
      'bundleSizeBytes': 2048,
      'teamIdentifier': 'EXAMPLE123',
    };
    response = [
      {
        'appName': 'Example Editor',
        'bundleIdentifier': 'com.example.editor',
        'appPath': '/Applications/Editor.app',
        'versionName': '1.2.0',
        'isAgent': false,
        'isBackgroundOnly': false,
        'supportedArchitectures': ['arm64', 'x86_64'],
        'bundleSizeBytes': 4096,
        'teamIdentifier': 'EXAMPLE123',
      },
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getApp') {
            if (lookupError != null) throw lookupError!;
            return getResponse;
          }
          if (call.method == 'getAppIcon') return iconResponse;
          if (call.method == 'isAppInstalled') return true;
          if (call.method == 'isSystemApp') return null;
          if (call.method == 'isAppLaunchable') return false;
          if (call.method == 'detectAppFrameworks') return ['flutter', 'qt'];
          if (call.method == 'getInstallSourceInfo') {
            return {
              'source': 'webDownload',
              'hasAppStoreReceipt': false,
              'quarantineAgentName': 'Safari',
            };
          }
          if ([
            'openApp',
            'revealAppInFinder',
            'moveAppToTrash',
          ].contains(call.method)) {
            return null;
          }
          if (fail) {
            throw PlatformException(code: 'ERR_LIST', message: 'Access denied');
          }
          return response;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('checks the selected app status in the lookup dialog', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Get app'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('get-app-target')),
      'com.example.editor',
    );

    for (final (button, status) in [
      ('Installed?', 'Installed: Yes'),
      ('System?', 'System app: Unavailable'),
      ('Launchable?', 'Launchable: No'),
    ]) {
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(find.text(status), findsOneWidget);
    }

    expect(calls.map((call) => call.method), [
      'listApps',
      'isAppInstalled',
      'isSystemApp',
      'isAppLaunchable',
    ]);
    for (final call in calls.skip(1)) {
      expect(call.arguments, {
        'bundleIdentifier': 'com.example.editor',
        'appPath': null,
      });
    }
  });

  testWidgets(
    'opens, reveals, and confirms the resolved path before trashing',
    (tester) async {
      const path = '/Applications/Lookup Editor.app';
      await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Get app'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('get-app-target')),
        'com.example.lookup',
      );
      for (final (button, message, method) in [
        ('Open app', 'macOS reported launch success.', 'openApp'),
        ('Show in Finder', 'Finder request sent.', 'revealAppInFinder'),
      ]) {
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(calls.last.method, method);
        expect(calls.last.arguments, {
          'bundleIdentifier': 'com.example.lookup',
          'appPath': null,
        });
      }

      await tester.tap(find.text('Lookup'));
      await tester.pumpAndSettle();
      final trashButton = find.text('Move to Trash…');
      await tester.ensureVisible(trashButton);
      await tester.tap(trashButton);
      await tester.pumpAndSettle();
      expect(find.text(path), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'getApp');

      await tester.ensureVisible(trashButton);
      await tester.tap(trashButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to Trash'));
      await tester.pumpAndSettle();
      final trashCall = calls.singleWhere(
        (call) => call.method == 'moveAppToTrash',
      );
      expect(trashCall.arguments, {'bundleIdentifier': null, 'appPath': path});
      expect(find.text('App moved to Trash.'), findsOneWidget);
      expect(calls.last.method, 'listApps');
    },
  );

  testWidgets('shows framework and install source indicators', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Get app'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('get-app-target')),
      'com.example.editor',
    );

    await tester.tap(find.text('Frameworks'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'detectAppFrameworks');
    expect(find.text('Packaged frameworks: Flutter, Qt'), findsOneWidget);

    await tester.tap(find.text('Install source'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'getInstallSourceInfo');
    expect(
      find.text('Install source: Web download\nQuarantine agent: Safari'),
      findsOneWidget,
    );
  });

  testWidgets('loads an icon through the icon API', (tester) async {
    iconResponse = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j2ioAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Get app'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('get-app-target')),
      'com.example.editor',
    );
    await tester.tap(find.text('Load icon'));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), ['listApps', 'getAppIcon']);
    expect(calls.last.arguments, {
      'bundleIdentifier': 'com.example.editor',
      'appPath': null,
    });
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('looks up a batch of bundle IDs and paths', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();
    response = [
      {'appName': 'Batch Editor', 'appPath': '/Applications/Editor Copy.app'},
    ];

    await tester.tap(find.byTooltip('Get apps'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('get-apps-targets')),
      'com.example.editor\n\n/Applications/Editor Copy.app',
    );
    await tester.tap(find.text('Look up apps'));
    await tester.pumpAndSettle();

    final lookup = calls.where((call) => call.method == 'getApps').single;
    expect((lookup.arguments as Map)['targets'], [
      'com.example.editor',
      '/Applications/Editor Copy.app',
    ]);
    expect(find.text('Batch Editor'), findsOneWidget);
    expect(find.text('/Applications/Editor Copy.app'), findsOneWidget);
  });

  testWidgets('loads and displays app metadata', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(find.text('Example Editor'), findsOneWidget);
    expect(find.textContaining('/Applications/Editor.app'), findsOneWidget);
    expect(find.text('1 app'), findsOneWidget);
    expect((calls.single.arguments as Map)['onlyLaunchable'], isTrue);
    expect((calls.single.arguments as Map)['includeArchitectures'], isFalse);
    expect((calls.single.arguments as Map)['includeSize'], isFalse);
    expect((calls.single.arguments as Map)['includeSigningInfo'], isFalse);
    expect(find.textContaining('Agent: false'), findsOneWidget);
    expect(find.textContaining('Architectures:'), findsNothing);
  });

  testWidgets('applies bundle ID filters and reloads with selected options', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'com.example.');
    await tester.enterText(find.byType(TextField).at(1), 'editor');
    await tester.tap(find.byTooltip('Apply filters'));
    await tester.pumpAndSettle();
    expect(
      (calls.last.arguments as Map)['bundleIdentifierPrefix'],
      'com.example.',
    );
    expect((calls.last.arguments as Map)['bundleIdentifierContains'], 'editor');
    await tester.tap(find.text('Include system'));
    await tester.pumpAndSettle();
    expect((calls.last.arguments as Map)['includeSystem'], isTrue);
    await tester.tap(find.text('Icons'));
    await tester.pumpAndSettle();
    expect((calls.last.arguments as Map)['includeIcons'], isTrue);
    await tester.tap(find.text('Only launchable'));
    await tester.pumpAndSettle();
    expect((calls.last.arguments as Map)['onlyLaunchable'], isFalse);
    await tester.tap(find.text('Architectures'));
    await tester.pumpAndSettle();
    expect((calls.last.arguments as Map)['includeArchitectures'], isTrue);
    expect(find.textContaining('Architectures: arm64, x86_64'), findsOneWidget);
    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    expect((calls.last.arguments as Map)['includeSize'], isTrue);
    expect(find.textContaining('Bundle size: 4096 bytes'), findsOneWidget);
    await tester.tap(find.text('Signing info'));
    await tester.pumpAndSettle();
    expect((calls.last.arguments as Map)['includeSigningInfo'], isTrue);
    expect(find.textContaining('Team ID: EXAMPLE123'), findsOneWidget);
  });

  testWidgets('shows unavailable optional metadata without hiding the app', (
    tester,
  ) async {
    response = [
      {'appName': 'Unknown metadata', 'appPath': '/Applications/Unknown.app'},
    ];
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();
    for (final label in ['Architectures', 'Size', 'Signing info']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(find.text('Unknown metadata'), findsOneWidget);
    expect(find.textContaining('Architectures: Unavailable'), findsOneWidget);
    expect(find.textContaining('Bundle size: Unavailable'), findsOneWidget);
    expect(find.textContaining('Team ID: Unavailable'), findsOneWidget);
  });

  testWidgets('looks up a bundle ID with optional metadata', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Get app'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('get-app-target')),
      'com.example.lookup',
    );
    for (final label in ['Icon', 'Architectures', 'Size', 'Signing info']) {
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Lookup'));
    await tester.pumpAndSettle();
    final lookup = calls.where((call) => call.method == 'getApp').single;
    expect(lookup.arguments, {
      'bundleIdentifier': 'com.example.lookup',
      'appPath': null,
      'includeIcon': true,
      'includeArchitectures': true,
      'includeSize': true,
      'includeSigningInfo': true,
    });
    expect(find.textContaining('Name: Lookup Editor'), findsOneWidget);
    expect(find.textContaining('Team ID: EXAMPLE123'), findsOneWidget);
  });

  testWidgets('selects an exact listed app copy using its path', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example Editor'));
    await tester.pumpAndSettle();
    final lookup = calls.where((call) => call.method == 'getApp').single;
    expect((lookup.arguments as Map)['appPath'], '/Applications/Editor.app');
    expect((lookup.arguments as Map)['bundleIdentifier'], isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('get-app-target')))
          .controller!
          .text,
      '/Applications/Editor.app',
    );
    expect(find.textContaining('Name: Lookup Editor'), findsOneWidget);
  });

  testWidgets('shows lookup misses, native failures, and invalid paths', (
    tester,
  ) async {
    getResponse = null;
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Get app'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('App path'));
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('get-app-target'));
    await tester.enterText(target, '/Applications/Missing.app');
    await tester.tap(find.text('Lookup'));
    await tester.pumpAndSettle();
    expect(find.text('App not found or inaccessible.'), findsOneWidget);
    lookupError = PlatformException(code: 'ERR_GET', message: 'Lookup failed');
    await tester.tap(find.text('Lookup'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not get app:'), findsOneWidget);
    await tester.enterText(target, 'relative.app');
    await tester.tap(find.text('Lookup'));
    await tester.pumpAndSettle();
    expect(find.textContaining('absolute filesystem path'), findsOneWidget);
    expect(calls.where((call) => call.method == 'getApp'), hasLength(2));
  });

  testWidgets('shows scan failures and retries to an empty result', (
    tester,
  ) async {
    fail = true;
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load apps:'), findsOneWidget);
    fail = false;
    response = [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No apps found.'), findsOneWidget);
    expect(calls, hasLength(2));
  });
}
