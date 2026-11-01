import AppKit
import FlutterMacOS
import MachO
import XCTest

@testable import flutter_device_apps_macos

class RunnerTests: XCTestCase {
  private let fm = FileManager.default
  private var root: URL!
  private var userApps: URL!
  private var systemApps: URL!

  override func setUpWithError() throws {
    root = fm.temporaryDirectory.appendingPathComponent("device-apps-\(UUID().uuidString)")
    userApps = root.appendingPathComponent("UserApps")
    systemApps = root.appendingPathComponent("SystemApps")
    try fm.createDirectory(at: userApps, withIntermediateDirectories: true)
    try fm.createDirectory(at: systemApps, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try fm.removeItem(at: root)
  }

  private var directories: [AppSearchDirectory] {
    [AppSearchDirectory(url: userApps), AppSearchDirectory(url: systemApps, isSystem: true)]
  }

  @discardableResult
  private func app(
    _ relativePath: String,
    in directory: URL? = nil,
    bundleIdentifier: String? = "com.example.app",
    extra: [String: Any] = [:],
    executable: Bool = true
  ) throws -> URL {
    let url = (directory ?? userApps!).appendingPathComponent(relativePath)
    let macos = url.appendingPathComponent("Contents/MacOS")
    try fm.createDirectory(at: macos, withIntermediateDirectories: true)
    var info: [String: Any] = [
      "CFBundlePackageType": "APPL",
      "CFBundleName": url.deletingPathExtension().lastPathComponent,
      "CFBundleExecutable": "Executable",
      "CFBundleShortVersionString": "2.3.0",
      "CFBundleVersion": "42.1.0",
    ]
    info["CFBundleIdentifier"] = bundleIdentifier
    info.merge(extra) { _, new in new }
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
    if executable {
      let path = macos.appendingPathComponent("Executable")
      try Data("#!/bin/sh\nexit 0\n".utf8).write(to: path)
      try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }
    return url
  }

  private func scan(_ options: AppListOptions = AppListOptions()) throws -> [[String: Any]] {
    try MacosAppScanner(searchDirectories: directories).listApps(options: options)
  }

  func testMetadataAndDefaultSystemExclusion() throws {
    let url = try app("Editor.app", extra: [
      "CFBundleDisplayName": "Example Editor",
      "LSApplicationCategoryType": "public.app-category.developer-tools",
      "LSMinimumSystemVersion": "12.0",
    ])
    try app("System.app", in: systemApps)
    let apps = try scan()
    XCTAssertEqual(apps.count, 1)
    let info = try XCTUnwrap(apps.first)
    XCTAssertEqual(info["appName"] as? String, "Example Editor")
    XCTAssertEqual(info["bundleIdentifier"] as? String, "com.example.app")
    XCTAssertEqual(info["versionName"] as? String, "2.3.0")
    XCTAssertEqual(info["buildNumber"] as? String, "42.1.0")
    XCTAssertEqual(info["appPath"] as? String, url.resolvingSymlinksInPath().path)
    XCTAssertEqual(info["isSystem"] as? Bool, false)
    XCTAssertEqual(info["isAgent"] as? Bool, false)
    XCTAssertEqual(info["isBackgroundOnly"] as? Bool, false)
    XCTAssertTrue(info["supportedArchitectures"] is NSNull)
    XCTAssertTrue(info["bundleSizeBytes"] is NSNull)
    XCTAssertTrue(info["teamIdentifier"] is NSNull)
    XCTAssertEqual(info["category"] as? String, "public.app-category.developer-tools")
    XCTAssertEqual(info["minimumSystemVersion"] as? String, "12.0")
    XCTAssertTrue(info["iconBytes"] is NSNull)
    let all = try scan(AppListOptions(includeSystem: true))
    XCTAssertEqual(all.count, 2)
    XCTAssertEqual(all.filter { $0["isSystem"] as? Bool == true }.count, 1)
  }

  func testCaseSensitiveFiltersUseAndAndEmptyDisablesEach() throws {
    try app("Editor.app", bundleIdentifier: "com.example.Editor")
    try app("Browser.app", bundleIdentifier: "org.example.Editor")
    XCTAssertEqual(try scan(AppListOptions(
      bundleIdentifierPrefix: "com.", bundleIdentifierContains: "Editor"
    )).count, 1)
    XCTAssertTrue(try scan(AppListOptions(bundleIdentifierContains: "editor")).isEmpty)
    XCTAssertEqual(try scan(AppListOptions(
      bundleIdentifierPrefix: "", bundleIdentifierContains: ""
    )).count, 2)
    XCTAssertEqual(try scan(AppListOptions(bundleIdentifierContains: "Editor")).count, 2)
  }

  func testOnlyLaunchableExcludesAgentsBackgroundAndMissingExecutables() throws {
    try app("Normal.app")
    try app("Agent.app", extra: ["LSUIElement": true])
    try app("Background.app", extra: ["LSBackgroundOnly": "YES"])
    try app("NoExecutable.app", executable: false)
    let blocked = try app("NonExecutable.app")
    try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath:
      blocked.appendingPathComponent("Contents/MacOS/Executable").path)
    XCTAssertEqual(try scan().map { $0["appName"] as? String }, ["Normal"])
    XCTAssertEqual(try scan(AppListOptions(onlyLaunchable: false)).count, 5)
  }

