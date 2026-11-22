import CoreServices
import Foundation
import Security

extension MacosAppScanner {
  private static let linkedFrameworks = [
    "AppKit": "appKit",
    "AudioToolbox": "audioToolbox",
    "AVFoundation": "avFoundation",
    "AVKit": "avKit",
    "Chromium Embedded Framework": "chromiumEmbeddedFramework",
    "Cocoa": "cocoa",
    "Combine": "combine",
    "CoreAudio": "coreAudio",
    "CoreData": "coreData",
    "CoreGraphics": "coreGraphics",
    "CoreMedia": "coreMedia",
    "CoreML": "coreML",
    "Electron Framework": "electron",
    "FlutterMacOS": "flutter",
    "JavaScriptCore": "javaScriptCore",
    "Metal": "metal",
    "MetalKit": "metalKit",
    "OpenGL": "openGL",
    "Python": "pythonRuntime",
    "QtCore": "qt",
    "QtQuick": "qtQuick",
    "QtWidgets": "qtWidgets",
    "QuartzCore": "quartzCore",
    "RealityKit": "realityKit",
    "SceneKit": "sceneKit",
    "SDL2": "sdl2",
    "SDL3": "sdl3",
    "SpriteKit": "spriteKit",
    "SwiftData": "swiftData",
    "SwiftUI": "swiftUI",
    "UIKit": "uiKit",
    "WebKit": "webKit",
  ]

  private static let linkedDylibs = [
    "libcoreclr": "dotnetRuntime",
    "libjvm": "javaRuntime",
    "libmonobdwgc-2": "monoRuntime",
    "libmonosgen-2": "monoRuntime",
    "libpython": "pythonRuntime",
    "libpython2": "pythonRuntime",
    "libpython3": "pythonRuntime",
    "libSDL2": "sdl2",
    "libSDL2-2": "sdl2",
    "libSDL3": "sdl3",
    "libvlc": "libVlc",
    "UnityPlayer": "unity",
  ]

  func detectAppTechnologies(
    target: AppLookupTarget, includeAdditionalTechnologies: Bool
  ) throws -> [String]? {
    guard let (app, info) = try resolveApp(target: target) else { return nil }
    var indicators = [
      ("flutter", ["Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS"]),
      ("electron", ["Contents/Frameworks/Electron Framework.framework/Electron Framework"]),
      ("qt", ["Contents/Frameworks/QtCore.framework/QtCore"]),
      ("unity", ["Contents/Frameworks/UnityPlayer.dylib"]),
      ("javaRuntime", [
        "Contents/runtime/Contents/Home/lib/server/libjvm.dylib",
        "Contents/jbr/Contents/Home/lib/server/libjvm.dylib",
      ]),
    ]
    if includeAdditionalTechnologies {
      indicators += [
        ("qtWidgets", ["Contents/Frameworks/QtWidgets.framework/QtWidgets"]),
        ("qtQuick", ["Contents/Frameworks/QtQuick.framework/QtQuick"]),
        ("chromiumEmbeddedFramework", [
          "Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework",
        ]),
      ]
    }
    var matches = indicators.compactMap { name, paths in
      paths.contains { bundleFile($0, in: app) != nil } ? name : nil
    }
    if includeAdditionalTechnologies {
      if let executable = info["CFBundleExecutable"] as? String,
         !executable.isEmpty, !executable.contains("/"),
         hasBundleHeader("Contents/Resources/\(executable).pck", in: app, header: [0x47, 0x44, 0x50, 0x43]) {
        matches.append("godot")
      }
      if hasBundleHeader(
        "Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/kernel_blob.bin",
        in: app, header: [0x90, 0xAB, 0xCD, 0xEF]
      ) || bundleFile("Contents/Frameworks/App.framework/App", in: app)
        .map({ MachOInspector.inspect($0, checkDartAot: true).hasDartAot }) == true {
        matches.append("dart")
      }
      if let executable = executableURL(app, info: info),
         let file = bundleFile(executable, in: app) {
        let metadata = MachOInspector.inspect(file)
        var linked = Set(metadata.dependencies.compactMap(Self.linkedTechnology))
        if metadata.hasSwiftMetadata { linked.insert("swift") }
        if metadata.isMacCatalyst { linked.insert("macCatalyst") }
        matches.append(contentsOf: linked.subtracting(matches).sorted())
      }
    }
    return matches
  }

  func getInstallSourceInfo(target: AppLookupTarget) throws -> [String: Any]? {
    guard let (app, _) = try resolveApp(target: target) else { return nil }
    let receipt = bundleFile("Contents/_MASReceipt/receipt", in: app) != nil
    let quarantine = try? app.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
    return Self.installSourceInfo(hasAppStoreReceipt: receipt, quarantine: quarantine)
  }

  func getDeclaredCapabilities(target: AppLookupTarget) throws -> [String: Any]? {
    guard let (app, info) = try resolveApp(target: target) else { return nil }
    let descriptions = info.filter { $0.key.hasSuffix("UsageDescription") && $0.value is String }
    var result: [String: Any] = ["usageDescriptions": descriptions]

    if let signing = Self.signingInformation(app, flags: kSecCSRequirementInformation),
       signing[kSecCodeInfoIdentifier as String] != nil {
      if let entitlements = signing[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
        result["entitlements"] = entitlements
      } else if signing[kSecCodeInfoEntitlements as String] == nil {
        result["entitlements"] = [String: Any]()
      }
    }
    return result
  }

  static func installSourceInfo(
    hasAppStoreReceipt: Bool, quarantine: [String: Any]?
  ) -> [String: Any] {
    let quarantineType = quarantine?[kLSQuarantineTypeKey as String] as? String
    let source: String
    if hasAppStoreReceipt {
      source = "macAppStore"
    } else if quarantineType == kLSQuarantineTypeWebDownload as String {
      source = "webDownload"
    } else {
      source = "unknown"
    }
    var result: [String: Any] = ["source": source, "hasAppStoreReceipt": hasAppStoreReceipt]
    result["quarantineAgentName"] = quarantine?[kLSQuarantineAgentNameKey as String] as? String
    result["quarantineAgentBundleIdentifier"] =
      quarantine?[kLSQuarantineAgentBundleIdentifierKey as String] as? String
    return result
  }

  private static func linkedTechnology(_ dependency: String) -> String? {
    let components = dependency.split(separator: "/")
    guard let binary = components.last else { return nil }
    if components.dropLast().contains("\(binary).framework") {
      return linkedFrameworks[String(binary)]
    }
    guard binary.hasSuffix(".dylib") else { return nil }
    let parts = binary.dropLast(".dylib".count).split(separator: ".", omittingEmptySubsequences: false)
    let versionCount = parts.reversed().prefix { part in
      !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) }
    }.count
    return linkedDylibs[parts.dropLast(versionCount).joined(separator: ".")]
  }

  private func bundleFile(_ path: String, in app: URL) -> URL? {
    bundleFile(app.appendingPathComponent(path), in: app)
  }

  private func bundleFile(_ candidate: URL, in app: URL) -> URL? {
    let file = candidate.resolvingSymlinksInPath().standardizedFileURL
    guard file.path.hasPrefix(app.path + "/"),
          (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
    return file
  }

  private func hasBundleHeader(_ path: String, in app: URL, header: [UInt8]) -> Bool {
    guard let file = bundleFile(path, in: app),
          let handle = try? FileHandle(forReadingFrom: file) else { return false }
    defer { try? handle.close() }
    guard let bytes = try? handle.read(upToCount: 8), bytes.count == 8 else { return false }
    return bytes.starts(with: header)
  }
}
