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
    darwinTouchIDAuthenticationAllowableReuseDuration = params["darwinTouchIDAuthenticationAllowableReuseDurationSeconds"] as? Int
    darwinTouchIDAuthenticationForceReuseContextDuration = params["darwinTouchIDAuthenticationForceReuseContextDurationSeconds"] as? Int
    authenticationRequired = params["authenticationRequired"] as? Bool
    darwinBiometricOnly = params["darwinBiometricOnly"] as? Bool
    darwinKeychainAccessGroup = params["darwinKeychainAccessGroup"] as? String
  }
  let darwinTouchIDAuthenticationAllowableReuseDuration: Int?
  let darwinTouchIDAuthenticationForceReuseContextDuration: Int?
  let authenticationRequired: Bool!
  let darwinBiometricOnly: Bool!
  /// kSecAttrAccessGroup, so an app extension of the same app can read the
  /// item. Part of the item's identity — see the dart side for the caveats.
  let darwinKeychainAccessGroup: String?
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
  
  private var stores: [String: BiometricStorageFile] = [:]
  private let storageError: StorageError
  private let storageMethodNotImplemented: Any

  private func storageError(code: String, message: String?, details: Any?) -> Any {
    return storageError(code, message, details)
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
    func requireStorage(_ name: String, _ cb: (BiometricStorageFile) -> Void) {
      guard let file = stores[name] else {
        result(storageError(code: "InvalidArguments", message: "Storage was not initialized \(name)", details: nil))
        return
      }
      cb(file)
    }
    
    if ("canAuthenticate" == call.method) {
      requiredArg("options") { options in
        let initOptions = InitOptions(params: options)
        canAuthenticate(options: initOptions, result: result)
      }
    } else if ("init" == call.method) {
      requiredArg("name") { (name: String) in
        requiredArg("options") { (options: [String: Any]) in
          // The success reply belongs on the success path. It used to sit after
          // this block and ran unconditionally, so a missing or mistyped
          // argument replied with the error and then replied `true` as well —
          // Flutter discards the second reply and logs "Reply already
          // submitted", leaving the caller believing init had succeeded.
          if stores[name] != nil {
            // Mirrors Android: forceInit means "assert this was not already
            // initialised", and without it a repeat init is a no-op reporting
            // false. Neither was implemented here at all before.
            let args = call.arguments as? [String: Any]
            if args?["forceInit"] as? Bool == true {
              result(storageError(
                code: "AlreadyInitialized",
                message: "A storage file with the name '\(name)' was already initialized.",
                details: nil))
            } else {
              result(false)
            }
            return
          }
          stores[name] = BiometricStorageFile(name: name, initOptions: InitOptions(params: options), storageError: storageError)
          result(true)
        }
      }
    } else if ("dispose" == call.method) {
      // This used to be a no-op replying `true`, which made the whole feature
      // silently useless here: `stores` kept the entry, so the next `init`
      // took the short circuit above, discarded the freshly passed
      // InitOptions and replied `false` — reporting success at every step
      // while leaving the file on its original configuration. Removing the
      // entry is what lets a later init apply new options.
      //
      // The keychain item itself is deliberately untouched; this reconfigures
      // rather than erases. Replies whether there was anything to forget, so
      // a repeat dispose is not an error.
      requiredArg("name") { (name: String) in
        result(stores.removeValue(forKey: name) != nil)
      }
    } else if ("read" == call.method) {
      requiredArg("name") { name in
        requiredArg("iosPromptInfo") { promptInfo in
          requireStorage(name) { file in
            file.read(result, IOSPromptInfo(params: promptInfo))
          }
        }
      }
    } else if ("write" == call.method) {
      requiredArg("name") { name in
        requiredArg("content") { content in
          requiredArg("iosPromptInfo") { promptInfo in
            requireStorage(name) { file in
              file.write(content, result, IOSPromptInfo(params: promptInfo))
            }
          }
        }
      }
    } else if ("delete" == call.method) {
      requiredArg("name") { name in
        requiredArg("iosPromptInfo") { promptInfo in
          requireStorage(name) { file in
            file.delete(result, IOSPromptInfo(params: promptInfo))
          }
        }
      }
    } else {
      result(storageMethodNotImplemented)
    }
  }
  

  private func canAuthenticate(options: InitOptions, result: @escaping StorageCallback) {
    var error: NSError?
    let context = LAContext()
    let policy: LAPolicy = options.darwinBiometricOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
    if context.canEvaluatePolicy(policy, error: &error) {
      result("Success")
      return
    }
    guard let err = error else {
      // Same reasoning as the default arm below: "cannot tell" is not
      // "this plugin does not work on this platform".
      result("ErrorStatusUnknown")
      return
    }
    let laError = LAError(_nsError: err)
    NSLog("LAError: \(laError)");
    switch laError.code {
    case .touchIDNotAvailable:
      result("ErrorHwUnavailable")
      break;
    case .passcodeNotSet:
      result("ErrorPasscodeNotSet")
      break;
    case .touchIDNotEnrolled:
      result("ErrorNoBiometricEnrolled")
      break;
    case .biometryLockout:
      // Recoverable — too many failed attempts, and the user can retry later or
      // fall back to the device credential. Named explicitly rather than left
      // to the default arm so that the "unmapped" log there keeps meaning
      // "something we have not seen", instead of firing on the common case.
      // androidx's BiometricManager has no lockout status at all, so Android
      // callers already get Success here and discover the lockout at the
      // prompt; reporting "cannot tell, try it" converges the two platforms.
      result("ErrorStatusUnknown")
      break;
    case .invalidContext: fallthrough
    default:
      // Not "ErrorUnknown": the Dart side maps that to
      // CanAuthenticateResponse.unsupported, whose own doc reads "Plugin does
      // not support platform", so a biometryLockout — too many failed attempts,
      // and recoverable — told callers the plugin did not work on iOS at all.
      // ErrorStatusUnknown is what Android reports for a code it does not
      // recognise, and it says what is actually true: we cannot tell.
      NSLog("Unmapped LAError \(laError.code.rawValue), reporting status unknown");
      result("ErrorStatusUnknown")
      break;
    }
  }
}