  func testAgentAndBackgroundFlagsDescribeBundleDeclarations() throws {
    try app("Agent.app", extra: ["LSUIElement": true])
    try app("Background.app", extra: ["LSBackgroundOnly": "YES"])
    let apps = try scan(AppListOptions(onlyLaunchable: false))
    XCTAssertEqual(apps[0]["isAgent"] as? Bool, true)
    XCTAssertEqual(apps[0]["isBackgroundOnly"] as? Bool, false)
    XCTAssertEqual(apps[1]["isAgent"] as? Bool, false)
    XCTAssertEqual(apps[1]["isBackgroundOnly"] as? Bool, true)
  }

  func testOptionalReadersRunIndependentlyAndAfterFiltering() throws {
    try app("Editor.app", bundleIdentifier: "com.example.editor")
    try app("Browser.app", bundleIdentifier: "org.example.browser")
    var reads: [String] = []
    let scanner = MacosAppScanner(
      searchDirectories: directories,
      architectureProvider: { url in reads.append("arch:\(url.lastPathComponent)"); return ["arm64"] },
      sizeProvider: { url in reads.append("size:\(url.lastPathComponent)"); return 4096 },
      teamIdentifierProvider: { url in reads.append("team:\(url.lastPathComponent)"); return "EXAMPLE123" }
    )
    _ = try scanner.listApps(options: AppListOptions())
    XCTAssertTrue(reads.isEmpty)
    let sizes = try scanner.listApps(options: AppListOptions(
      includeSize: true, bundleIdentifierPrefix: "com."
    ))
    XCTAssertEqual(reads, ["size:Editor.app"])
    XCTAssertEqual(sizes.first?["bundleSizeBytes"] as? Int64, 4096)
    XCTAssertTrue(sizes.first?["supportedArchitectures"] is NSNull)
    XCTAssertTrue(sizes.first?["teamIdentifier"] is NSNull)
    reads.removeAll()
    let all = try scanner.listApps(options: AppListOptions(
      includeArchitectures: true, includeSize: true, includeSigningInfo: true,
      bundleIdentifierPrefix: "com."
    ))
    XCTAssertEqual(reads.sorted(), ["arch:Editor.app", "size:Editor.app", "team:Editor.app"])
    XCTAssertEqual(all.first?["supportedArchitectures"] as? [String], ["arm64"])
    XCTAssertEqual(all.first?["teamIdentifier"] as? String, "EXAMPLE123")
  }

