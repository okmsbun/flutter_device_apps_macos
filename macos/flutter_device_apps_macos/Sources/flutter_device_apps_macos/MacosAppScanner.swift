import AppKit
import CoreFoundation
import Foundation
import MachO
import Security

struct AppMethodArguments {
  let values: [String: Any]

  init(_ arguments: Any?, method: String) throws {
    if arguments == nil {
      values = [:]
    } else if let map = arguments as? [String: Any] {
      values = map
    } else {
      throw AppScanError.invalidArgument("\(method) arguments must be a map")
    }
  }

  func boolean(_ key: String, default fallback: Bool = false) throws -> Bool {
    guard let value = values[key], !(value is NSNull) else { return fallback }
    guard let number = value as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() else {
      throw AppScanError.invalidArgument("\(key) must be a boolean")
    }
    return number.boolValue
  }

  func string(_ key: String) throws -> String? {
    guard let value = values[key], !(value is NSNull) else { return nil }
    guard let text = value as? String else {
      throw AppScanError.invalidArgument("\(key) must be a string")
    }
    return text
  }

  func lookupTarget() throws -> AppLookupTarget {
    try AppLookupTarget(
      bundleIdentifier: string("bundleIdentifier"), appPath: string("appPath")
    )
  }

  func lookupOptions(iconKey: String) throws -> AppListOptions {
    try AppListOptions(
      includeSystem: true, onlyLaunchable: false,
      includeIcons: boolean(iconKey),
      includeArchitectures: boolean("includeArchitectures"),
      includeSize: boolean("includeSize"),
      includeSigningInfo: boolean("includeSigningInfo")
    )
  }
}

struct AppListOptions {
  var includeSystem = false
  var onlyLaunchable = true
  var includeIcons = false
  var includeArchitectures = false
  var includeSize = false
  var includeSigningInfo = false
  var bundleIdentifierPrefix: String?
  var bundleIdentifierContains: String?

  init(
    includeSystem: Bool = false,
    onlyLaunchable: Bool = true,
    includeIcons: Bool = false,
    includeArchitectures: Bool = false,
    includeSize: Bool = false,
    includeSigningInfo: Bool = false,
    bundleIdentifierPrefix: String? = nil,
    bundleIdentifierContains: String? = nil
  ) {
    self.includeSystem = includeSystem
    self.onlyLaunchable = onlyLaunchable
    self.includeIcons = includeIcons
    self.includeArchitectures = includeArchitectures
    self.includeSize = includeSize
    self.includeSigningInfo = includeSigningInfo
    self.bundleIdentifierPrefix = bundleIdentifierPrefix
    self.bundleIdentifierContains = bundleIdentifierContains
  }

  init(arguments: Any?) throws {
    let values = try AppMethodArguments(arguments, method: "listApps")
    try self.init(
      includeSystem: values.boolean("includeSystem"),
      onlyLaunchable: values.boolean("onlyLaunchable", default: true),
      includeIcons: values.boolean("includeIcons"),
      includeArchitectures: values.boolean("includeArchitectures"),
      includeSize: values.boolean("includeSize"),
      includeSigningInfo: values.boolean("includeSigningInfo"),
      bundleIdentifierPrefix: values.string("bundleIdentifierPrefix"),
      bundleIdentifierContains: values.string("bundleIdentifierContains")
    )
  }

  func matches(bundleIdentifier: String?) -> Bool {
    if let prefix = bundleIdentifierPrefix, !prefix.isEmpty,
       !(bundleIdentifier?.hasPrefix(prefix) ?? false) { return false }
    if let contains = bundleIdentifierContains, !contains.isEmpty,
       !(bundleIdentifier?.contains(contains) ?? false) { return false }
    return true
  }
}

enum AppLookupTarget {
  case bundleIdentifier(String)
  case appPath(String)

  init(bundleIdentifier: String?, appPath: String?) throws {
    guard (bundleIdentifier == nil) != (appPath == nil) else {
      throw AppScanError.invalidArgument("Provide exactly one of bundleIdentifier or appPath")
    }
    let value = bundleIdentifier ?? appPath!
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !value.contains("\0") else {
      throw AppScanError.invalidArgument("The lookup target must be non-empty and contain no NUL")
    }
    if let path = appPath {
      guard path.hasPrefix("/") else {
        throw AppScanError.invalidArgument("appPath must be an absolute filesystem path")
      }
      self = .appPath(path)
    } else {
      self = .bundleIdentifier(value)
    }
  }
}

