import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var selectedFiles: [String: URL] = [:]

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let filePicker = FlutterMethodChannel(
      name: "flutter_device_apps_macos_example/file_picker",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    filePicker.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "chooseFile":
        self.chooseFile(result: result)
      case "releaseFile":
        if let id = call.arguments as? String {
          self.selectedFiles.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func chooseFile(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.beginSheetModal(for: self) { [weak self] response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      guard let self = self else {
        url.stopAccessingSecurityScopedResource()
        result(nil)
        return
      }
      let id = UUID().uuidString
      self.selectedFiles[id] = url
      result(["id": id, "path": url.path])
    }
  }

  deinit {
    for url in selectedFiles.values { url.stopAccessingSecurityScopedResource() }
  }
}
