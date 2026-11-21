import CoreServices
import Foundation

extension MacosAppScanner {
  func detectAppFrameworks(target: AppLookupTarget) throws -> [String]? {
    guard let (app, _) = try resolveApp(target: target) else { return nil }
    let indicators = [
      ("flutter", "FlutterMacOS.framework/FlutterMacOS"),
      ("electron", "Electron Framework.framework/Electron Framework"),
      ("qt", "QtCore.framework/QtCore"),
    ]
    return indicators.compactMap { name, path in
      hasBundleFile("Contents/Frameworks/" + path, in: app) ? name : nil
    }
  }

  func getInstallSourceInfo(target: AppLookupTarget) throws -> [String: Any]? {
    guard let (app, _) = try resolveApp(target: target) else { return nil }
    let receipt = hasBundleFile("Contents/_MASReceipt/receipt", in: app)
    let quarantine = try? app.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
    return Self.installSourceInfo(hasAppStoreReceipt: receipt, quarantine: quarantine)
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
