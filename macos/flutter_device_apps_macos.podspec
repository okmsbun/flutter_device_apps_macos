Pod::Spec.new do |s|
  s.name             = 'flutter_device_apps_macos'
  s.version          = '1.0.0'
  s.summary          = 'Independent macOS app discovery and management APIs for Flutter.'
  s.description      = s.summary
  s.homepage         = 'https://github.com/okmsbun/flutter_device_apps_macos'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'okmsbun'
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_device_apps_macos/Sources/flutter_device_apps_macos/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