  func testUnavailableOptionalMetadataKeepsTheApp() throws {
    try app("Editor.app")
    let scanner = MacosAppScanner(
      searchDirectories: directories, architectureProvider: { _ in nil },
      sizeProvider: { _ in nil }, teamIdentifierProvider: { _ in nil }
    )
    let apps = try scanner.listApps(options: AppListOptions(
      includeArchitectures: true, includeSize: true, includeSigningInfo: true
    ))
    XCTAssertEqual(apps.count, 1)
    for key in ["supportedArchitectures", "bundleSizeBytes", "teamIdentifier"] {
      XCTAssertTrue(apps[0][key] is NSNull)
    }
  }

  private func machoHeader(cpu: cpu_type_t, subtype: cpu_subtype_t) -> Data {
    var header = mach_header_64(
      magic: MH_MAGIC_64, cputype: cpu, cpusubtype: subtype, filetype: UInt32(MH_EXECUTE),
      ncmds: 0, sizeofcmds: 0, flags: 0, reserved: 0
    )
    return withUnsafeBytes(of: &header) { Data($0) }
  }

  func testReadsArchitectureFromAThinExecutable() throws {
    let url = try app("ArmApp.app")
    try machoHeader(cpu: CPU_TYPE_ARM64, subtype: CPU_SUBTYPE_ARM64_ALL)
      .write(to: url.appendingPathComponent("Contents/MacOS/Executable"))
    let apps = try scan(AppListOptions(includeArchitectures: true))
    XCTAssertEqual(apps.first?["supportedArchitectures"] as? [String], ["arm64"])
  }

  func testReadsBothArchitectureFamiliesFromAUniversalExecutable() throws {
    let url = try app("UniversalApp.app")
    let arm = machoHeader(cpu: CPU_TYPE_ARM64, subtype: CPU_SUBTYPE_ARM64_ALL)
    let intel = machoHeader(cpu: CPU_TYPE_X86_64, subtype: CPU_SUBTYPE_X86_64_ALL)
    var binary = Data()
    func word(_ value: UInt32) {
      var bigEndian = value.bigEndian
      withUnsafeBytes(of: &bigEndian) { binary.append(contentsOf: $0) }
    }
    word(FAT_MAGIC)
    word(2)
    for (cpu, subtype, offset) in [
      (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, UInt32(4096)),
      (CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_ALL, UInt32(8192)),
    ] {
      word(UInt32(bitPattern: cpu))
      word(UInt32(bitPattern: subtype))
      word(offset)
      word(UInt32(arm.count))
      word(12)
    }
    binary.append(Data(repeating: 0, count: 4096 - binary.count))
    binary.append(arm)
    binary.append(Data(repeating: 0, count: 8192 - binary.count))
    binary.append(intel)
    try binary.write(to: url.appendingPathComponent("Contents/MacOS/Executable"))
    let apps = try scan(AppListOptions(includeArchitectures: true))
    XCTAssertEqual(apps.first?["supportedArchitectures"] as? [String], ["arm64", "x86_64"])
  }

  func testScriptArchitecturesAndUnsignedTeamIDsRemainUnknown() throws {
    try app("Script.app")
    let apps = try scan(AppListOptions(includeArchitectures: true, includeSigningInfo: true))
    XCTAssertEqual(apps.count, 1)
    XCTAssertTrue(apps[0]["supportedArchitectures"] is NSNull)
    XCTAssertTrue(apps[0]["teamIdentifier"] is NSNull)
  }