struct AppLookupRequest {
  let target: AppLookupTarget
  let options: AppListOptions

  init(arguments: Any?) throws {
    let values = try AppMethodArguments(arguments, method: "getApp")
    target = try values.lookupTarget()
    options = try values.lookupOptions(iconKey: "includeIcon")
  }
}

struct AppBatchLookupRequest {
  let targets: [AppLookupTarget]
  let options: AppListOptions

  init(arguments: Any?) throws {
    let parsed = try AppMethodArguments(arguments, method: "getApps")
    guard let entries = parsed.values["targets"] as? [String] else {
      throw AppScanError.invalidArgument("targets must be a list of strings")
    }
    targets = try entries.map { entry in
      let isPath = entry.hasPrefix("/")
      guard isPath || !entry.contains("/") else {
        throw AppScanError.invalidArgument("targets must be bundle identifiers or absolute app paths")
      }
      return try AppLookupTarget(
        bundleIdentifier: isPath ? nil : entry, appPath: isPath ? entry : nil
      )
    }
    options = try parsed.lookupOptions(iconKey: "includeIcons")
  }
}

enum AppScanError: LocalizedError {
  case invalidArgument(String)
  case inaccessibleDirectories

  var errorDescription: String? {
    switch self {
    case .invalidArgument(let message): return message
    case .inaccessibleDirectories:
      return "No existing application directory could be read. Check App Sandbox and file access."
    }
  }
}

struct AppSearchDirectory {
  let url: URL
  var isSystem = false
}

final class MacosAppScanner {
  private let searchDirectories: [AppSearchDirectory]
  private let fileManager: FileManager
  private let iconProvider: (URL) -> Data?
  private let architectureProvider: (URL) -> [String]?
  private let sizeProvider: (URL) -> Int64?
  private let teamIdentifierProvider: (URL) -> String?
  private let applicationResolver: (String) throws -> URL?

  init(
    searchDirectories: [AppSearchDirectory] = MacosAppScanner.standardDirectories,
    fileManager: FileManager = .default,
    iconProvider: @escaping (URL) -> Data? = MacosAppScanner.pngIcon,
    architectureProvider: @escaping (URL) -> [String]? = MacosAppScanner.executableArchitectures,
    sizeProvider: ((URL) -> Int64?)? = nil,
    teamIdentifierProvider: @escaping (URL) -> String? = MacosAppScanner.teamIdentifier,
    applicationResolver: @escaping (String) throws -> URL? = {
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
    }
  ) {
    self.searchDirectories = searchDirectories
    self.fileManager = fileManager
    self.iconProvider = iconProvider
    self.architectureProvider = architectureProvider
    self.sizeProvider = sizeProvider ?? { MacosAppScanner.logicalBundleSize($0, fileManager: fileManager) }
    self.teamIdentifierProvider = teamIdentifierProvider
    self.applicationResolver = applicationResolver
  }

  static var standardDirectories: [AppSearchDirectory] {
    var directories = [AppSearchDirectory(url: URL(fileURLWithPath: "/Applications"))]
    // homeDirectoryForCurrentUser can point to the container in a sandboxed host.
    if let home = NSHomeDirectoryForUser(NSUserName()) {
      directories.append(AppSearchDirectory(
        url: URL(fileURLWithPath: home).appendingPathComponent("Applications", isDirectory: true)
      ))
    }
    directories.append(contentsOf: [
      AppSearchDirectory(url: URL(fileURLWithPath: "/System/Applications"), isSystem: true),
      AppSearchDirectory(url: URL(fileURLWithPath: "/System/Library/CoreServices"), isSystem: true),
    ])
    return directories
  }

