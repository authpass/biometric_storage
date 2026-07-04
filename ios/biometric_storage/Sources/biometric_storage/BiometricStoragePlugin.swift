import Flutter
//import UIKit

// The registered pluginClass (pubspec `ios: pluginClass: BiometricStoragePlugin`).
// Previously an ObjC shim forwarded to `SwiftBiometricStoragePlugin`; this is now
// a pure Swift plugin so the iOS implementation builds under Swift Package
// Manager (SPM cannot compile a mixed ObjC+Swift target). `@objc(...)` keeps the
// ObjC runtime name stable for the generated plugin registrant.
@objc(BiometricStoragePlugin)
public class BiometricStoragePlugin: NSObject, FlutterPlugin {
  private let impl = BiometricStorageImpl(storageError: { (code, message, details) -> Any in
    FlutterError(code: code, message: message, details: details)
  }, storageMethodNotImplemented: FlutterMethodNotImplemented)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "biometric_storage", binaryMessenger: registrar.messenger())
    let instance = BiometricStoragePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    impl.handle(StorageMethodCall(method: call.method, arguments: call.arguments), result: result)
  }
}
