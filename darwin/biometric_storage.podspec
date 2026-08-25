#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint biometric_storage.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'biometric_storage'
  s.version          = '0.0.1'
  s.summary          = 'Encrypted file store, optionally secured by biometric lock.'
  s.description      = <<-DESC
Encrypted file store, optionally secured by biometric lock, backed by the
keychain and LocalAuthentication on iOS and macOS.
Downloaded by pub (not CocoaPods).
                       DESC
  s.homepage         = 'https://github.com/authpass/biometric_storage'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Herbert Poul' => 'herbert@codeux.design' }
  s.source           = { :path => '.' }
  s.documentation_url = 'https://pub.dev/packages/biometric_storage'
  s.source_files     = 'biometric_storage/Sources/biometric_storage/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
