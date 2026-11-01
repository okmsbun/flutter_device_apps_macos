import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_device_apps_macos_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('flutter_device_apps_macos/methods');
  final calls = <MethodCall>[];
  Object? response;
  bool fail = false;

  setUp(() {
    calls.clear();
    fail = false;
    response = [
      {
        'appName': 'Example Editor',
        'bundleIdentifier': 'com.example.editor',
        'appPath': '/Applications/Editor.app',
        'versionName': '1.2.0',
      },
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
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

  testWidgets('loads and displays app metadata', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MacosPluginExample()));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(find.text('Example Editor'), findsOneWidget);
    expect(find.textContaining('/Applications/Editor.app'), findsOneWidget);
    expect(find.text('1 app'), findsOneWidget);
    expect((calls.single.arguments as Map)['onlyLaunchable'], isTrue);
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