  func testLogicalSizeIncludesHiddenAndNestedFilesWithoutFollowingSymlinks() throws {
    let url = try app("Sized.app")
    let expectedBase = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")).count
      + Data(contentsOf: url.appendingPathComponent("Contents/MacOS/Executable")).count
    let nested = url.appendingPathComponent("Contents/Frameworks/Embedded.framework")
    try fm.createDirectory(at: nested, withIntermediateDirectories: true)
    let regular = nested.appendingPathComponent("resource")
    try Data(repeating: 1, count: 37).write(to: regular)
    try fm.linkItem(at: regular, to: nested.appendingPathComponent("hardlink"))
    try Data(repeating: 2, count: 11).write(to: url.appendingPathComponent(".hidden"))
    let external = root.appendingPathComponent("External")
    try fm.createDirectory(at: external, withIntermediateDirectories: true)
    try Data(repeating: 3, count: 1000).write(to: external.appendingPathComponent("large"))
    try fm.createSymbolicLink(at: url.appendingPathComponent("LinkedDirectory"),
                             withDestinationURL: external)
    try fm.createSymbolicLink(at: url.appendingPathComponent("LinkedFile"),
                             withDestinationURL: regular)
    try fm.createSymbolicLink(at: url.appendingPathComponent("BrokenLink"),
                             withDestinationURL: root.appendingPathComponent("Missing"))
    let apps = try scan(AppListOptions(includeSize: true))
    XCTAssertEqual(apps.first?["bundleSizeBytes"] as? Int64, Int64(expectedBase + 37 + 37 + 11))
  }

