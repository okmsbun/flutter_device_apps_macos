import AppKit
import CoreFoundation
import Foundation

struct AppListOptions {
  var includeSystem = false
  var onlyLaunchable = true
  var includeIcons = false
  var bundleIdentifierPrefix: String?
  var bundleIdentifierContains: String?

  init(
    includeSystem: Bool = false,
    onlyLaunchable: Bool = true,
    includeIcons: Bool = false,
    bundleIdentifierPrefix: String? = nil,
    bundleIdentifierContains: String? = nil
  ) {
    self.includeSystem = includeSystem
    self.onlyLaunchable = onlyLaunchable
    self.includeIcons = includeIcons
    self.bundleIdentifierPrefix = bundleIdentifierPrefix
    self.bundleIdentifierContains = bundleIdentifierContains
  }

  init(arguments: Any?) throws {
    let map: [String: Any]
    if arguments == nil {
      map = [:]
    } else if let value = arguments as? [String: Any] {
      map = value
    } else {
      throw AppScanError.invalidArgument("listApps arguments must be a map")
    }
    func boolean(_ key: String, default fallback: Bool) throws -> Bool {
      guard let value = map[key], !(value is NSNull) else { return fallback }
      guard let number = value as? NSNumber,
            CFGetTypeID(number) == CFBooleanGetTypeID() else {
        throw AppScanError.invalidArgument("\(key) must be a boolean")
      }
      return number.boolValue
    }
    func string(_ key: String) throws -> String? {
      guard let value = map[key], !(value is NSNull) else { return nil }
      guard let text = value as? String else {
        throw AppScanError.invalidArgument("\(key) must be a string")
      }
      return text
    }
    try self.init(
      includeSystem: boolean("includeSystem", default: false),
      onlyLaunchable: boolean("onlyLaunchable", default: true),
      includeIcons: boolean("includeIcons", default: false),
      bundleIdentifierPrefix: string("bundleIdentifierPrefix"),
      bundleIdentifierContains: string("bundleIdentifierContains")
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

  init(
    searchDirectories: [AppSearchDirectory] = MacosAppScanner.standardDirectories,
    fileManager: FileManager = .default,
    iconProvider: @escaping (URL) -> Data? = MacosAppScanner.pngIcon
  ) {
    self.searchDirectories = searchDirectories
    self.fileManager = fileManager
    self.iconProvider = iconProvider
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
        if options.onlyLaunchable {
          guard let executable = executable,
                fileManager.isExecutableFile(atPath: executable.path),
                (try? executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                !plistBoolean(info["LSBackgroundOnly"]),
                !plistBoolean(info["LSUIElement"]) else { continue }
        }
        visitedPaths.insert(url.path)
        apps.append(appMap(url, info: info, executable: executable,
                           isSystem: isSystem, includeIcon: options.includeIcons))
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

  private func plistBoolean(_ value: Any?) -> Bool {
    if let number = value as? NSNumber { return number.boolValue }
    if let text = value as? NSString { return text.boolValue }
    return false
  }

  private func appMap(
    _ url: URL, info: [String: Any], executable: URL?, isSystem: Bool, includeIcon: Bool
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
      "category": info["LSApplicationCategoryType"] as? String ?? NSNull(),
      "minimumSystemVersion": info["LSMinimumSystemVersion"] as? String ?? NSNull(),
      "iconBytes": (includeIcon ? iconProvider(url) : nil) ?? NSNull(),
    ]
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
