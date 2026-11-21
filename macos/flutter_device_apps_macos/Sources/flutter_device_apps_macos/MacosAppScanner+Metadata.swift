import CoreServices
import Foundation
import Security

extension MacosAppScanner {
  func detectAppFrameworks(target: AppLookupTarget) throws -> [String]? {
    guard let (app, _) = try resolveApp(target: target) else { return nil }
    let indicators = [
      ("flutter", ["Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS"]),
      ("electron", ["Contents/Frameworks/Electron Framework.framework/Electron Framework"]),
      ("qt", ["Contents/Frameworks/QtCore.framework/QtCore"]),
      ("unity", ["Contents/Frameworks/UnityPlayer.dylib"]),
      ("javaRuntime", [
        "Contents/runtime/Contents/Home/lib/server/libjvm.dylib",
        "Contents/jbr/Contents/Home/lib/server/libjvm.dylib",
      ]),
    ]
    return indicators.compactMap { name, paths in
      paths.contains { hasBundleFile($0, in: app) } ? name : nil
    }
  }

  func getInstallSourceInfo(target: AppLookupTarget) throws -> [String: Any]? {
    guard let (app, _) = try resolveApp(target: target) else { return nil }
    let receipt = hasBundleFile("Contents/_MASReceipt/receipt", in: app)
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

  private func hasBundleFile(_ path: String, in app: URL) -> Bool {
    let file = app.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
    return file.path.hasPrefix(app.path + "/")
      && (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
  }
}
