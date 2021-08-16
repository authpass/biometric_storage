// Shared file between iOS and Mac OS
// make sure they stay in sync.

import Foundation
import LocalAuthentication

typealias StorageCallback = (Any?) -> Void
typealias StorageError = (String, String?, Any?) -> Any

struct StorageMethodCall {
  let method: String
  let arguments: Any?
}

class InitOptions {
  init(params: [String: Any]) {
    authenticationValidityDurationSeconds = params["authenticationValidityDurationSeconds"] as? Int
    authenticationRequired = params["authenticationRequired"] as? Bool
  }
  let authenticationValidityDurationSeconds: Int!
  let authenticationRequired: Bool!
}

class IOSPromptInfo {
  init(params: [String: Any]) {
    saveTitle = params["saveTitle"] as? String
    accessTitle = params["accessTitle"] as? String
  }
  let saveTitle: String!
  let accessTitle: String!
}

private func hpdebug(_ message: String) {
  print(message);
}

class BiometricStorageImpl {
  
  init(storageError: @escaping StorageError, storageMethodNotImplemented: Any) {
    self.storageError = storageError
    self.storageMethodNotImplemented = storageMethodNotImplemented
  }
  
  private var stores: [String: InitOptions] = [:]
  private let storageError: StorageError
  private let storageMethodNotImplemented: Any

  private func storageError(code: String, message: String?, details: Any?) -> Any {
    return storageError(code, message, details)
  }

  private func baseQuery(name: String) -> [String: Any] {
    return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "flutter_biometric_storage",
            kSecAttrAccount as String: name]
  }

  public func handle(_ call: StorageMethodCall, result: @escaping StorageCallback) {
    
    func requiredArg<T>(_ name: String, _ cb: (T) -> Void) {
      guard let args = call.arguments as? Dictionary<String, Any> else {
        result(storageError(code: "InvalidArguments", message: "Invalid arguments \(String(describing: call.arguments))", details: nil))
        return
      }
      guard let value = args[name] else {
        result(storageError(code: "InvalidArguments", message: "Missing argument \(name)", details: nil))
        return
      }
      guard let valueTyped = value as? T else {
        result(storageError(code: "InvalidArguments", message: "Invalid argument for \(name): expected \(T.self) got \(value)", details: nil))
        return
      }
      cb(valueTyped)
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
        requiredArg("iosPromptInfo") { promptInfo in
          read(name, result, IOSPromptInfo(params: promptInfo))
        }
      }
    } else if ("write" == call.method) {
      requiredArg("name") { name in
        requiredArg("content") { content in
          requiredArg("iosPromptInfo") { promptInfo in
            write(name, content, result, IOSPromptInfo(params: promptInfo))
          }
        }
      }
    } else if ("delete" == call.method) {
      requiredArg("name") { name in
        requiredArg("iosPromptInfo") { promptInfo in
          delete(name, result, IOSPromptInfo(params: promptInfo))
        }
      }
    } else {
      result(storageMethodNotImplemented)
    }
  }
  
  private func read(_ name: String, _ result: @escaping StorageCallback, _ promptInfo: IOSPromptInfo) {
    
    var query = baseQuery(name: name)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseOperationPrompt as String] = promptInfo.accessTitle
    query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = true
    
    var item: CFTypeRef?
    
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status != errSecItemNotFound else {
      result(nil)
      return
    }
    guard status == errSecSuccess else {
      handleOSStatusError(status, result, "Error retrieving item. \(status)")
      return
    }
    guard let existingItem = item as? [String : Any],
      let data = existingItem[kSecValueData as String] as? Data,
      let dataString = String(data: data, encoding: String.Encoding.utf8)
      else {
        result(storageError(code: "RetrieveError", message: "Unexpected data.", details: nil))
        return
    }
    result(dataString)
  }
  
  private func delete(_ name: String, _ result: @escaping StorageCallback, _ promptInfo: IOSPromptInfo) {
    let query = baseQuery(name: name)
    //    query[kSecMatchLimit as String] = kSecMatchLimitOne
    //    query[kSecReturnData as String] = true
    let status = SecItemDelete(query as CFDictionary)
    if status == errSecSuccess {
      result(true)
      return
    }
    if status == errSecItemNotFound {
      hpdebug("Item not in keychain. Nothing to delete.")
      result(true)
      return
    }
    handleOSStatusError(status, result, "writing data")
  }
  
  private func write(_ name: String, _ content: String, _ result: @escaping StorageCallback, _ promptInfo: IOSPromptInfo) {
    guard let initOptions = stores[name] else {
      result(storageError(code: "WriteError", message: "Storage was not initialized. \(name)", details: nil))
      return
    }
    
    var query = baseQuery(name: name)
    
    if (initOptions.authenticationRequired) {
      let context = LAContext()
      if initOptions.authenticationValidityDurationSeconds > 0 {
        if #available(OSX 10.12, *) {
          context.touchIDAuthenticationAllowableReuseDuration = Double(initOptions.authenticationValidityDurationSeconds)
        } else {
          // Fallback on earlier versions
          hpdebug("Pre OSX 10.12 no touchIDAuthenticationAllowableReuseDuration available. ignoring.")
        }
      }
      let access = SecAccessControlCreateWithFlags(nil, // Use the default allocator.
        kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
        .userPresence,
        nil) // Ignore any error.
      query.merge([
        kSecUseAuthenticationContext as String: context,
        kSecAttrAccessControl as String: access as Any,
      ]) { (_, new) in new }
      if let operationPrompt = promptInfo.saveTitle {
        query[kSecUseOperationPrompt as String] = operationPrompt
      }
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
  
  private func handleOSStatusError(_ status: OSStatus, _ result: @escaping StorageCallback, _ message: String) {
    var errorMessage: String? = nil
    if #available(iOS 11.3, OSX 10.12, *) {
      errorMessage = SecCopyErrorMessageString(status, nil) as String?
    }
    let code: String
    switch status {
    case errSecUserCanceled:
      code = "AuthError:UserCanceled"
    default:
      code = "SecurityError"
    }
    
    result(storageError(code: code, message: "Error while \(message): \(status): \(errorMessage ?? "Unknown")", details: nil))
  }
  
  private func canAuthenticate(result: @escaping StorageCallback) {
    let context = LAContext()
    if #available(iOS 10.0, OSX 10.12, *) {
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
