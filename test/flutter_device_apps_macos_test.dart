import 'package:flutter/services.dart';
import 'package:flutter_device_apps_macos/flutter_device_apps_macos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_device_apps_macos/methods');
  final calls = <MethodCall>[];
  Object? response;
  Object? getResponse;
  PlatformException? error;

  setUp(() {
    calls.clear();
    response = <Object>[];
    getResponse = null;
    error = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (error != null) throw error!;
          return call.method == 'getApp' ? getResponse : response;
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
        'includeArchitectures': false,
        'includeSize': false,
        'includeSigningInfo': false,
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
          includeArchitectures: true,
          includeSize: true,
          includeSigningInfo: true,
          bundleIdentifierPrefix: 'com.Example.',
          bundleIdentifierContains: ' Tool ',
        );
        expect(calls.single.arguments, {
          'includeSystem': true,
          'onlyLaunchable': false,
          'includeIcons': true,
          'includeArchitectures': true,
          'includeSize': true,
          'includeSigningInfo': true,
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
          'isAgent': true,
          'isBackgroundOnly': false,
          'category': 'public.app-category.developer-tools',
          'minimumSystemVersion': '12.0',
          'supportedArchitectures': ['arm64', 'x86_64'],
          'bundleSizeBytes': 12345678901,
          'teamIdentifier': 'EXAMPLE123',
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
      expect(app.isAgent, isTrue);
      expect(app.isBackgroundOnly, isFalse);
      expect(app.category, 'public.app-category.developer-tools');
      expect(app.minimumSystemVersion, '12.0');
      expect(app.supportedArchitectures, ['arm64', 'x86_64']);
      expect(app.bundleSizeBytes, 12345678901);
      expect(app.teamIdentifier, 'EXAMPLE123');
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

  group('getApp', () {
    test('forwards a bundle ID and defaults in one request', () async {
      expect(
        await FlutterDeviceAppsMacos.getApp(
          bundleIdentifier: 'com.example.Editor',
        ),
        isNull,
      );
      expect(calls.single.method, 'getApp');
      expect(calls.single.arguments, {
        'bundleIdentifier': 'com.example.Editor',
        'appPath': null,
        'includeIcon': false,
        'includeArchitectures': false,
        'includeSize': false,
        'includeSigningInfo': false,
      });
    });

    test('forwards an exact app path and all metadata options', () async {
      await FlutterDeviceAppsMacos.getApp(
        appPath: '/Applications/Example Editor.app',
        includeIcon: true,
        includeArchitectures: true,
        includeSize: true,
        includeSigningInfo: true,
      );
      expect(calls.single.arguments, {
        'bundleIdentifier': null,
        'appPath': '/Applications/Example Editor.app',
        'includeIcon': true,
        'includeArchitectures': true,
        'includeSize': true,
        'includeSigningInfo': true,
      });
    });

    test('decodes a single app using the same model as listApps', () async {
      getResponse = {
        'bundleIdentifier': 'com.example.editor',
        'appName': 'Editor',
        'appPath': '/Applications/Editor.app',
        'isAgent': true,
        'isSystem': true,
        'supportedArchitectures': ['arm64'],
        'bundleSizeBytes': 12345678901,
        'teamIdentifier': 'EXAMPLE123',
        'iconBytes': Uint8List.fromList([137, 80, 78, 71]),
      };
      final app = await FlutterDeviceAppsMacos.getApp(
        bundleIdentifier: 'com.example.editor',
        includeIcon: true,
        includeArchitectures: true,
        includeSize: true,
        includeSigningInfo: true,
      );
      expect(app, isA<MacosAppInfo>());
      expect(app!.appName, 'Editor');
      expect(app.appPath, '/Applications/Editor.app');
      expect(app.isAgent, isTrue);
      expect(app.isSystem, isTrue);
      expect(app.supportedArchitectures, ['arm64']);
      expect(app.bundleSizeBytes, 12345678901);
      expect(app.teamIdentifier, 'EXAMPLE123');
      expect(app.iconBytes, [137, 80, 78, 71]);
    });

    test('returns null for missing or inaccessible apps', () async {
      expect(
        await FlutterDeviceAppsMacos.getApp(appPath: '/Missing.app'),
        isNull,
      );
    });

    test('rejects invalid targets before invoking native code', () async {
      final targets = <({String? bundleIdentifier, String? appPath})>[
        (bundleIdentifier: null, appPath: null),
        (bundleIdentifier: 'com.example.app', appPath: '/Applications/App.app'),
        (bundleIdentifier: '', appPath: null),
        (bundleIdentifier: ' \n ', appPath: null),
        (bundleIdentifier: 'com.example.\u0000app', appPath: null),
        (bundleIdentifier: null, appPath: ''),
        (bundleIdentifier: null, appPath: 'App.app'),
        (bundleIdentifier: null, appPath: '~/Applications/App.app'),
        (bundleIdentifier: null, appPath: 'file:///Applications/App.app'),
        (bundleIdentifier: null, appPath: '/Applications/App.app\u0000'),
      ];
      for (final target in targets) {
        await expectLater(
          FlutterDeviceAppsMacos.getApp(
            bundleIdentifier: target.bundleIdentifier,
            appPath: target.appPath,
          ),
          throwsArgumentError,
        );
      }
      expect(calls, isEmpty);
    });

    test(
      'propagates unexpected lookup failures instead of returning null',
      () async {
        error = PlatformException(code: 'ERR_GET', message: 'Lookup failed');
        await expectLater(
          FlutterDeviceAppsMacos.getApp(bundleIdentifier: 'com.example.app'),
          throwsA(
            isA<PlatformException>().having((e) => e.code, 'code', 'ERR_GET'),
          ),
        );
      },
    );
  });

  group('getApps', () {
    test('sends an ordered batch and metadata options in one call', () async {
      const targets = [
        'com.example.editor',
        '/Applications/Editor Copy.app',
        'com.example.missing',
        'com.example.editor',
      ];
      response = [
        {'appPath': '/Applications/Editor.app', 'bundleSizeBytes': 2048},
        {'appPath': '/Applications/Editor Copy.app', 'bundleSizeBytes': 4096},
      ];

      final apps = await FlutterDeviceAppsMacos.getApps(
        targets,
        includeIcons: true,
        includeArchitectures: true,
        includeSize: true,
        includeSigningInfo: true,
      );

      expect(calls.single.method, 'getApps');
      expect(calls.single.arguments, {
        'targets': targets,
        'includeIcons': true,
        'includeArchitectures': true,
        'includeSize': true,
        'includeSigningInfo': true,
      });
      expect(apps.map((app) => app.appPath), [
        '/Applications/Editor.app',
        '/Applications/Editor Copy.app',
      ]);
      expect(apps.map((app) => app.bundleSizeBytes), [2048, 4096]);
    });

    test('handles empty input and rejects malformed targets in Dart', () async {
      expect(await FlutterDeviceAppsMacos.getApps([]), isEmpty);
      for (final target in [
        '',
        ' ',
        'com.example.\u0000app',
        'Folder/App.app',
        'file:///Apps/App.app',
      ]) {
        await expectLater(
          FlutterDeviceAppsMacos.getApps(['com.example.valid', target]),
          throwsArgumentError,
        );
      }
      expect(calls, isEmpty);
    });

    test('propagates unexpected native batch failures', () async {
      error = PlatformException(code: 'ERR_GET_APPS');
      await expectLater(
        FlutterDeviceAppsMacos.getApps(['com.example.editor']),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'ERR_GET_APPS',
          ),
        ),
      );
    });
  });

  group('MacosAppInfo', () {
    test(
      'keeps unavailable metadata null and protects the architecture list',
      () {
        final architectures = <String>['arm64'];
        final app = MacosAppInfo.fromMap({
          'isAgent': false,
          'isBackgroundOnly': true,
          'supportedArchitectures': architectures,
          'bundleSizeBytes': null,
          'teamIdentifier': null,
        });
        architectures.add('x86_64');
        expect(app.isAgent, isFalse);
        expect(app.isBackgroundOnly, isTrue);
        expect(app.supportedArchitectures, ['arm64']);
        expect(app.bundleSizeBytes, isNull);
        expect(app.teamIdentifier, isNull);
        expect(
          () => app.supportedArchitectures!.add('x86_64'),
          throwsUnsupportedError,
        );
      },
    );

    test('keeps absent metadata null', () {
      final app = MacosAppInfo.fromMap({});
      expect(app.bundleIdentifier, isNull);
      expect(app.appName, isNull);
      expect(app.versionName, isNull);
      expect(app.buildNumber, isNull);
      expect(app.appPath, isNull);
      expect(app.executablePath, isNull);
      expect(app.isSystem, isNull);
      expect(app.isAgent, isNull);
      expect(app.isBackgroundOnly, isNull);
      expect(app.category, isNull);
      expect(app.minimumSystemVersion, isNull);
      expect(app.supportedArchitectures, isNull);
      expect(app.bundleSizeBytes, isNull);
      expect(app.teamIdentifier, isNull);
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
