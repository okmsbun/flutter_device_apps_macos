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
    guard call.method == "listApps" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let options: AppListOptions
    do {
      options = try AppListOptions(arguments: call.arguments)
    } catch {
      result(FlutterError(code: "ARG", message: error.localizedDescription, details: nil))
      return
    }
    worker.async {
      do {
        let apps = try self.scanner.listApps(options: options).map { app -> [String: Any] in
          var encoded = app
          if let bytes = app["iconBytes"] as? Data {
            encoded["iconBytes"] = FlutterStandardTypedData(bytes: bytes)
          }
          return encoded
        }
        DispatchQueue.main.async { result(apps) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "ERR_LIST", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
