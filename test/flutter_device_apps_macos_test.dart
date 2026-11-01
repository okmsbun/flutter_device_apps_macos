import 'package:flutter/services.dart';
import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_device_apps_macos/methods');
  final calls = <MethodCall>[];
  Object? response;
  PlatformException? error;

  setUp(() {
    calls.clear();
    response = <Object>[];
    error = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (error != null) throw error!;
          return response;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('listApps', () {
    test('forwards default options on the macOS method channel', () async {
      expect(await FlutterDeviceAppsMacos.listApps(), isEmpty);
      expect(calls.single.method, 'listApps');
      expect(calls.single.arguments, {
        'includeSystem': false,
        'onlyLaunchable': true,
        'includeIcons': false,
        'bundleIdentifierPrefix': null,
        'bundleIdentifierContains': null,
      });
    });

    test(
      'forwards all options without trimming case-sensitive filters',
      () async {
        await FlutterDeviceAppsMacos.listApps(
          includeSystem: true,
          onlyLaunchable: false,
          includeIcons: true,
          bundleIdentifierPrefix: 'com.Example.',
          bundleIdentifierContains: ' Tool ',
        );
        expect(calls.single.arguments, {
          'includeSystem': true,
          'onlyLaunchable': false,
          'includeIcons': true,
          'bundleIdentifierPrefix': 'com.Example.',
          'bundleIdentifierContains': ' Tool ',
        });
      },
    );

    test('preserves independently disabled filters', () async {
      await FlutterDeviceAppsMacos.listApps(bundleIdentifierPrefix: '');
      expect((calls.single.arguments as Map)['bundleIdentifierPrefix'], '');
      expect(
        (calls.single.arguments as Map)['bundleIdentifierContains'],
        isNull,
      );
    });

    test('decodes metadata and typed PNG bytes', () async {
      final bytes = Uint8List.fromList([137, 80, 78, 71]);
      response = [
        {
          'bundleIdentifier': 'com.example.editor',
          'appName': 'Editor',
          'versionName': '2.3',
          'buildNumber': '42.1.0',
          'appPath': '/Applications/Editor.app',
          'executablePath': '/Applications/Editor.app/Contents/MacOS/Editor',
          'isSystem': false,
          'category': 'public.app-category.developer-tools',
          'minimumSystemVersion': '12.0',
          'iconBytes': bytes,
        },
      ];
      final app = (await FlutterDeviceAppsMacos.listApps(
        includeIcons: true,
      )).single;
      expect(app, isA<MacosAppInfo>());
      expect(app.bundleIdentifier, 'com.example.editor');
      expect(app.appName, 'Editor');
      expect(app.versionName, '2.3');
      expect(app.buildNumber, '42.1.0');
      expect(app.appPath, '/Applications/Editor.app');
      expect(
        app.executablePath,
        '/Applications/Editor.app/Contents/MacOS/Editor',
      );
      expect(app.isSystem, isFalse);
      expect(app.category, 'public.app-category.developer-tools');
      expect(app.minimumSystemVersion, '12.0');
      expect(app.iconBytes, bytes);
    });

    test('preserves distinct copies that share a bundle identifier', () async {
      response = [
        {
          'bundleIdentifier': 'com.example.app',
          'appPath': '/Applications/App.app',
        },
        {
          'bundleIdentifier': 'com.example.app',
          'appPath': '/Users/test/Applications/App.app',
        },
      ];
      final apps = await FlutterDeviceAppsMacos.listApps();
      expect(apps, hasLength(2));
      expect(apps.map((app) => app.appPath).toSet(), hasLength(2));
    });

    test(
      'propagates native scan failures instead of reporting an empty inventory',
      () async {
        error = PlatformException(
          code: 'ERR_LIST',
          message: 'Directories inaccessible',
        );
        await expectLater(
          FlutterDeviceAppsMacos.listApps(),
          throwsA(
            isA<PlatformException>().having((e) => e.code, 'code', 'ERR_LIST'),
          ),
        );
      },
    );
  });

  group('MacosAppInfo', () {
    test('keeps absent metadata null', () {
      final app = MacosAppInfo.fromMap({});
      expect(app.bundleIdentifier, isNull);
      expect(app.appName, isNull);
      expect(app.versionName, isNull);
      expect(app.buildNumber, isNull);
      expect(app.appPath, isNull);
      expect(app.executablePath, isNull);
      expect(app.isSystem, isNull);
      expect(app.category, isNull);
      expect(app.minimumSystemVersion, isNull);
      expect(app.iconBytes, isNull);
    });

    test(
      'accepts a plain byte list and preserves dotted build identifiers',
      () {
        final app = MacosAppInfo.fromMap({
          'buildNumber': '2026.11.1',
          'iconBytes': <int>[137, 80, 78, 71],
          'isSystem': true,
        });
        expect(app.buildNumber, '2026.11.1');
        expect(app.iconBytes, isA<Uint8List>());
        expect(app.iconBytes, [137, 80, 78, 71]);
        expect(app.isSystem, isTrue);
      },
    );
  });
}
