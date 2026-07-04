#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint biometric_storage.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'biometric_storage'
  s.version          = '0.0.1'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  # Sources live under the SwiftPM layout (Sources/<name>/) so SPM and CocoaPods
  # share one source tree; see ios/biometric_storage/Package.swift. The plugin is
  # now pure Swift (the ObjC registration shim was folded into the Swift class),
  # so there are no public ObjC headers to expose.
  s.source_files = 'biometric_storage/Sources/biometric_storage/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '9.0'

  # Flutter.framework does not contain a i386 slice. Only x86_64 simulators are supported.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  s.swift_version = '5.0'
end