typealias StoredContext = (context: LAContext, expireAt: Date)

class BiometricStorageFile {
  private let name: String
  private let initOptions: InitOptions
  private var _context: StoredContext?
  private var context: LAContext {
    get {
      if let context = _context {
        if context.expireAt.timeIntervalSinceNow < 0 {
          // already expired.
          _context = nil
        } else {
          return context.context
        }
      }
      
      let context = LAContext()
      if (initOptions.authenticationRequired) {
        if let duration = initOptions.darwinTouchIDAuthenticationAllowableReuseDuration {
          if #available(OSX 10.12, *) {
            context.touchIDAuthenticationAllowableReuseDuration = Double(duration)
          } else {
            // Fallback on earlier versions
            hpdebug("Pre OSX 10.12 no touchIDAuthenticationAllowableReuseDuration available. ignoring.")
          }
        }
        
        if let duration = initOptions.darwinTouchIDAuthenticationForceReuseContextDuration {
          _context = (context: context, expireAt: Date(timeIntervalSinceNow: Double(duration)))
        }
      }
      return context
    }
  }

  /// The authentication context to hand to a keychain query, carrying the reason
  /// the prompt should give for itself.
  ///
  /// This replaces `kSecUseOperationPrompt`, deprecated since iOS 14 / macOS 11:
  /// the reason now travels on the context rather than in the query. It is set
  /// on every call because `context` may return a context reused across calls.
  private func authenticationContext(reason: String?) -> LAContext {
    let context = self.context
    // Assigned unconditionally, including when empty. `context` may be one
    // reused across calls when darwinTouchIDAuthenticationForceReuseContextDuration
    // is set, so skipping the assignment would leave the *previous* call's
    // reason in place — a read showing the save prompt's wording. The query key
    // this replaced was per-query and could not carry over like that.
    context.localizedReason = reason ?? ""
    return context
  }

  private let storageError: StorageError

  init(name: String, initOptions: InitOptions, storageError: @escaping StorageError) {
    self.name = name
    self.initOptions = initOptions
    self.storageError = storageError
  }
  
  private func baseQuery(_ result: @escaping StorageCallback) -> [String: Any]? {
    var query = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "flutter_biometric_storage",
      kSecAttrAccount as String: name,
    ] as [String : Any]
    if let accessGroup = initOptions.darwinKeychainAccessGroup {
      // Has to be on every query, not just the write: the access group is part
      // of an item's identity, so a read without it will not find an item
      // written with it.
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    if initOptions.authenticationRequired {
      guard let access = accessControl(result) else {
        return nil
      }
      if #available(iOS 13.0, macOS 10.15, *) {
        query[kSecUseDataProtectionKeychain as String] = true
      }
      query[kSecAttrAccessControl as String] = access
    }
    return query
  }
  
  private func accessControl(_ result: @escaping StorageCallback) -> SecAccessControl? {
    let accessControlFlags: SecAccessControlCreateFlags
    
    if initOptions.darwinBiometricOnly {
      if #available(iOS 11.3, *) {
        accessControlFlags =  .biometryCurrentSet
      } else {
        accessControlFlags = .touchIDCurrentSet
      }
    } else {
      accessControlFlags = .userPresence
    }
        