  func testUnreadableBundleContentsDoNotReturnAPartialSize() throws {
    let url = try app("Restricted.app")
    let restricted = url.appendingPathComponent("Contents/Private")
    try fm.createDirectory(at: restricted, withIntermediateDirectories: true)
    try Data([1, 2, 3]).write(to: restricted.appendingPathComponent("data"))
    try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: restricted.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: restricted.path) }
    if fm.isReadableFile(atPath: restricted.path) {
      throw XCTSkip("The test host can bypass filesystem permissions")
    }
    let apps = try scan(AppListOptions(includeSize: true))
    XCTAssertEqual(apps.count, 1)
    XCTAssertTrue(apps[0]["bundleSizeBytes"] is NSNull)
  }

  func testRejectsExecutablePathsThatEscapeTheBundle() throws {
    try app("Escaping.app", extra: ["CFBundleExecutable": "../../../outside"])
    XCTAssertTrue(try scan().isEmpty)
    let info = try XCTUnwrap(try scan(AppListOptions(onlyLaunchable: false)).first)
    XCTAssertTrue(info["executablePath"] is NSNull)
  }

  func testFindsAppsInSubdirectoriesWithoutListingEmbeddedHelpers() throws {
    let outer = try app("Utilities/Outer.app")
    try app("Contents/Helpers/Embedded.app", in: outer)
    try app(".Hidden.app")
    XCTAssertEqual(try scan().map { $0["appName"] as? String }, ["Outer"])
  }

  func testPreservesCopiesAndDeduplicatesOverlappingRootsAndSymlinks() throws {
    let first = try app("One.app")
    try app("Nested/Two.app")
    try fm.createSymbolicLink(at: userApps.appendingPathComponent("Alias.app"),
                             withDestinationURL: first)
    let scanner = MacosAppScanner(searchDirectories: directories + [
      AppSearchDirectory(url: userApps.appendingPathComponent("Nested")),
    ])
    let apps = try scanner.listApps(options: AppListOptions())
    XCTAssertEqual(apps.count, 2)
    XCTAssertEqual(Set(apps.compactMap { $0["bundleIdentifier"] as? String }).count, 1)
    XCTAssertEqual(Set(apps.compactMap { $0["appPath"] as? String }).count, 2)
  }

  func testResolvesSymbolicLinkSearchRoots() throws {
    try app("Editor.app")
    let alias = root.appendingPathComponent("AliasRoot")
    try fm.createSymbolicLink(at: alias, withDestinationURL: userApps)
    let scanner = MacosAppScanner(searchDirectories: [AppSearchDirectory(url: alias)])
    XCTAssertEqual(try scanner.listApps(options: AppListOptions()).count, 1)
  }

  func testSystemAppSymlinksRemainSystemApps() throws {
    let system = try app("System.app", in: systemApps)
    try fm.createSymbolicLink(at: userApps.appendingPathComponent("SystemAlias.app"),
                             withDestinationURL: system)
    XCTAssertTrue(try scan().isEmpty)
    XCTAssertEqual(try scan(AppListOptions(includeSystem: true)).count, 1)
  }

  func testMissingBundleIDsAndMalformedBundles() throws {
    try app("NoIdentifier.app", bundleIdentifier: nil)
    let malformed = try app("Malformed.app")
    try Data("invalid plist".utf8).write(to: malformed.appendingPathComponent("Contents/Info.plist"))
    try app("Framework.app", extra: ["CFBundlePackageType": "FMWK"])
    XCTAssertEqual(try scan().count, 1)
    XCTAssertTrue(try scan(AppListOptions(bundleIdentifierPrefix: "com.")).isEmpty)
  }

  func testIconsLoadOnlyForFilteredResultsAndOnlyWhenRequested() throws {
    try app("Editor.app", bundleIdentifier: "com.example.editor")
    try app("Browser.app", bundleIdentifier: "org.example.browser")
    var iconRequests: [String] = []
    let scanner = MacosAppScanner(searchDirectories: directories, iconProvider: { url in
      iconRequests.append(url.lastPathComponent)
      return Data([137, 80, 78, 71])
    })
    _ = try scanner.listApps(options: AppListOptions())
    XCTAssertTrue(iconRequests.isEmpty)
    let apps = try scanner.listApps(options: AppListOptions(
      includeIcons: true, bundleIdentifierPrefix: "com."
    ))
    XCTAssertEqual(iconRequests, ["Editor.app"])
    XCTAssertEqual(apps.first?["iconBytes"] as? Data, Data([137, 80, 78, 71]))
  }

  func testDefaultIconIsA64PixelPNG() throws {
    try app("Editor.app")
    let apps = try scan(AppListOptions(includeIcons: true))
    let bytes = try XCTUnwrap(apps.first?["iconBytes"] as? Data)
    XCTAssertEqual(Array(bytes.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    let image = try XCTUnwrap(NSBitmapImageRep(data: bytes))
    XCTAssertEqual(image.pixelsWide, 64)
    XCTAssertEqual(image.pixelsHigh, 64)
  }

  func testEmptyAndMissingSearchRootsReturnEmptyLists() throws {
    XCTAssertTrue(try scan().isEmpty)
    let scanner = MacosAppScanner(searchDirectories: [
      AppSearchDirectory(url: root.appendingPathComponent("Missing")),
    ])
    XCTAssertTrue(try scanner.listApps(options: AppListOptions()).isEmpty)
  }

  func testInaccessibleRootsDoNotHideAccessibleResults() throws {
    try app("System.app", in: systemApps)
    let restricted = DirectoryReadDenyingFileManager(denied: [userApps])
    let scanner = MacosAppScanner(searchDirectories: directories, fileManager: restricted)
    let apps = try scanner.listApps(options: AppListOptions(includeSystem: true))
    XCTAssertEqual(apps.map { $0["appName"] as? String }, ["System"])
  }

  func testAllInaccessibleRootsProduceANativeScanError() {
    let restricted = DirectoryReadDenyingFileManager(denied: [userApps, systemApps])
    let scanner = MacosAppScanner(searchDirectories: directories, fileManager: restricted)
    let plugin = FlutterDeviceAppsMacosPlugin(scanner: scanner)
    let completed = expectation(description: "Inaccessible roots must report ERR_LIST")
    plugin.handle(FlutterMethodCall(methodName: "listApps", arguments: ["includeSystem": true])) {
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertEqual(($0 as? FlutterError)?.code, "ERR_LIST")
      completed.fulfill()
    }
    waitForExpectations(timeout: 10)
  }

  func testArgumentValidationRejectsWrongTypes() throws {
    let defaults = try AppListOptions(arguments: nil)
    XCTAssertFalse(defaults.includeSystem)
    XCTAssertTrue(defaults.onlyLaunchable)
    XCTAssertFalse(defaults.includeArchitectures)
    XCTAssertFalse(defaults.includeSize)
    XCTAssertFalse(defaults.includeSigningInfo)
    let invalidArguments: [Any] = [
      [], ["includeSystem": "true"], ["includeIcons": 1], ["bundleIdentifierContains": true],
      ["includeArchitectures": "true"], ["includeSize": 1], ["includeSigningInfo": []],
    ]
    for invalid in invalidArguments {
      XCTAssertThrowsError(try AppListOptions(arguments: invalid))
    }
    let options = try AppListOptions(arguments: [
      "includeSystem": true, "onlyLaunchable": false, "includeIcons": true,
      "includeArchitectures": true, "includeSize": true, "includeSigningInfo": true,
      "bundleIdentifierPrefix": "", "bundleIdentifierContains": NSNull(),
    ])
    XCTAssertTrue(options.includeSystem)
    XCTAssertFalse(options.onlyLaunchable)
    XCTAssertTrue(options.includeIcons)
    XCTAssertTrue(options.includeArchitectures)
    XCTAssertTrue(options.includeSize)
    XCTAssertTrue(options.includeSigningInfo)
    XCTAssertEqual(options.bundleIdentifierPrefix, "")
    XCTAssertNil(options.bundleIdentifierContains)
  }

  func testMethodChannelEncodesIconsAndRepliesOnMainThread() throws {
    try app("Editor.app")
    let scanner = MacosAppScanner(
      searchDirectories: directories, iconProvider: { _ in Data([137, 80, 78, 71]) },
      architectureProvider: { _ in ["arm64", "x86_64"] },
      sizeProvider: { _ in 12345678901 }, teamIdentifierProvider: { _ in "EXAMPLE123" }
    )
    let plugin = FlutterDeviceAppsMacosPlugin(scanner: scanner)
    let completed = expectation(description: "Native listApps response")
    plugin.handle(FlutterMethodCall(methodName: "listApps", arguments: [
      "includeIcons": true, "includeArchitectures": true, "includeSize": true, "includeSigningInfo": true,
    ])) {
      result in
      XCTAssertTrue(Thread.isMainThread)
      let apps = result as? [[String: Any]]
      XCTAssertEqual(apps?.count, 1)
      XCTAssertEqual((apps?.first?["iconBytes"] as? FlutterStandardTypedData)?.data,
                     Data([137, 80, 78, 71]))
      XCTAssertEqual(apps?.first?["supportedArchitectures"] as? [String], ["arm64", "x86_64"])
      XCTAssertEqual(apps?.first?["bundleSizeBytes"] as? Int64, 12345678901)
      XCTAssertEqual(apps?.first?["teamIdentifier"] as? String, "EXAMPLE123")
      completed.fulfill()
    }
    waitForExpectations(timeout: 10)
  }

  func testMethodChannelRejectsInvalidArgumentsAndUnknownMethods() {
    let plugin = FlutterDeviceAppsMacosPlugin()
    plugin.handle(FlutterMethodCall(methodName: "listApps", arguments: ["includeIcons": "yes"])) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "ARG")
    }
    plugin.handle(FlutterMethodCall(methodName: "otherMethod", arguments: nil)) {
      XCTAssertTrue(($0 as AnyObject?) === FlutterMethodNotImplemented)
    }
  }

  func testDefaultDirectoriesCanBeScannedInTheHostSandbox() throws {
    let apps = try MacosAppScanner().listApps(options: AppListOptions(includeSystem: true))
    XCTAssertFalse(apps.isEmpty)
    XCTAssertTrue(apps.allSatisfy { $0["appPath"] is String && $0["appName"] is String })
    print("Sandbox app discovery smoke check: \(apps.count) accessible app bundles")
  }
}

private final class DirectoryReadDenyingFileManager: FileManager, @unchecked Sendable {
  private let deniedPaths: Set<String>

  init(denied: [URL]) {
    deniedPaths = Set(denied.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
    super.init()
  }

  override func contentsOfDirectory(
    at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?,
    options mask: FileManager.DirectoryEnumerationOptions = []
  ) throws -> [URL] {
    if deniedPaths.contains(url.path) { throw CocoaError(.fileReadNoPermission) }
    return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
  }
}
