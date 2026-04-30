Pod::Spec.new do |s|
  s.name             = 'biometric_storage_darwin'
  s.version          = '0.0.1'
  s.summary          = 'Darwin implementation for biometric_storage.'
  s.description      = <<-DESC
Darwin implementation for biometric_storage.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../../LICENSE' }
  s.author           = { 'AuthPass' => 'support@authpass.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'biometric_storage_darwin/Sources/biometric_storage_darwin/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