//      access = SecAccessControlCreateWithFlags(nil,
//                                               kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
//                                               accessControlFlags,
//                                               &error)
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      nil, // Use the default allocator.
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      accessControlFlags,
      &error) else {
      hpdebug("Error while creating access control flags. \(String(describing: error))")
      result(storageError("writing data", "error writing data", "\(String(describing: error))"));
      return nil
    }

    return access
  }
  
  func read(_ result: @escaping StorageCallback, _ promptInfo: IOSPromptInfo) {
    // No lockout check before the query, deliberately. Asking
    // canEvaluatePolicy up front would answer about a *fresh* context, while
    // the query below may carry one that has already authenticated — see
    // `context`, which keeps one alive for
    // darwinTouchIDAuthenticationForceReuseContextDuration. A read inside that
    // window succeeds without biometry, so a pre-flight check would refuse a
    // read that works. It would also turn a read of a name that was never
    // written into an error rather than the nil that means "nothing stored".
    // The check in handleOSStatusError sees the lockout either way, and only
    // once the attempt has actually failed.
    guard var query = baseQuery(result) else {
      return;
    }
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = true
    query[kSecUseAuthenticationContext as String] =
      authenticationContext(reason: promptInfo.accessTitle)
    
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
        result(storageError("RetrieveError", "Unexpected data.", nil))
        return
    }
    result(dataString)
  }
  
  func delete(_ result: @escaping StorageCallback, _ promptInfo: IOSPromptInfo) {
    guard let query = baseQuery(result) else {
      return;
    }
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
  
  func write(_ content: String, _ result: @escaping StorageCallback, _ promptInfo: IOSPromptInfo) {
    guard var query = baseQuery(result) else {
      return;
    }

    if (initOptions.authenticationRequired) {
      query.merge([
        kSecUseAuthenticationContext as String:
          authenticationContext(reason: promptInfo.saveTitle),
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
  
  private func handleOSStatusError(_ status: OSStatus, _ result: @escaping StorageCallback, _ message: String) {
    var errorMessage: String? = nil
    if #available(iOS 11.3, OSX 10.12, *) {
      errorMessage = SecCopyErrorMessageString(status, nil) as String?
    }
    let code: String
    switch status {
    case errSecUserCanceled:
      code = "AuthError:UserCanceled"
    case errSecAuthFailed:
      // One status, many causes. The Keychain does not distinguish "biometry
      // is locked out" from "the user failed the check" from "this item's
      // access control can never be satisfied again", because we let
      // SecItemCopyMatching drive LocalAuthentication internally rather than
      // calling LAContext.evaluatePolicy ourselves and reading its LAError.
      //
      // isBiometryLockedOut() recovers the one distinction that is worth a
      // different response from the caller, and it asks LocalAuthentication
      // rather than guessing from the status. Everything else stays together
      // under AuthFailed: the right answer to all of it is to authenticate
      // again, and the plugin cannot tell which of them it is holding.
      //
      // Note what this deliberately does NOT claim. A reader familiar with
      // issue #128 will expect invalidation — enrolled biometrics changed, so
      // a `.biometryCurrentSet` item is unreadable forever — to be reported as
      // such, the way Android reports KeyPermanentlyInvalidatedException. It
      // cannot be: it arrives here as the same errSecAuthFailed as a user who
      // simply looked away (#80) or a device whose sensor the system will not
      // use (#101), and in those two the value is intact. Calling all three
      // "invalidated" would tell an app its data is gone whenever a prompt was
      // failed, and an app that acts on that deletes a readable secret.
      //
      // Restricting the branch to errSecAuthFailed assumes a locked-out read
      // never surfaces under some other status. That rests on observed
      // behaviour of SecItemCopyMatching with kSecUseAuthenticationContext,
      // not on a document enumerating what a locked-out read may return. The
      // cost of being wrong is only a lockout reported as AuthFailed, which
      // asks the user to try again — not a claim about their data.
      code = isBiometryLockedOut() ? "AuthError:LockoutPermanent" : "AuthError:AuthFailed"
    default:
      code = "SecurityError"
    }
    
    result(storageError(code, "Error while \(message): \(status): \(errorMessage ?? "Unknown")", nil))
  }

  /// Whether biometry is locked out right now, asked of LocalAuthentication
  /// through `canEvaluatePolicy` — synchronous, no UI, and documented to
  /// report `.biometryLockout`. The alternative is to infer it from the
  /// Keychain's `OSStatus`, which cannot be done: Apple guarantees only that
  /// `errSecAuthFailed` means *some* authentication failure.
  ///
  /// Called after a failed attempt rather than before one, from
  /// `handleOSStatusError`, so it also sees a lockout that the failing attempt
  /// is what caused.
  ///
  /// iOS and macOS have a single biometric lockout state. Where Android splits
  /// ERROR_LOCKOUT from ERROR_LOCKOUT_PERMANENT, `biometryLockout` clears only
  /// when the user enters their passcode and never by waiting, so it is
  /// reported as "AuthError:LockoutPermanent": the recovery matches Android's
  /// permanent case.
  ///
  /// Answers false for a store this cannot speak for, rather than guessing:
  ///
  /// * one that does not authenticate at all, and
  /// * one with `darwinBiometricOnly: false`, whose items carry a
  ///   `.userPresence` access control. The policy that matches it,
  ///   `.deviceOwnerAuthentication`, is satisfiable whenever a passcode is set,
  ///   so `canEvaluatePolicy` would never report a lockout for it — correctly,
  ///   since such an item stays reachable through the passcode while biometry
  ///   is locked. An `errSecAuthFailed` there is an ordinary failure and is
  ///   reported as one.
  private func isBiometryLockedOut() -> Bool {
    guard initOptions.authenticationRequired, initOptions.darwinBiometricOnly else {
      return false
    }
    var error: NSError?
    // A fresh, throwaway context: reusing `self.context` here would touch the
    // authentication state kept alive for
    // darwinTouchIDAuthenticationForceReuseContextDuration, which this probe
    // has no business touching.
    let probeContext = LAContext()
    if probeContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
      return false
    }
    guard let laError = error else {
      return false
    }
    // Not every refusal is a lockout — no enrollment and no hardware land here
    // too, and neither says anything about this failure.
    return LAError(_nsError: laError).code == .biometryLockout
  }
}
