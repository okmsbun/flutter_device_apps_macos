import AppKit
import CoreServices
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

  func testBundleLookupUsesThePreferredCopyWithoutEnumeratingDirectories() throws {
    try app("First.app", bundleIdentifier: "com.example.copy")
    let preferred = try app("Second.app", bundleIdentifier: "com.example.copy")
    let fm = DirectoryReadDenyingFileManager(denied: [userApps, systemApps])
    var requests: [String] = []
    let scanner = MacosAppScanner(
      searchDirectories: directories, fileManager: fm,
      applicationResolver: { identifier in requests.append(identifier); return preferred }
    )
    let info = try scanner.getApp(target: .bundleIdentifier("com.example.copy"), options: AppListOptions())
    XCTAssertEqual(info?["appPath"] as? String, preferred.resolvingSymlinksInPath().path)
    XCTAssertEqual(info?["appName"] as? String, "Second")
    XCTAssertEqual(requests, ["com.example.copy"])
    XCTAssertEqual(fm.directoryReadCount, 0)
  }

  func testPathLookupSelectsAnExactCopyOutsideDiscoveryRootsAndResolvesSymlinks() throws {
    try app("Inside.app", bundleIdentifier: "com.example.copy")
    let outside = try app("Outside.app", in: root.appendingPathComponent("Other"),
                          bundleIdentifier: "com.example.copy")
    let alias = root.appendingPathComponent("Alias")
    try fm.createSymbolicLink(at: alias, withDestinationURL: outside)
    let scanner = MacosAppScanner(searchDirectories: directories, applicationResolver: { _ in
      XCTFail("Path lookup must not resolve a bundle identifier")
      return nil
    })
    let info = try scanner.getApp(target: .appPath(alias.path), options: AppListOptions())
    XCTAssertEqual(info?["appPath"] as? String, outside.resolvingSymlinksInPath().path)
    XCTAssertEqual(info?["appName"] as? String, "Outside")
  }

  func testLookupIncludesSystemAgentsBackgroundAppsAndMissingExecutables() throws {
    let url = try app(".Agent.app", in: systemApps, bundleIdentifier: nil,
                      extra: ["LSUIElement": true, "LSBackgroundOnly": true], executable: false)
    let scanner = MacosAppScanner(searchDirectories: directories)
    let info = try scanner.getApp(target: .appPath(url.path), options: AppListOptions())
    XCTAssertNotNil(info)
    XCTAssertTrue(info?["bundleIdentifier"] is NSNull)
    XCTAssertEqual(info?["isSystem"] as? Bool, true)
    XCTAssertEqual(info?["isAgent"] as? Bool, true)
    XCTAssertEqual(info?["isBackgroundOnly"] as? Bool, true)
  }

  func testLookupMissesAndStaleResolverResultsDoNotReturnOtherApps() throws {
    let appURL = try app("Existing.app", bundleIdentifier: "com.example.existing")
    let scanner = MacosAppScanner(searchDirectories: directories, applicationResolver: { _ in nil })
    XCTAssertNil(try scanner.getApp(target: .bundleIdentifier("com.example.existing"), options: AppListOptions()))
    XCTAssertNil(try scanner.getApp(target: .appPath(root.appendingPathComponent("Missing.app").path), options: AppListOptions()))
    let wrong = MacosAppScanner(searchDirectories: directories, applicationResolver: { _ in appURL })
    XCTAssertNil(try wrong.getApp(target: .bundleIdentifier("com.example.other"), options: AppListOptions()))
    XCTAssertNil(try wrong.getApp(target: .bundleIdentifier("COM.EXAMPLE.EXISTING"), options: AppListOptions()))
    let nonFile = MacosAppScanner(applicationResolver: { _ in URL(string: "https://example.com/App.app") })
    XCTAssertNil(try nonFile.getApp(target: .bundleIdentifier("com.example.app"), options: AppListOptions()))
  }

  func testMalformedAndUnreadableAppPathsReturnNil() throws {
    let scanner = MacosAppScanner(searchDirectories: directories)
    let framework = try app("Framework.app", extra: ["CFBundlePackageType": "FMWK"])
    XCTAssertNil(try scanner.getApp(target: .appPath(framework.path), options: AppListOptions()))
    let regularFile = root.appendingPathComponent("File.app")
    try Data([1]).write(to: regularFile)
    XCTAssertNil(try scanner.getApp(target: .appPath(regularFile.path), options: AppListOptions()))
    let malformed = try app("Malformed.app")
    try Data("not a plist".utf8).write(to: malformed.appendingPathComponent("Contents/Info.plist"))
    XCTAssertNil(try scanner.getApp(target: .appPath(malformed.path), options: AppListOptions()))
    let noAccess = try app("Restricted.app")
    let plist = noAccess.appendingPathComponent("Contents/Info.plist")
    try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: plist.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plist.path) }
    if fm.isReadableFile(atPath: plist.path) {
      throw XCTSkip("The test host can bypass filesystem permissions")
    }
    XCTAssertNil(try scanner.getApp(target: .appPath(noAccess.path), options: AppListOptions()))
  }

  func testLookupRequestValidatesTargetsAndMetadataOptions() throws {
    let invalid: [Any?] = [
      nil, [], [:], ["bundleIdentifier": 42], ["appPath": true],
      ["bundleIdentifier": ""], ["bundleIdentifier": " \n "],
      ["bundleIdentifier": "com.example.\0app"], ["appPath": "App.app"],
      ["appPath": "~/Applications/App.app"], ["appPath": "file:///Applications/App.app"],
      ["appPath": "/Applications/App.app\0"],
      ["bundleIdentifier": "com.example.app", "appPath": "/Applications/App.app"],
      ["appPath": "/Applications/App.app", "includeIcon": 1],
      ["appPath": "/Applications/App.app", "includeArchitectures": "true"],
      ["appPath": "/Applications/App.app", "includeSize": []],
      ["appPath": "/Applications/App.app", "includeSigningInfo": "true"],
    ]
    let plugin = FlutterDeviceAppsMacosPlugin()
    var replies = 0
    for arguments in invalid {
      XCTAssertThrowsError(try AppLookupRequest(arguments: arguments))
      plugin.handle(FlutterMethodCall(methodName: "getApp", arguments: arguments)) {
        XCTAssertEqual(($0 as? FlutterError)?.code, "ARG")
        replies += 1
      }
    }
    XCTAssertEqual(replies, invalid.count)
    let request = try AppLookupRequest(arguments: [
      "bundleIdentifier": NSNull(), "appPath": "/Applications/App.app", "includeIcon": true,
      "includeArchitectures": true, "includeSize": true, "includeSigningInfo": true,
    ])
    XCTAssertTrue(request.options.includeIcons)
    XCTAssertTrue(request.options.includeArchitectures)
    XCTAssertTrue(request.options.includeSize)
    XCTAssertTrue(request.options.includeSigningInfo)
    XCTAssertTrue(request.options.includeSystem)
    XCTAssertFalse(request.options.onlyLaunchable)
  }

  func testLookupMethodChannelReturnsMetadataOnMainThreadFromBackgroundLookup() throws {
    let url = try app("Editor.app")
    let scanner = MacosAppScanner(
      searchDirectories: directories, iconProvider: { _ in Data([137, 80, 78, 71]) },
      architectureProvider: { _ in ["arm64"] }, sizeProvider: { _ in 4096 },
      teamIdentifierProvider: { _ in "EXAMPLE123" }, applicationResolver: { _ in
        XCTAssertFalse(Thread.isMainThread)
        return url
      }
    )
    let plugin = FlutterDeviceAppsMacosPlugin(scanner: scanner)
    let completed = expectation(description: "One app with optional metadata")
    plugin.handle(FlutterMethodCall(methodName: "getApp", arguments: [
      "bundleIdentifier": "com.example.app", "includeIcon": true,
      "includeArchitectures": true, "includeSize": true, "includeSigningInfo": true,
    ])) { result in
      XCTAssertTrue(Thread.isMainThread)
      let app = result as? [String: Any]
      XCTAssertEqual(app?["appName"] as? String, "Editor")
      XCTAssertEqual(app?["supportedArchitectures"] as? [String], ["arm64"])
      XCTAssertEqual(app?["bundleSizeBytes"] as? Int64, 4096)
      XCTAssertEqual(app?["teamIdentifier"] as? String, "EXAMPLE123")
      XCTAssertEqual((app?["iconBytes"] as? FlutterStandardTypedData)?.data, Data([137, 80, 78, 71]))
      completed.fulfill()
    }
    waitForExpectations(timeout: 10)
  }

  func testLookupMethodChannelDistinguishesMissingAppsFromResolutionErrors() {
    let missing = FlutterDeviceAppsMacosPlugin(scanner: MacosAppScanner(applicationResolver: { _ in nil }))
    let absent = expectation(description: "Missing app returns null")
    missing.handle(FlutterMethodCall(methodName: "getApp", arguments: ["bundleIdentifier": "com.example.missing"])) {
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertNil($0)
      absent.fulfill()
    }
    let failed = FlutterDeviceAppsMacosPlugin(scanner: MacosAppScanner(applicationResolver: { _ in
      throw NSError(domain: "lookup", code: 1)
    }))
    let error = expectation(description: "Unexpected resolution errors report ERR_GET")
    failed.handle(FlutterMethodCall(methodName: "getApp", arguments: ["bundleIdentifier": "com.example.app"])) {
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertEqual(($0 as? FlutterError)?.code, "ERR_GET")
      error.fulfill()
    }
    waitForExpectations(timeout: 10)
  }

  func testAppStatusChecksUseSingleLookupAndLaunchPreflight() throws {
    let system = try app("System.app", in: systemApps, bundleIdentifier: "com.example.system")
    let regular = try app("Regular.app")
    let agent = try app("Agent.app", extra: ["LSUIElement": true])
    let background = try app("Background.app", extra: ["LSBackgroundOnly": true])
    let disabled = try app("Disabled.app")
    try fm.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: disabled.appendingPathComponent("Contents/MacOS/Executable").path
    )
    let missing = root.appendingPathComponent("Missing.app").path
    let restricted = DirectoryReadDenyingFileManager(denied: [userApps, systemApps])
    let scanner = MacosAppScanner(
      searchDirectories: directories, fileManager: restricted,
      applicationResolver: { $0 == "com.example.system" ? system : nil }
    )
    let plugin = FlutterDeviceAppsMacosPlugin(scanner: scanner)
    let checks: [(method: String, arguments: [String: String], expected: Bool?)] = [
      ("isAppInstalled", ["bundleIdentifier": "com.example.system"], true),
      ("isAppInstalled", ["appPath": agent.path], true),
      ("isAppInstalled", ["appPath": missing], false),
      ("isSystemApp", ["appPath": system.path], true),
      ("isSystemApp", ["appPath": regular.path], false),
      ("isSystemApp", ["appPath": missing], nil),
      ("isAppLaunchable", ["appPath": regular.path], true),
      ("isAppLaunchable", ["appPath": agent.path], false),
      ("isAppLaunchable", ["appPath": background.path], false),
      ("isAppLaunchable", ["appPath": disabled.path], false),
      ("isAppLaunchable", ["appPath": missing], false),
    ]
    for check in checks {
      let completed = expectation(description: check.method)
      plugin.handle(FlutterMethodCall(methodName: check.method, arguments: check.arguments)) { result in
        XCTAssertTrue(Thread.isMainThread)
        if check.expected == nil {
          XCTAssertNil(result)
        } else {
          XCTAssertEqual(result as? Bool, check.expected, "\(check.method) \(check.arguments)")
        }
        completed.fulfill()
      }
    }
    waitForExpectations(timeout: 10)
    XCTAssertEqual(restricted.directoryReadCount, 0)
  }

  func testDeclaredCapabilitiesPreserveUsageDescriptionsWithoutASignature() throws {
    let camera = try app("Camera.app", bundleIdentifier: "com.example.camera", extra: [
      "NSCameraUsageDescription": "Capture a photo",
      "NSMicrophoneUsageDescription": 42,
      "CFBundleDisplayName": "Camera",
    ])
    let restricted = DirectoryReadDenyingFileManager(denied: [userApps, systemApps])
    let scanner = MacosAppScanner(
      searchDirectories: directories, fileManager: restricted,
      applicationResolver: { $0 == "com.example.camera" ? camera : nil }
    )
    let plugin = FlutterDeviceAppsMacosPlugin(scanner: scanner)
    let read = expectation(description: "declared capabilities")
    let call = FlutterMethodCall(
      methodName: "getDeclaredCapabilities", arguments: ["bundleIdentifier": "com.example.camera"]
    )
    plugin.handle(call) { response in
      XCTAssertTrue(Thread.isMainThread)
      let result = response as? [String: Any]
      XCTAssertEqual(result?["usageDescriptions"] as? [String: String], [
        "NSCameraUsageDescription": "Capture a photo",
      ])
      XCTAssertNil(result?["entitlements"])
      read.fulfill()
    }
    waitForExpectations(timeout: 10)
    XCTAssertEqual(restricted.directoryReadCount, 0)
    XCTAssertNil(try scanner.getDeclaredCapabilities(target: .bundleIdentifier("com.example.missing")))
  }

  func testDeclaredCapabilitiesReadTheHostsEmbeddedEntitlements() throws {
    let target = AppLookupTarget.appPath(Bundle.main.bundleURL.path)
    let result = try XCTUnwrap(MacosAppScanner().getDeclaredCapabilities(target: target))
    let entitlements = try XCTUnwrap(result["entitlements"] as? [String: Any])
    XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
  }

  func testAppInspectionReadsOnlySupportedMarkersInTheResolvedBundle() throws {
    let preferred = try app("Preferred.app")
    let copy = try app("Copy.app")
    let plain = try app("Plain.app")
    let missing = userApps.appendingPathComponent("Missing.app")
    let flutterRoot = preferred.appendingPathComponent("Contents/Frameworks/FlutterMacOS.framework")
    for file in [
      flutterRoot.appendingPathComponent("Versions/A/FlutterMacOS"),
      preferred.appendingPathComponent("Contents/Frameworks/QtCore.framework/QtCore"),
      preferred.appendingPathComponent("Contents/_MASReceipt/receipt"),
      copy.appendingPathComponent("Contents/Frameworks/Electron Framework.framework/Electron Framework"),
      plain.appendingPathComponent("Contents/PlugIns/Helper.app/Contents/Frameworks/QtCore.framework/QtCore"),
    ] {
      try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("fixture".utf8).write(to: file)
    }
    try fm.createSymbolicLink(
      at: flutterRoot.appendingPathComponent("FlutterMacOS"),
      withDestinationURL: flutterRoot.appendingPathComponent("Versions/A/FlutterMacOS")
    )
    try fm.createSymbolicLink(
      at: copy.appendingPathComponent("Contents/Frameworks/FlutterMacOS.framework"),
      withDestinationURL: flutterRoot
    )

    let restricted = DirectoryReadDenyingFileManager(denied: [userApps, systemApps])
    let scanner = MacosAppScanner(
      searchDirectories: directories, fileManager: restricted,
      applicationResolver: { _ in preferred }
    )
    let plugin = FlutterDeviceAppsMacosPlugin(scanner: scanner)
    let frameworkChecks: [([String: String], [String]?)] = [
      (["bundleIdentifier": "com.example.app"], ["flutter", "qt"]),
      (["appPath": copy.path], ["electron"]),
      (["appPath": plain.path], []),
      (["appPath": missing.path], nil),
    ]
    for (arguments, expected) in frameworkChecks {
      let finished = expectation(description: "framework inspection")
      plugin.handle(FlutterMethodCall(methodName: "detectAppFrameworks", arguments: arguments)) { result in
        XCTAssertTrue(Thread.isMainThread)
        if let expected = expected {
          XCTAssertEqual(result as? [String], expected)
        } else {
          XCTAssertNil(result)
        }
        finished.fulfill()
      }
    }
    let sourceChecks: [(URL, String?)] = [
      (preferred, "macAppStore"), (copy, "unknown"), (missing, nil),
    ]
    for (app, expected) in sourceChecks {
      let finished = expectation(description: "install source inspection")
      plugin.handle(FlutterMethodCall(methodName: "getInstallSourceInfo", arguments: ["appPath": app.path])) { result in
        XCTAssertTrue(Thread.isMainThread)
        if let expected = expected {
          let info = result as? [String: Any]
          XCTAssertEqual(info?["source"] as? String, expected)
          XCTAssertEqual(info?["hasAppStoreReceipt"] as? Bool, expected == "macAppStore")
        } else {
          XCTAssertNil(result)
        }
        finished.fulfill()
      }
    }
    waitForExpectations(timeout: 10)
    XCTAssertEqual(restricted.directoryReadCount, 0)
  }

  func testInstallSourceUsesQuarantineTypeAndPrefersAReceiptMarker() {
    let web: [String: Any] = [
      kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
      kLSQuarantineAgentNameKey as String: "Safari",
      kLSQuarantineAgentBundleIdentifierKey as String: "com.apple.Safari",
    ]
    let download = MacosAppScanner.installSourceInfo(hasAppStoreReceipt: false, quarantine: web)
    XCTAssertEqual(download["source"] as? String, "webDownload")
    XCTAssertEqual(download["quarantineAgentName"] as? String, "Safari")
    XCTAssertEqual(download["quarantineAgentBundleIdentifier"] as? String, "com.apple.Safari")
    let store = MacosAppScanner.installSourceInfo(hasAppStoreReceipt: true, quarantine: web)
    XCTAssertEqual(store["source"] as? String, "macAppStore")
    let unspecified = MacosAppScanner.installSourceInfo(
      hasAppStoreReceipt: false,
      quarantine: [kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String]
    )
    XCTAssertEqual(unspecified["source"] as? String, "unknown")
  }

  func testAppActionsUseResolvedPathsAndWaitForLaunchCompletion() throws {
    let preferred = try app("Preferred.app", extra: ["LSBackgroundOnly": true], executable: false)
    let copy = try app("Copy.app").resolvingSymlinksInPath().standardizedFileURL
    let trashed = root.appendingPathComponent("Moved.app")
    let restricted = DirectoryReadDenyingFileManager(denied: [userApps, systemApps])
    let scanner = MacosAppScanner(
      searchDirectories: directories, fileManager: restricted,
      applicationResolver: { _ in preferred }
    )
    var launchFinished = false
    let plugin = FlutterDeviceAppsMacosPlugin(
      scanner: scanner,
      openApplication: { url, finish in
        XCTAssertEqual(url.path, preferred.resolvingSymlinksInPath().path)
        DispatchQueue.main.async {
          launchFinished = true
          finish(nil)
        }
      },
      revealApplication: { XCTAssertEqual($0.path, copy.path) },
      trashApplication: { [fm] url in
        XCTAssertEqual(url.path, copy.path)
        try fm.moveItem(at: url, to: trashed)
      }
    )
    for (method, arguments) in [
      ("openApp", ["bundleIdentifier": "com.example.app"]),
      ("revealAppInFinder", ["appPath": copy.path]),
      ("moveAppToTrash", ["appPath": copy.path]),
    ] {
      let completed = expectation(description: method)
      plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { result in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertNil(result)
        if method == "openApp" { XCTAssertTrue(launchFinished) }
        completed.fulfill()
      }
    }
    waitForExpectations(timeout: 10)
    XCTAssertEqual(restricted.directoryReadCount, 0)
    XCTAssertTrue(fm.fileExists(atPath: preferred.path))
    XCTAssertFalse(fm.fileExists(atPath: copy.path))
    XCTAssertTrue(fm.fileExists(atPath: trashed.path))
  }

  func testAppActionErrorsPreserveNativeFailureAndRejectTrashAliases() throws {
    let target = try app("Target.app").resolvingSymlinksInPath().standardizedFileURL
    let alias = userApps.appendingPathComponent("Alias.app")
    try fm.createSymbolicLink(at: alias, withDestinationURL: target)
    let missing = userApps.appendingPathComponent("Missing.app").path
    let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
    let plugin = FlutterDeviceAppsMacosPlugin(
      scanner: MacosAppScanner(searchDirectories: directories),
      openApplication: { _, finish in finish(denied) },
      revealApplication: { _ in XCTFail("Missing apps should not be revealed") },
      trashApplication: { url in
        XCTAssertEqual(url.path, target.path)
        throw denied
      }
    )
    for (method, arguments, code, nativeCode) in [
      ("openApp", ["appPath": target.path], "ERR_OPEN", denied.code),
      ("revealAppInFinder", ["appPath": missing], "APP_UNAVAILABLE", nil),
      ("moveAppToTrash", ["appPath": alias.path], "ERR_TRASH", nil),
      ("moveAppToTrash", ["appPath": target.path], "ERR_TRASH", denied.code),
      ("moveAppToTrash", ["bundleIdentifier": "com.example.app"], "ARG", nil),
    ] {
      let completed = expectation(description: method)
      plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { result in
        XCTAssertTrue(Thread.isMainThread)
        let error = result as? FlutterError
        XCTAssertEqual(error?.code, code)
        if let nativeCode = nativeCode {
          let details = error?.details as? [String: Any]
          XCTAssertEqual(details?["domain"] as? String, denied.domain)
          XCTAssertEqual(details?["code"] as? Int, nativeCode)
        }
        completed.fulfill()
      }
    }
    waitForExpectations(timeout: 10)
    XCTAssertTrue(fm.fileExists(atPath: target.path))
  }

  func testIconLookupReturnsPNGWithoutEnumeratingDirectories() throws {
    let url = try app("Editor.app")
    let restricted = DirectoryReadDenyingFileManager(denied: [userApps, systemApps])
    let scanner = MacosAppScanner(
      searchDirectories: directories, fileManager: restricted,
      applicationResolver: { identifier in
        XCTAssertEqual(identifier, "com.example.app")
        XCTAssertFalse(Thread.isMainThread)
        return url
      }
    )
    let plugin = FlutterDeviceAppsMacosPlugin(scanner: scanner)
    let completed = expectation(description: "Standalone PNG icon")
    plugin.handle(FlutterMethodCall(methodName: "getAppIcon", arguments: [
      "bundleIdentifier": "com.example.app",
    ])) { result in
      XCTAssertTrue(Thread.isMainThread)
      let icon = (result as? FlutterStandardTypedData).flatMap { NSBitmapImageRep(data: $0.data) }
      XCTAssertEqual(icon?.pixelsWide, 64)
      XCTAssertEqual(icon?.pixelsHigh, 64)
      XCTAssertEqual(restricted.directoryReadCount, 0)
      completed.fulfill()
    }
    let missing = expectation(description: "Missing app icon")
    plugin.handle(FlutterMethodCall(methodName: "getAppIcon", arguments: [
      "appPath": root.appendingPathComponent("Missing.app").path,
    ])) {
      XCTAssertNil($0)
      missing.fulfill()
    }
    waitForExpectations(timeout: 10)
  }

  func testBatchLookupPreservesOrderAndDeduplicatesResolvedCopies() throws {
    let first = try app("First.app", bundleIdentifier: "com.example.copy")
    let preferred = try app("Second.app", bundleIdentifier: "com.example.copy")
    let alias = root.appendingPathComponent("Alias.app")
    try fm.createSymbolicLink(at: alias, withDestinationURL: preferred)
    let expectedPaths = [preferred, first].map { $0.resolvingSymlinksInPath().path }
    var iconReads: [String] = []
    let scanner = MacosAppScanner(
      searchDirectories: directories, iconProvider: { url in
        iconReads.append(url.path)
        return Data([137, 80, 78, 71])
      },
      applicationResolver: { identifier in
        XCTAssertFalse(Thread.isMainThread)
        return identifier == "com.example.copy" ? preferred : nil
      }
    )
    let plugin = FlutterDeviceAppsMacosPlugin(scanner: scanner)
    let completed = expectation(description: "Ordered batch lookup")
    plugin.handle(FlutterMethodCall(methodName: "getApps", arguments: [
      "targets": ["com.example.copy", alias.path, "com.example.missing", first.path, preferred.path],
      "includeIcons": true,
    ])) { result in
      XCTAssertTrue(Thread.isMainThread)
      let apps = result as? [[String: Any]]
      XCTAssertEqual(apps?.compactMap { $0["appPath"] as? String }, expectedPaths)
      XCTAssertEqual(apps?.compactMap { $0["bundleIdentifier"] as? String },
                     ["com.example.copy", "com.example.copy"])
      XCTAssertEqual(iconReads, expectedPaths)
      XCTAssertEqual((apps?.first?["iconBytes"] as? FlutterStandardTypedData)?.data,
                     Data([137, 80, 78, 71]))
      completed.fulfill()
    }
    waitForExpectations(timeout: 10)
  }

  func testBatchLookupRejectsInvalidTargetsAndReportsResolutionErrors() {
    let plugin = FlutterDeviceAppsMacosPlugin(scanner: MacosAppScanner(applicationResolver: { _ in
      throw NSError(domain: "lookup", code: 1)
    }))
    let invalid: [[String: Any]] = [
      [:], ["targets": [1]], ["targets": [" "]], ["targets": ["Folder/App.app"]],
      ["targets": ["com.example.\0app"]], ["targets": ["com.example.app"], "includeIcons": 1],
    ]
    var replies = 0
    for arguments in invalid {
      plugin.handle(FlutterMethodCall(methodName: "getApps", arguments: arguments)) {
        XCTAssertEqual(($0 as? FlutterError)?.code, "ARG")
        replies += 1
      }
    }
    XCTAssertEqual(replies, invalid.count)
    let completed = expectation(description: "Unexpected batch failure")
    plugin.handle(FlutterMethodCall(methodName: "getApps", arguments: [
      "targets": ["com.example.app"],
    ])) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "ERR_GET_APPS")
      completed.fulfill()
    }
    waitForExpectations(timeout: 10)
  }

  func testRunningAppsReportsTheHostApplication() {
    let completed = expectation(description: "running apps snapshot")
    let plugin = FlutterDeviceAppsMacosPlugin(scanner: MacosAppScanner())
    plugin.handle(FlutterMethodCall(methodName: "listRunningApps", arguments: nil)) { result in
      XCTAssertTrue(Thread.isMainThread)
      let apps = result as? [[String: Any]]
      let host = apps?.first {
        $0["processIdentifier"] as? Int == Int(ProcessInfo.processInfo.processIdentifier)
      }
      XCTAssertEqual(host?["bundleIdentifier"] as? String, Bundle.main.bundleIdentifier)
      XCTAssertNotNil(host?["appPath"] as? String)
      XCTAssertNotNil(host?["isActive"] as? Bool)
      completed.fulfill()
    }
    waitForExpectations(timeout: 10)
  }

  func testDefaultAppForFileUsesTheResolvedAppCopyWithoutScanning() throws {
    let document = root.appendingPathComponent("My Document.pdf")
    try Data().write(to: document)
    try app("Other Reader.app", bundleIdentifier: "com.example.reader")
    let handler = try app("PDF Reader.app", in: root, bundleIdentifier: "com.example.reader")
    let restricted = DirectoryReadDenyingFileManager(denied: [userApps, systemApps])
    let plugin = FlutterDeviceAppsMacosPlugin(
      scanner: MacosAppScanner(searchDirectories: directories, fileManager: restricted),
      defaultAppForFile: { $0.path == document.path ? handler : nil }
    )
    for (path, expected) in [
      (document.path, handler.resolvingSymlinksInPath().standardizedFileURL.path),
      (root.appendingPathComponent("Missing.pdf").path, nil),
    ] {
      let completed = expectation(description: "default app for file")
      plugin.handle(FlutterMethodCall(
        methodName: "getDefaultAppForFile", arguments: ["filePath": path]
      )) { result in
        XCTAssertTrue(Thread.isMainThread)
        if let expected = expected {
          let app = result as? [String: Any]
          XCTAssertEqual(app?["appPath"] as? String, expected)
          XCTAssertEqual(app?["bundleIdentifier"] as? String, "com.example.reader")
        } else {
          XCTAssertNil(result)
        }
        completed.fulfill()
      }
    }
    waitForExpectations(timeout: 10)
    XCTAssertEqual(restricted.directoryReadCount, 0)
  }

  func testSpotlightOptInMergesValidCandidatesUsingTheListFilters() throws {
    let id = "com.example.editor"
    let scanned = try app("Scanned.app", bundleIdentifier: id)
    let extra = root.appendingPathComponent("OutsideSearchRoots")
    let indexed = try app("Indexed.app", in: extra, bundleIdentifier: id)
    let system = try app("System.app", in: systemApps, bundleIdentifier: id)
    let agent = try app("Agent.app", in: extra, bundleIdentifier: id, extra: ["LSUIElement": true])
    let mismatched = try app("Mismatched.app", in: extra, bundleIdentifier: "com.example.other")
    let nested = try app("Parent.app/Contents/Helpers/Nested.app", in: extra, bundleIdentifier: id)
    let hidden = try app(".Hidden.app", in: extra, bundleIdentifier: id)
    let missing = extra.appendingPathComponent("Missing.app")
    let alias = extra.appendingPathComponent("IndexedAlias.app")
    try fm.createSymbolicLink(at: alias, withDestinationURL: indexed)
    var searches = 0
    let plugin = FlutterDeviceAppsMacosPlugin(
      scanner: MacosAppScanner(searchDirectories: directories),
      searchSpotlight: { finish in
        searches += 1
        finish([scanned, alias, indexed, system, agent, mismatched, nested, hidden, missing])
      }
    )
    for (includeSpotlight, names) in [
      (false, ["Scanned"]),
      (true, ["Indexed", "Scanned"]),
    ] {
      let completed = expectation(description: "listApps with Spotlight \(includeSpotlight)")
      plugin.handle(FlutterMethodCall(methodName: "listApps", arguments: [
        "includeSpotlight": includeSpotlight, "bundleIdentifierPrefix": id,
      ])) { result in
        XCTAssertTrue(Thread.isMainThread)
        let apps = result as? [[String: Any]]
        XCTAssertEqual(apps?.compactMap { $0["appName"] as? String }, names)
        completed.fulfill()
      }
    }
    waitForExpectations(timeout: 10)
    XCTAssertEqual(searches, 1)
  }

  func testSpotlightSearchCompletesInTheHostSandbox() {
    let completed = expectation(description: "Spotlight query")
    completed.assertForOverFulfill = true
    SpotlightAppSearch.search { urls in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertTrue(urls.allSatisfy(\.isFileURL))
      completed.fulfill()
    }
    waitForExpectations(timeout: 5)
  }

  func testSearchFolderBookmarksPersistAndFeedTheNormalListAppsChannel() throws {
    let suite = "flutter-device-apps-search-folders-\(UUID().uuidString)"
    let prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { prefs.removePersistentDomain(forName: suite) }

    let extra = root.appendingPathComponent("ExtraApps")
    _ = try app("Extra.app", in: extra, bundleIdentifier: "com.example.discovery.extra")
    _ = try app("Agent.app", in: extra, extra: ["LSUIElement": true])
    _ = try app("Default.app", bundleIdentifier: "com.example.discovery.default")

    let initial = AppSearchFolders(defaults: prefs)
    let entry = try initial.add(extra)
    XCTAssertEqual(try initial.add(extra), entry)
    _ = try initial.add(userApps)
    let id = try XCTUnwrap(entry["id"])

    let restored = AppSearchFolders(defaults: prefs)
    XCTAssertEqual(restored.list().count, 2)
    XCTAssertEqual(restored.list().first, entry)
    do {
      let access = restored.start()
      defer { access.stop() }
      XCTAssertEqual(
        Set(access.scopedURLs.map { $0.resolvingSymlinksInPath().path }),
        Set([extra, userApps!].map { $0.resolvingSymlinksInPath().path })
      )
    }

    let plugin = FlutterDeviceAppsMacosPlugin(
      scanner: MacosAppScanner(searchDirectories: directories), searchFolders: restored
    )
    let list = FlutterMethodCall(
      methodName: "listApps", arguments: ["bundleIdentifierPrefix": "com.example.discovery."]
    )
    let included = expectation(description: "saved folder included")
    plugin.handle(list) { result in
      let apps = result as? [[String: Any]]
      XCTAssertEqual(apps?.compactMap { $0["appName"] as? String }, ["Default", "Extra"])
      included.fulfill()
    }
    waitForExpectations(timeout: 10)

    let removed = expectation(description: "saved folder removed")
    plugin.handle(FlutterMethodCall(methodName: "removeAppSearchFolder", arguments: ["id": id])) { result in
      XCTAssertNil(result)
      removed.fulfill()
    }
    waitForExpectations(timeout: 10)
    XCTAssertEqual(initial.list().count, 1)

    let excluded = expectation(description: "removed folder excluded")
    plugin.handle(list) { result in
      let apps = result as? [[String: Any]]
      XCTAssertEqual(apps?.compactMap { $0["appName"] as? String }, ["Default"])
      excluded.fulfill()
    }
    waitForExpectations(timeout: 10)
    XCTAssertTrue(fm.fileExists(atPath: extra.path))
  }

  func testDefaultBundleLookupWorksInTheHostSandbox() throws {
    let info = try MacosAppScanner().getApp(target: .bundleIdentifier("com.apple.TextEdit"), options: AppListOptions())
    XCTAssertEqual(info?["bundleIdentifier"] as? String, "com.apple.TextEdit")
    XCTAssertNotNil(info?["appPath"] as? String)
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
  private(set) var directoryReadCount = 0

  init(denied: [URL]) {
    deniedPaths = Set(denied.map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
    super.init()
  }

  override func contentsOfDirectory(
    at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?,
    options mask: FileManager.DirectoryEnumerationOptions = []
  ) throws -> [URL] {
    directoryReadCount += 1
    if deniedPaths.contains(url.path) { throw CocoaError(.fileReadNoPermission) }
    return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
  }
}
