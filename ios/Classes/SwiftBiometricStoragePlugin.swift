import Flutter
import UIKit
import LocalAuthentication

class InitOptions {
  init(params: [String: Any]) {
    authenticationValidityDurationSeconds = params["authenticationValidityDurationSeconds"] as? Int
    authenticationRequired = params["authenticationRequired"] as? Bool
  }
  let authenticationValidityDurationSeconds: Int!
  let authenticationRequired: Bool!
}

private func hpdebug(_ message: String) {
  print(message);
}

public class SwiftBiometricStoragePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "biometric_storage", binaryMessenger: registrar.messenger())
    let instance = SwiftBiometricStoragePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
  
  private var stores: [String: InitOptions] = [:]
  
  private func baseQuery(name: String) -> [String: Any] {
    return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "flutter_biometric_storage",
            kSecAttrAccount as String: name]
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    
    func requiredArg<T>(_ name: String, _ cb: (T) -> Void) {
      guard let args = call.arguments as? Dictionary<String, Any> else {
        result(FlutterError(code: "InvalidArguments", message: "Invalid arguments \(String(describing: call.arguments))", details: nil))
        return
      }
      guard let value = args[name] else {
        result(FlutterError(code: "InvalidArguments", message: "Missing argument \(name)", details: nil))
        return
      }
      cb(value as! T)
      return
    }
    
    if ("canAuthenticate" == call.method) {
      canAuthenticate(result: result)
    } else if ("init" == call.method) {
      requiredArg("name") { name in
        requiredArg("options") { options in
          stores[name] = InitOptions(params: options)
        }
      }
      result(true)
    } else if ("dispose" == call.method) {
      // nothing to dispose
      result(true)
    } else if ("read" == call.method) {
      requiredArg("name") { name in
        read(name, result)
      }
    } else if ("write" == call.method) {
      requiredArg("name") { name in
        requiredArg("content") { content in
          write(name, content, result)
        }
      }
    } else if ("delete" == call.method) {
      requiredArg("name") { name in
        delete(name, result)
      }
    } else {
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func read(_ name: String, _ result: @escaping FlutterResult) {

    var query = baseQuery(name: name)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseOperationPrompt as String] = "Unlock to access data"
    query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = true

    var item: CFTypeRef?

    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status != errSecItemNotFound else {
      result(nil)
      return
    }
    guard status == errSecSuccess else {
      result(FlutterError(code: "RetrieveError", message: "Error retrieving item. \(status)", details: nil))
      return
    }
    guard let existingItem = item as? [String : Any],
      let data = existingItem[kSecValueData as String] as? Data,
      let dataString = String(data: data, encoding: String.Encoding.utf8)
      else {
        result(FlutterError(code: "RetrieveError", message: "Unexpected data.", details: nil))
        return
    }
    result(dataString)
  }
  
  private func delete(_ name: String, _ result: @escaping FlutterResult) {
    let query = baseQuery(name: name)
//    query[kSecMatchLimit as String] = kSecMatchLimitOne
//    query[kSecReturnData as String] = true
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess else {
      handleOSStatusError(status, result, "writing data")
      return
    }
    result(true)
  }
  
  private func write(_ name: String, _ content: String, _ result: @escaping FlutterResult) {
    guard let initOptions = stores[name] else {
      result(FlutterError(code: "WriteError", message: "Storer was not initialized. \(name)", details: nil))
      return
    }
    
    var query = baseQuery(name: name)
    
    if (initOptions.authenticationRequired) {
      let context = LAContext()
      context.touchIDAuthenticationAllowableReuseDuration = Double(initOptions.authenticationValidityDurationSeconds)
      let access = SecAccessControlCreateWithFlags(nil, // Use the default allocator.
        kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
        .userPresence,
        nil) // Ignore any error.
      query.merge([
        kSecUseAuthenticationContext as String: context,
        kSecAttrAccessControl as String: access as Any,
        kSecUseOperationPrompt as String: "Unlock to save data",
      ]) { (_, new) in new }
    } else {
      hpdebug("No authentication required for \(name)")
    }
    query.merge([
//      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecValueData as String: content.data(using: String.Encoding.utf8) as Any,
    ]) { (_, new) in new }
    var status = SecItemAdd(query as CFDictionary, nil)
    if (status == errSecDuplicateItem) {
      hpdebug("Value already exists. updating.")
      let update = [kSecValueData as String: query[kSecValueData as String]]
      query.removeValue(forKey: kSecValueData as String)
      status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    }
    guard status == errSecSuccess else {
      handleOSStatusError(status, result, "writing data")
      return
    }
    result(nil)
  }
  
  private func handleOSStatusError(_ status: OSStatus, _ result: @escaping FlutterResult, _ message: String) {
    var errorMessage: String? = nil
    if #available(iOS 11.3, *) {
      errorMessage = SecCopyErrorMessageString(status, nil) as String?
    }
    
    result(FlutterError(code: "SecurityError", message: "Error while \(message): \(status): \(errorMessage ?? "Unknown")", details: nil))
  }
  
  private func canAuthenticate(result: @escaping FlutterResult) {
    let context = LAContext()
    if #available(iOS 10.0, *) {
      context.localizedCancelTitle = "Checking auth support"
    }
    var error: NSError?
    if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
      result("Success")
      return
    }
    guard let err = error else {
      result("ErrorUnknown")
      return
    }
    let laError = LAError(_nsError: err)
    NSLog("LAError: \(laError)");
    switch laError.code {
    case .touchIDNotAvailable:
      result("ErrorHwUnavailable")
      break;
    case .passcodeNotSet: fallthrough
    case .touchIDNotEnrolled:
      result("ErrorNoBiometricEnrolled")
      break;
    case .invalidContext: fallthrough
    default:
      result("ErrorUnknown")
      break;
    }
  }
}
