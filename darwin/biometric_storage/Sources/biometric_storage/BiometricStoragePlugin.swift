#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

public class BiometricStoragePlugin: NSObject, FlutterPlugin {

  private let impl = BiometricStorageImpl(
    storageError: { (code, message, details) -> Any in
      FlutterError(code: code, message: message, details: details)
    }, storageMethodNotImplemented: FlutterMethodNotImplemented)

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #elseif os(macOS)
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "biometric_storage", binaryMessenger: messenger)
    let instance = BiometricStoragePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    impl.handle(StorageMethodCall(method: call.method, arguments: call.arguments), result: result)
  }
}
