import Cocoa
import FlutterMacOS

private enum AppActionError: LocalizedError {
  case unavailable, unresolvedPath, launchFailed

  var errorDescription: String? {
    switch self {
    case .unavailable: return "The selected app is unavailable."
    case .unresolvedPath: return "Use the resolved app path from the app lookup."
    case .launchFailed: return "macOS did not report a running app."
    }
  }
}

public class FlutterDeviceAppsMacosPlugin: NSObject, FlutterPlugin {
  private let scanner: MacosAppScanner
  private let worker = DispatchQueue(label: "flutter_device_apps_macos/scan", qos: .userInitiated)
  private let openApplication: (URL, @escaping (Error?) -> Void) -> Void
  private let revealApplication: (URL) -> Void
  private let trashApplication: (URL) throws -> Void

  public override convenience init() {
    self.init(scanner: MacosAppScanner())
  }

  init(
    scanner: MacosAppScanner,
    openApplication: @escaping (URL, @escaping (Error?) -> Void) -> Void = { url, finish in
      NSWorkspace.shared.openApplication(at: url, configuration: .init()) { app, error in
        finish(error ?? (app == nil ? AppActionError.launchFailed : nil))
      }
    },
    revealApplication: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
    trashApplication: @escaping (URL) throws -> Void = {
      try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }
  ) {
    self.scanner = scanner
    self.openApplication = openApplication
    self.revealApplication = revealApplication
    self.trashApplication = trashApplication
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_device_apps_macos/methods",
      binaryMessenger: registrar.messenger
    )
    let instance = FlutterDeviceAppsMacosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "listApps":
        let options = try AppListOptions(arguments: call.arguments)
        perform(errorCode: "ERR_LIST", result: result) {
          try self.scanner.listApps(options: options).map(Self.encodeApp)
        }
      case "getApp":
        let request = try AppLookupRequest(arguments: call.arguments)
        perform(errorCode: "ERR_GET", result: result) {
          try self.scanner.getApp(target: request.target, options: request.options).map(Self.encodeApp)
        }
      case "getApps":
        let request = try AppBatchLookupRequest(arguments: call.arguments)
        perform(errorCode: "ERR_GET_APPS", result: result) {
          try self.scanner.getApps(targets: request.targets, options: request.options).map(Self.encodeApp)
        }
      case "getAppIcon":
        try performLookup(call, errorCode: "ERR_GET_ICON", result: result) { target in
          try self.scanner.getAppIcon(target: target).map { FlutterStandardTypedData(bytes: $0) }
        }
      case "isAppInstalled":
        try performLookup(call, errorCode: "ERR_QUERY", result: result) { target in
          try self.scanner.isAppInstalled(target: target)
        }
      case "isSystemApp":
        try performLookup(call, errorCode: "ERR_QUERY", result: result) { target in
          try self.scanner.isSystemApp(target: target)
        }
      case "isAppLaunchable":
        try performLookup(call, errorCode: "ERR_QUERY", result: result) { target in
          try self.scanner.isAppLaunchable(target: target)
        }
      case "openApp":
        let target = try AppMethodArguments(call.arguments, method: call.method).lookupTarget()
        performAppAction(target, errorCode: "ERR_OPEN", result: result, action: openApplication)
      case "revealAppInFinder":
        let target = try AppMethodArguments(call.arguments, method: call.method).lookupTarget()
        performAppAction(target, errorCode: "ERR_REVEAL", result: result) { url, finish in
          self.revealApplication(url)
          finish(nil)
        }
      case "moveAppToTrash":
        let target = try AppMethodArguments(call.arguments, method: call.method).lookupTarget()
        guard case .appPath(let path) = target else {
          throw AppScanError.invalidArgument("moveAppToTrash requires an absolute appPath")
        }
        performAppAction(target, errorCode: "ERR_TRASH", result: result) { url, finish in
          guard url.path == path else { throw AppActionError.unresolvedPath }
          try self.trashApplication(url)
          finish(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "ARG", message: error.localizedDescription, details: nil))
    }
  }

  private static func encodeApp(_ app: [String: Any]) -> [String: Any] {
    var encoded = app
    if let bytes = app["iconBytes"] as? Data {
      encoded["iconBytes"] = FlutterStandardTypedData(bytes: bytes)
    }
    return encoded
  }

  private func performLookup(
    _ call: FlutterMethodCall, errorCode: String, result: @escaping FlutterResult,
    operation: @escaping (AppLookupTarget) throws -> Any?
  ) throws {
    let arguments = try AppMethodArguments(call.arguments, method: call.method)
    let target = try arguments.lookupTarget()
    perform(errorCode: errorCode, result: result) { try operation(target) }
  }

  private func performAppAction(
    _ target: AppLookupTarget, errorCode: String, result: @escaping FlutterResult,
    action: @escaping (URL, @escaping (Error?) -> Void) throws -> Void
  ) {
    worker.async {
      func finish(_ error: Error?) {
        let response = error.map { failure in
          let native = failure as NSError
          let code = (failure as? AppActionError) == .unavailable ? "APP_UNAVAILABLE" : errorCode
          return FlutterError(
            code: code, message: native.localizedDescription,
            details: ["domain": native.domain, "code": native.code]
          )
        }
        DispatchQueue.main.async { result(response) }
      }

      do {
        guard let (url, _) = try self.scanner.resolveApp(target: target) else {
          throw AppActionError.unavailable
        }
        try action(url, finish)
      } catch {
        finish(error)
      }
    }
  }

  private func perform(
    errorCode: String, result: @escaping FlutterResult,
    operation: @escaping () throws -> Any?
  ) {
    worker.async {
      do {
        let response = try operation()
        DispatchQueue.main.async { result(response) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: errorCode, message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
