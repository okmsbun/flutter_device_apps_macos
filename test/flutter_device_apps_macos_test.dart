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
        'includeSpotlight': false,
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
          includeSpotlight: true,
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
          'includeSpotlight': true,
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

  group('getAppIcon', () {
    test(
      'returns native icon bytes or null through a single request',
      () async {
        final icon = Uint8List.fromList([137, 80, 78, 71]);
        response = icon;
        expect(
          await FlutterDeviceAppsMacos.getAppIcon(
            bundleIdentifier: 'com.example.editor',
          ),
          icon,
        );
        expect(calls.single.method, 'getAppIcon');
        expect(calls.single.arguments, {
          'bundleIdentifier': 'com.example.editor',
          'appPath': null,
        });

        calls.clear();
        response = null;
        expect(
          await FlutterDeviceAppsMacos.getAppIcon(appPath: '/Missing.app'),
          isNull,
        );
        expect(calls.single.method, 'getAppIcon');
        expect(calls.single.arguments, {
          'bundleIdentifier': null,
          'appPath': '/Missing.app',
        });
      },
    );

    test('rejects missing, conflicting, and relative targets', () async {
      await expectLater(
        FlutterDeviceAppsMacos.getAppIcon(),
        throwsArgumentError,
      );
      await expectLater(
        FlutterDeviceAppsMacos.getAppIcon(
          bundleIdentifier: 'com.example.editor',
          appPath: '/Applications/Editor.app',
        ),
        throwsArgumentError,
      );
      await expectLater(
        FlutterDeviceAppsMacos.getAppIcon(appPath: 'Editor.app'),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });
  });

  group('app status checks', () {
    test('forwards the exact targets and preserves status responses', () async {
      response = true;
      expect(
        await FlutterDeviceAppsMacos.isAppInstalled(
          bundleIdentifier: 'com.example.app',
        ),
        isTrue,
      );

      response = null;
      expect(
        await FlutterDeviceAppsMacos.isSystemApp(appPath: '/Missing.app'),
        isNull,
      );

      response = false;
      expect(
        await FlutterDeviceAppsMacos.isAppLaunchable(
          appPath: '/Applications/Agent.app',
        ),
        isFalse,
      );

      expect(calls.map((call) => call.method), [
        'isAppInstalled',
        'isSystemApp',
        'isAppLaunchable',
      ]);
      expect(calls.map((call) => call.arguments), [
        {'bundleIdentifier': 'com.example.app', 'appPath': null},
        {'bundleIdentifier': null, 'appPath': '/Missing.app'},
        {'bundleIdentifier': null, 'appPath': '/Applications/Agent.app'},
      ]);
    });

    test(
      'validates targets and propagates unexpected query failures',
      () async {
        await expectLater(
          FlutterDeviceAppsMacos.isAppInstalled(),
          throwsArgumentError,
        );
        await expectLater(
          FlutterDeviceAppsMacos.isSystemApp(appPath: 'App.app'),
          throwsArgumentError,
        );
        await expectLater(
          FlutterDeviceAppsMacos.isAppLaunchable(
            bundleIdentifier: 'com.example.app',
            appPath: '/Applications/App.app',
          ),
          throwsArgumentError,
        );
        expect(calls, isEmpty);

        error = PlatformException(code: 'ERR_QUERY');
        await expectLater(
          FlutterDeviceAppsMacos.isAppLaunchable(
            bundleIdentifier: 'com.example.app',
          ),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'ERR_QUERY',
            ),
          ),
        );
      },
    );
  });

  test(
    'listRunningApps preserves multiple instances and optional fields',
    () async {
      response = [
        {
          'appName': 'Editor',
          'bundleIdentifier': 'com.example.editor',
          'appPath': '/Applications/Editor.app',
          'processIdentifier': 100,
          'isActive': true,
        },
        {
          'bundleIdentifier': 'com.example.editor',
          'processIdentifier': 101,
          'isActive': false,
        },
        {'isActive': false},
      ];
      final apps = await FlutterDeviceAppsMacos.listRunningApps();
      expect(calls.single.method, 'listRunningApps');
      expect(calls.single.arguments, isNull);
      expect(apps.map((app) => app.processIdentifier), [100, 101, null]);
      expect(apps.take(2).map((app) => app.bundleIdentifier), [
        'com.example.editor',
        'com.example.editor',
      ]);
      expect(apps.first.appName, 'Editor');
      expect(apps.first.appPath, '/Applications/Editor.app');
      expect(apps.first.isActive, isTrue);
      expect(apps.last.appName, isNull);
      expect(apps.last.appPath, isNull);
      expect(apps.last.isActive, isFalse);
    },
  );

  test(
    'getDefaultAppForFile forwards a file path and decodes the handler',
    () async {
      const path = '/Users/test/My Document.pdf';
      response = {
        'appName': 'PDF Reader',
        'bundleIdentifier': 'com.example.reader',
        'appPath': '/Applications/PDF Reader.app',
      };
      final app = await FlutterDeviceAppsMacos.getDefaultAppForFile(
        filePath: path,
      );
      expect(calls.single.method, 'getDefaultAppForFile');
      expect(calls.single.arguments, {'filePath': path});
      expect(app?.appName, 'PDF Reader');
      expect(app?.appPath, '/Applications/PDF Reader.app');

      response = null;
      expect(
        await FlutterDeviceAppsMacos.getDefaultAppForFile(filePath: path),
        isNull,
      );
      await expectLater(
        FlutterDeviceAppsMacos.getDefaultAppForFile(filePath: 'document.pdf'),
        throwsArgumentError,
      );
      expect(calls, hasLength(2));
    },
  );

  group('app search folders', () {
    test('adds, lists, and removes folders by their stable IDs', () async {
      const folder = {'id': 'folder-id', 'path': '/Volumes/Work/Apps'};
      response = folder;

      final added = await FlutterDeviceAppsMacos.addAppSearchFolder();
      expect(added?.id, folder['id']);
      expect(added?.path, folder['path']);

      response = [folder];
      final folders = await FlutterDeviceAppsMacos.listAppSearchFolders();
      expect(folders.single.id, added?.id);
      expect(folders.single.path, added?.path);

      response = null;
      await FlutterDeviceAppsMacos.removeAppSearchFolder(id: folders.single.id);
      expect(calls.map((call) => call.method), [
        'addAppSearchFolder',
        'listAppSearchFolders',
        'removeAppSearchFolder',
      ]);
      expect(calls.last.arguments, {'id': folder['id']});
    });

    test('preserves cancellation and rejects empty folder IDs', () async {
      response = null;
      expect(await FlutterDeviceAppsMacos.addAppSearchFolder(), isNull);
      expect(await FlutterDeviceAppsMacos.listAppSearchFolders(), isEmpty);
      await expectLater(
        FlutterDeviceAppsMacos.removeAppSearchFolder(id: ' '),
        throwsArgumentError,
      );
      expect(calls, hasLength(2));
    });
  });

  group('app inspection', () {
    test(
      'decodes declared capabilities and preserves nested entitlement values',
      () async {
        const bundle = 'com.example.camera';
        const camera = 'NSCameraUsageDescription';
        response = {
          'usageDescriptions': {camera: 'Capture a photo'},
          'entitlements': {
            'com.apple.security.device.camera': true,
            'example.array': ['com.example.service'],
            'example.dictionary': {'active': false},
            'example.data': Uint8List.fromList([1, 2]),
          },
        };
        final capabilities =
            (await FlutterDeviceAppsMacos.getDeclaredCapabilities(
              bundleIdentifier: bundle,
            ))!;

        expect(calls.single.method, 'getDeclaredCapabilities');
        expect(calls.single.arguments, {
          'bundleIdentifier': bundle,
          'appPath': null,
        });
        expect(capabilities.usageDescriptions, {camera: 'Capture a photo'});
        final entitlements = capabilities.entitlements!;
        expect(entitlements['com.apple.security.device.camera'], isTrue);
        final list = entitlements['example.array'] as List<Object?>;
        final dictionary =
            entitlements['example.dictionary'] as Map<String, Object?>;
        final bytes = entitlements['example.data'] as Uint8List;
        expect(list, ['com.example.service']);
        expect(dictionary, {'active': false});
        expect(bytes, [1, 2]);
        expect(capabilities.usageDescriptions.clear, throwsUnsupportedError);
        expect(entitlements.clear, throwsUnsupportedError);
        expect(list.clear, throwsUnsupportedError);
        expect(dictionary.clear, throwsUnsupportedError);
        expect(() => bytes[0] = 3, throwsUnsupportedError);
      },
    );

    test(
      'distinguishes unavailable app, unavailable entitlements, and empty entitlements',
      () async {
        const path = '/Applications/Camera.app';
        response = null;
        expect(
          await FlutterDeviceAppsMacos.getDeclaredCapabilities(appPath: path),
          isNull,
        );
        expect(calls.single.arguments, {
          'bundleIdentifier': null,
          'appPath': path,
        });
        response = {'usageDescriptions': <String, String>{}};
        final unsigned = await FlutterDeviceAppsMacos.getDeclaredCapabilities(
          appPath: path,
        );
        expect(unsigned?.usageDescriptions, isEmpty);
        expect(unsigned?.entitlements, isNull);
        response = {
          'usageDescriptions': <String, String>{},
          'entitlements': <String, Object?>{},
        };
        final signed = await FlutterDeviceAppsMacos.getDeclaredCapabilities(
          appPath: path,
        );
        expect(signed?.entitlements, isEmpty);
        await expectLater(
          FlutterDeviceAppsMacos.getDeclaredCapabilities(appPath: 'Camera.app'),
          throwsArgumentError,
        );
      },
    );

    test(
      'decodes known framework markers and preserves unavailable results',
      () async {
        const path = '/Applications/Editor Copy.app';
        response = ['flutter', 'qt', 'futureFramework', 'flutter'];
        expect(
          await FlutterDeviceAppsMacos.detectAppFrameworks(appPath: path),
          [MacosAppFramework.flutter, MacosAppFramework.qt],
        );
        expect(calls.single.method, 'detectAppFrameworks');
        expect(calls.single.arguments, {
          'bundleIdentifier': null,
          'appPath': path,
        });

        response = <String>[];
        expect(
          await FlutterDeviceAppsMacos.detectAppFrameworks(appPath: path),
          isEmpty,
        );
        response = null;
        expect(
          await FlutterDeviceAppsMacos.detectAppFrameworks(appPath: path),
          isNull,
        );
      },
    );

    test(
      'decodes install source evidence and keeps unknown separate from null',
      () async {
        const bundle = 'com.example.editor';
        response = {
          'source': 'webDownload',
          'hasAppStoreReceipt': false,
          'quarantineAgentName': 'Safari',
          'quarantineAgentBundleIdentifier': 'com.apple.Safari',
        };
        final info = await FlutterDeviceAppsMacos.getInstallSourceInfo(
          bundleIdentifier: bundle,
        );
        expect(calls.single.method, 'getInstallSourceInfo');
        expect(calls.single.arguments, {
          'bundleIdentifier': bundle,
          'appPath': null,
        });
        expect(info?.source, MacosAppInstallSource.webDownload);
        expect(info?.hasAppStoreReceipt, isFalse);
        expect(info?.quarantineAgentName, 'Safari');
        expect(info?.quarantineAgentBundleIdentifier, 'com.apple.Safari');

        response = {'source': 'futureSource'};
        final unknown = await FlutterDeviceAppsMacos.getInstallSourceInfo(
          bundleIdentifier: bundle,
        );
        expect(unknown?.source, MacosAppInstallSource.unknown);
        expect(unknown?.quarantineAgentName, isNull);
        response = null;
        expect(
          await FlutterDeviceAppsMacos.getInstallSourceInfo(
            bundleIdentifier: bundle,
          ),
          isNull,
        );
        await expectLater(
          FlutterDeviceAppsMacos.getInstallSourceInfo(),
          throwsArgumentError,
        );
      },
    );
  });

  group('app actions', () {
    test('sends one request for each action with its exact target', () async {
      response = null;
      const path = '/Applications/Editor Copy.app';

      await FlutterDeviceAppsMacos.openApp(
        bundleIdentifier: 'com.example.editor',
      );
      await FlutterDeviceAppsMacos.revealAppInFinder(appPath: path);
      await FlutterDeviceAppsMacos.moveAppToTrash(appPath: path);

      expect(calls.map((call) => call.method), [
        'openApp',
        'revealAppInFinder',
        'moveAppToTrash',
      ]);
      expect(calls.first.arguments, {
        'bundleIdentifier': 'com.example.editor',
        'appPath': null,
      });
      for (final call in calls.skip(1)) {
        expect(call.arguments, {'bundleIdentifier': null, 'appPath': path});
      }
    });

    test('rejects invalid targets and preserves native failures', () async {
      await expectLater(FlutterDeviceAppsMacos.openApp(), throwsArgumentError);
      await expectLater(
        FlutterDeviceAppsMacos.revealAppInFinder(
          bundleIdentifier: 'com.example.editor',
          appPath: '/Applications/Editor.app',
        ),
        throwsArgumentError,
      );
      await expectLater(
        FlutterDeviceAppsMacos.moveAppToTrash(appPath: 'Editor.app'),
        throwsArgumentError,
      );
      expect(calls, isEmpty);

      const path = '/Applications/Editor.app';
      for (final (invoke, code) in [
        (FlutterDeviceAppsMacos.openApp, 'ERR_OPEN'),
        (FlutterDeviceAppsMacos.revealAppInFinder, 'APP_UNAVAILABLE'),
        (FlutterDeviceAppsMacos.moveAppToTrash, 'ERR_TRASH'),
      ]) {
        error = PlatformException(code: code);
        await expectLater(
          invoke(appPath: path),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
        );
      }
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
