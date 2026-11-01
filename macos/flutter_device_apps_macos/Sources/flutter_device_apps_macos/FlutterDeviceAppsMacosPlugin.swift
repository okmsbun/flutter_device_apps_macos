import Cocoa
import FlutterMacOS

public class FlutterDeviceAppsMacosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_device_apps_macos",
      binaryMessenger: registrar.messenger
    )
    let instance = FlutterDeviceAppsMacosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }
}
