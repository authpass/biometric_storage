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
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '9.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  s.swift_version = '5.0'
end