  func listApps(options: AppListOptions) throws -> [[String: Any]] {
    var apps: [[String: Any]] = []
    var visitedPaths = Set<String>()
    var readableDirectories = 0
    var failedDirectories = 0

    for directory in searchDirectories {
      if directory.isSystem && !options.includeSystem { continue }
      let root = directory.url.resolvingSymlinksInPath().standardizedFileURL
      do {
        // Preflight root access: an empty readable directory is a valid result.
        _ = try fileManager.contentsOfDirectory(
          at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
      } catch let error as CocoaError where error.code == .fileReadNoSuchFile
          || error.code == .fileNoSuchFile {
        continue
      } catch {
        failedDirectories += 1
        continue
      }
      readableDirectories += 1
      guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, _ in true }
      ) else { continue }

      for case let entry as URL in enumerator {
        guard entry.pathExtension.lowercased() == "app" else { continue }
        enumerator.skipDescendants()
        let url = entry.resolvingSymlinksInPath().standardizedFileURL
        guard !visitedPaths.contains(url.path),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
          continue
        }
        let isSystem = directory.isSystem || isSystemLocation(url)
        if isSystem && !options.includeSystem { continue }
        guard let info = readInfo(url),
              options.matches(bundleIdentifier: info["CFBundleIdentifier"] as? String) else {
          continue
        }
        let executable = executableURL(url, info: info)
        if options.onlyLaunchable && !canLaunch(executable, info: info) { continue }
        visitedPaths.insert(url.path)
        apps.append(appMap(url, info: info, executable: executable,
                           isSystem: isSystem, options: options))
      }
    }
    if readableDirectories == 0 && failedDirectories > 0 {
      throw AppScanError.inaccessibleDirectories
    }
    return apps.sorted {
      let first = $0["appName"] as? String ?? ""
      let second = $1["appName"] as? String ?? ""
      let order = first.localizedStandardCompare(second)
      if order != .orderedSame { return order == .orderedAscending }
      return ($0["appPath"] as? String ?? "") < ($1["appPath"] as? String ?? "")
    }
  }

  func getApp(target: AppLookupTarget, options: AppListOptions) throws -> [String: Any]? {
    guard let (url, info) = try resolveApp(target: target) else { return nil }
    return lookupMap(url, info: info, options: options)
  }

  func getApps(targets: [AppLookupTarget], options: AppListOptions) throws -> [[String: Any]] {
    var seenPaths = Set<String>()
    return try targets.compactMap { target in
      guard let (url, info) = try resolveApp(target: target),
            seenPaths.insert(url.path).inserted else { return nil }
      return lookupMap(url, info: info, options: options)
    }
  }

  func getAppIcon(target: AppLookupTarget) throws -> Data? {
    guard let (url, _) = try resolveApp(target: target) else { return nil }
    return iconProvider(url)
  }

  func isAppInstalled(target: AppLookupTarget) throws -> Bool {
    try resolveApp(target: target) != nil
  }

  func isSystemApp(target: AppLookupTarget) throws -> Bool? {
    guard let (url, _) = try resolveApp(target: target) else { return nil }
    return isSystemLocation(url)
  }

  func isAppLaunchable(target: AppLookupTarget) throws -> Bool {
    guard let (url, info) = try resolveApp(target: target) else { return false }
    return canLaunch(executableURL(url, info: info), info: info)
  }

  func resolveApp(target: AppLookupTarget) throws -> (URL, [String: Any])? {
    let candidate: URL
    switch target {
    case .appPath(let path):
      candidate = URL(fileURLWithPath: path)
    case .bundleIdentifier(let identifier):
      guard let resolved = try applicationResolver(identifier) else { return nil }
      candidate = resolved
    }
    guard candidate.isFileURL else { return nil }
    let url = candidate.resolvingSymlinksInPath().standardizedFileURL
    guard url.pathExtension.lowercased() == "app",
          (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
          let info = readInfo(url) else { return nil }
    if case .bundleIdentifier(let identifier) = target,
       info["CFBundleIdentifier"] as? String != identifier { return nil }
    return (url, info)
  }

  private func lookupMap(_ url: URL, info: [String: Any], options: AppListOptions) -> [String: Any] {
    return appMap(
      url, info: info, executable: executableURL(url, info: info),
      isSystem: isSystemLocation(url), options: options
    )
  }

  private func isSystemLocation(_ url: URL) -> Bool {
    let path = url.path
    // Includes system apps reached through symlinks, such as Safari in Cryptexes.
    // The writable Data volume can contain ordinary third-party applications.
    if path.hasPrefix("/System/") && !path.hasPrefix("/System/Volumes/Data/") {
      return true
    }
    return searchDirectories.contains { directory in
      guard directory.isSystem else { return false }
      let root = directory.url.resolvingSymlinksInPath().standardizedFileURL.path
      return path == root || path.hasPrefix(root + "/")
    }
  }

  private func readInfo(_ url: URL) -> [String: Any]? {
    let infoURL = url.appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: infoURL),
          let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let info = value as? [String: Any] else { return nil }
    if let type = info["CFBundlePackageType"] as? String, type != "APPL" { return nil }
    return info
  }

  private func executableURL(_ url: URL, info: [String: Any]) -> URL? {
    guard let name = info["CFBundleExecutable"] as? String,
          !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return nil }
    return url.appendingPathComponent("Contents/MacOS", isDirectory: true)
      .appendingPathComponent(name)
  }

  private func canLaunch(_ executable: URL?, info: [String: Any]) -> Bool {
    guard let executable = executable else { return false }
    return fileManager.isExecutableFile(atPath: executable.path)
      && (try? executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      && !plistBoolean(info["LSBackgroundOnly"])
      && !plistBoolean(info["LSUIElement"])
  }

  private func plistBoolean(_ value: Any?) -> Bool {
    if let number = value as? NSNumber { return number.boolValue }
    if let text = value as? NSString { return text.boolValue }
    return false
  }

  private func appMap(
    _ url: URL, info: [String: Any], executable: URL?, isSystem: Bool, options: AppListOptions
  ) -> [String: Any] {
    let localized = Bundle(url: url)?.localizedInfoDictionary ?? [:]
    let name = (localized["CFBundleDisplayName"] as? String)
      ?? (info["CFBundleDisplayName"] as? String)
      ?? (localized["CFBundleName"] as? String)
      ?? (info["CFBundleName"] as? String)
      ?? url.deletingPathExtension().lastPathComponent
    return [
      "bundleIdentifier": info["CFBundleIdentifier"] as? String ?? NSNull(),
      "appName": name,
      "versionName": info["CFBundleShortVersionString"] as? String ?? NSNull(),
      "buildNumber": (info["CFBundleVersion"].map { String(describing: $0) }) ?? NSNull(),
      "appPath": url.path,
      "executablePath": executable?.path ?? NSNull(),
      "isSystem": isSystem,
      "isAgent": plistBoolean(info["LSUIElement"]),
      "isBackgroundOnly": plistBoolean(info["LSBackgroundOnly"]),
      "category": info["LSApplicationCategoryType"] as? String ?? NSNull(),
      "minimumSystemVersion": info["LSMinimumSystemVersion"] as? String ?? NSNull(),
      "supportedArchitectures": (options.includeArchitectures ? architectureProvider(url) : nil) ?? NSNull(),
      "bundleSizeBytes": (options.includeSize ? sizeProvider(url) : nil) ?? NSNull(),
      "teamIdentifier": (options.includeSigningInfo ? teamIdentifierProvider(url) : nil) ?? NSNull(),
      "iconBytes": (options.includeIcons ? iconProvider(url) : nil) ?? NSNull(),
    ]
  }

  private static func executableArchitectures(_ url: URL) -> [String]? {
    guard let values = Bundle(url: url)?.executableArchitectures, !values.isEmpty else { return nil }
    let architectures = values.map { value -> String in
      switch value.int32Value {
      case CPU_TYPE_ARM64: return "arm64"
      case CPU_TYPE_X86_64: return "x86_64"
      case CPU_TYPE_I386: return "i386"
      case CPU_TYPE_ARM: return "arm"
      case CPU_TYPE_POWERPC: return "ppc"
      case CPU_TYPE_POWERPC64: return "ppc64"
      default: return "cpu-\(value.int32Value)"
      }
    }
    return Array(Set(architectures)).sorted()
  }

  private static func logicalBundleSize(_ url: URL, fileManager: FileManager) -> Int64? {
    var failed = false
    guard let enumerator = fileManager.enumerator(
      at: url,
      includingPropertiesForKeys: [.isSymbolicLinkKey],
      options: [],
      errorHandler: { _, _ in
        failed = true
        return false
      }
    ) else { return nil }
    var total: Int64 = 0
    do {
      for case let entry as URL in enumerator {
        let link = try entry.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard let isLink = link.isSymbolicLink else { return nil }
        if isLink { continue }
        let values = try entry.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard let isRegularFile = values.isRegularFile else { return nil }
        if !isRegularFile { continue }
        guard let size = values.fileSize, size >= 0 else { return nil }
        let sum = total.addingReportingOverflow(Int64(size))
        guard !sum.overflow else { return nil }
        total = sum.partialValue
      }
    } catch {
      return nil
    }
    return failed ? nil : total
  }

  private static func teamIdentifier(_ url: URL) -> String? {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess,
          let code = code else { return nil }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(
      code, SecCSFlags(rawValue: kSecCSSigningInformation), &information
    ) == errSecSuccess,
    let fields = information as? [String: Any],
    let team = fields[kSecCodeInfoTeamIdentifier as String] as? String,
    !team.isEmpty else { return nil }
    return team
  }

  private static func pngIcon(_ url: URL) -> Data? {
    let image = NSWorkspace.shared.icon(forFile: url.path)
    let size = NSSize(width: 64, height: 64)
    guard let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
  }
}
