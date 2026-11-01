import Cocoa
import FlutterMacOS

public class FlutterDeviceAppsMacosPlugin: NSObject, FlutterPlugin {
  private let scanner: MacosAppScanner
  private let worker = DispatchQueue(label: "flutter_device_apps_macos/scan", qos: .userInitiated)

  public override init() {
    scanner = MacosAppScanner()
    super.init()
  }

  init(scanner: MacosAppScanner) {
    self.scanner = scanner
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
