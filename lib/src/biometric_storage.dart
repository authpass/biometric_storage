import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Not `dart:io` directly: importing it here unconditionally is what made the
// whole package report as WebAssembly-incompatible, since this library is
// reachable from the web implementation. The io branch still uses `dart:io`.
import 'platform_os_io.dart'
    if (dart.library.js_interop) 'platform_os_web.dart';

final _logger = Logger('biometric_storage');

/// Reason for not supporting authentication.
/// **As long as this is NOT [unsupported] you can still use the secure
/// storage without biometric storage** (By setting
/// [StorageFileInitOptions.authenticationRequired] to `false`).
enum CanAuthenticateResponse {
  success,
  errorHwUnavailable,
  errorNoBiometricEnrolled,
  errorNoHardware,

  /// Passcode is not set (iOS/MacOS) or no user credentials (on macos).
  errorPasscodeNotSet,

  /// Used on android if the status is unknown.
  /// https://developer.android.com/reference/androidx/biometric/BiometricManager#BIOMETRIC_STATUS_UNKNOWN
  statusUnknown,

  /// Plugin does not support platform. This should no longer be the case.
  unsupported,
}

const _canAuthenticateMapping = {
  'Success': CanAuthenticateResponse.success,
  'ErrorHwUnavailable': CanAuthenticateResponse.errorHwUnavailable,
  'ErrorNoBiometricEnrolled': CanAuthenticateResponse.errorNoBiometricEnrolled,
  'ErrorNoHardware': CanAuthenticateResponse.errorNoHardware,
  'ErrorPasscodeNotSet': CanAuthenticateResponse.errorPasscodeNotSet,
  'ErrorUnknown': CanAuthenticateResponse.unsupported,
  'ErrorStatusUnknown': CanAuthenticateResponse.statusUnknown,
};

/// Why an [AuthException] was raised.
///
/// New members may be added in a minor release, so a `switch` over this should
/// carry a `default` rather than being exhaustive. Several platform conditions
/// still arrive as [unknown] — Android reports every `BiometricPrompt` error
/// beyond cancel and timeout that way, lockout included — and narrowing them is
/// only a minor-version change while this contract holds.
enum AuthExceptionCode {
  /// User taps the cancel/negative button or presses `back`.
  userCanceled,

  /// Authentication prompt is canceled due to another reason
  /// (like when biometric sensor becamse unavailable like when
  /// user switches between apps, logsout, etc).
  canceled,
  unknown,
  timeout,
  linuxAppArmorDenied,
}

const _authErrorCodeMapping = {
  'AuthError:UserCanceled': AuthExceptionCode.userCanceled,
  'AuthError:Canceled': AuthExceptionCode.canceled,
  'AuthError:Timeout': AuthExceptionCode.timeout,
};

/// Why a [BiometricStorageException] was raised.
///
/// New members may be added in a minor release, so a `switch` over this should
/// carry a `default` rather than being exhaustive.
enum BiometricStorageExceptionCode {
  /// [BiometricStorage.getStorage] was called for a name already opened in this
  /// runtime, with `forceInit: true`. A caller's own mistake: pick a different
  /// name, or drop the flag.
  alreadyInitialized,

  /// The platform's credential store refused the operation — as opposed to
  /// simply not holding a value, which is reported as `null` from
  /// [BiometricStorageFile.read] and `false` from a delete. Worth surfacing to
  /// the user or retrying; not a programming error.
  storageFailure,

  /// Raised before this enum existed, or by a path that has not been
  /// classified. Treat as [storageFailure] for handling purposes.
  unknown,
}

class BiometricStorageException implements Exception {
  BiometricStorageException(
    this.message, {
    this.code = BiometricStorageExceptionCode.unknown,
  });

  final String message;

  /// Defaults to [BiometricStorageExceptionCode.unknown] so that constructing
  /// one positionally — as every caller did before 6.0.0-dev.4 — still works.
  final BiometricStorageExceptionCode code;

  @override
  String toString() {
    return 'BiometricStorageException{code: $code, message: $message}';
  }
}

/// Exceptions during authentication operations.
/// See [AuthExceptionCode] for details.
class AuthException implements Exception {
  AuthException(this.code, this.message);

  final AuthExceptionCode code;
  final String message;

  @override
  String toString() {
    return 'AuthException{code: $code, message: $message}';
  }
}

class StorageFileInitOptions {
  StorageFileInitOptions({
    Duration? androidAuthenticationValidityDuration,
    Duration? darwinTouchIDAuthenticationAllowableReuseDuration,
    this.darwinTouchIDAuthenticationForceReuseContextDuration,
    @Deprecated(
      'use use androidAuthenticationValidityDuration, iosTouchIDAuthenticationAllowableReuseDuration or iosTouchIDAuthenticationForceReuseContextDuration instead',
    )
    int authenticationValidityDurationSeconds = -1,
    this.authenticationRequired = true,
    this.androidBiometricOnly = true,
    this.darwinBiometricOnly = true,
    this.darwinKeychainAccessGroup,
  }) : androidAuthenticationValidityDuration =
           androidAuthenticationValidityDuration ??
           (authenticationValidityDurationSeconds <= 0
               ? null
               : Duration(seconds: authenticationValidityDurationSeconds)),
       darwinTouchIDAuthenticationAllowableReuseDuration =
           darwinTouchIDAuthenticationAllowableReuseDuration ??
           (authenticationValidityDurationSeconds <= 0
               ? null
               : Duration(seconds: authenticationValidityDurationSeconds));

  /// see https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder#setUserAuthenticationParameters(int,%20int)
  final Duration? androidAuthenticationValidityDuration;

  /// see https://developer.apple.com/documentation/localauthentication/lacontext/1622329-touchidauthenticationallowablere
  /// > If the user unlocks the device using Touch ID within the specified time interval, then authentication for the receiver succeeds automatically, without prompting the user for Touch ID. This bypasses a scenario where the user unlocks the device and then is almost immediately prompted for another fingerprint.
  /// and https://developer.apple.com/documentation/localauthentication/accessing_keychain_items_with_face_id_or_touch_id
  /// > Note that this grace period applies specifically to device unlock with Touch ID, not keychain retrieval authentications
  ///
  /// If you want to avoid requiring authentication after a successful
  /// keychain retrieval see [darwinTouchIDAuthenticationForceReuseContextDuration]
  final Duration? darwinTouchIDAuthenticationAllowableReuseDuration;

  /// To prevent forcing the user to authenticate again after unlocking once
  /// we can reuse the `LAContext` object for the given amount of time.
  /// see https://github.com/authpass/biometric_storage/pull/73
  /// This is pretty much undocumented behavior, but works similar to
  /// `androidAuthenticationValidityDuration`.
  ///
  /// See also [darwinTouchIDAuthenticationAllowableReuseDuration]
  final Duration? darwinTouchIDAuthenticationForceReuseContextDuration;

  /// Whether an authentication is required. if this is
  /// false NO BIOMETRIC CHECK WILL BE PERFORMED! and the value
  /// will simply be save encrypted. (default: true)
  final bool authenticationRequired;

  /// Only makes difference on Android, where if set true, you can't use
  /// PIN/pattern/password to get the file.
  /// On Android < 30 this will always be ignored. (always `true`)
  /// https://github.com/authpass/biometric_storage/issues/12#issuecomment-900358154
  ///
  /// Also: this **must** be `true` if [androidAuthenticationValidityDuration]
  /// is null.
  /// https://github.com/authpass/biometric_storage/issues/12#issuecomment-902508609
  final bool androidBiometricOnly;

  /// Only for iOS and macOS:
  /// Uses `.biometryCurrentSet` if true, `.userPresence` otherwise.
  /// https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/1392879-userpresence
  final bool darwinBiometricOnly;

  /// Only for iOS and macOS: the keychain access group to store the item in,
  /// so an app extension of the same app can read it
  /// (`kSecAttrAccessGroup`).
  ///
  /// Must be one of the `keychain-access-groups` entitlements of *both* the
  /// app and the extension, and is prefixed by the team id, so the usual value
  /// looks like `ABCDE12345.com.example.app`. On macOS the app also has to be
  /// signed for the entitlement to take effect.
  ///
  /// The access group is part of an item's identity: an item written without
  /// one cannot be read back with one, and vice versa. Changing this for an
  /// existing file makes its contents unreadable rather than raising an error,
  /// so treat a value here as a new, separate item — see
  /// https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps
  final String? darwinKeychainAccessGroup;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'androidAuthenticationValidityDurationSeconds':
        androidAuthenticationValidityDuration?.inSeconds,
    'darwinTouchIDAuthenticationAllowableReuseDurationSeconds':
        darwinTouchIDAuthenticationAllowableReuseDuration?.inSeconds,
    'darwinTouchIDAuthenticationForceReuseContextDurationSeconds':
        darwinTouchIDAuthenticationForceReuseContextDuration?.inSeconds,
    'authenticationRequired': authenticationRequired,
    'androidBiometricOnly': androidBiometricOnly,
    'darwinBiometricOnly': darwinBiometricOnly,
    'darwinKeychainAccessGroup': darwinKeychainAccessGroup,
  };
}

/// Android specific configuration of the prompt displayed for biometry.
class AndroidPromptInfo {
  const AndroidPromptInfo({
    this.title = 'Authenticate to unlock data',
    this.subtitle,
    this.description,
    this.negativeButton = 'Cancel',
    this.confirmationRequired = true,
  });

  final String title;
  final String? subtitle;
  final String? description;
  final String negativeButton;
  final bool confirmationRequired;

  static const defaultValues = AndroidPromptInfo();

  Map<String, dynamic> _toJson() => <String, dynamic>{
    'title': title,
    'subtitle': subtitle,
    'description': description,
    'negativeButton': negativeButton,
    'confirmationRequired': confirmationRequired,
  };
}

/// iOS **and MacOS** specific configuration of the prompt displayed for biometry.
///
/// **These strings are not shown on a Face ID device.** They are passed to the
/// system as `LAContext.localizedReason`, and Face ID authenticates against a
/// HUD that has no room for a reason: the panel shows the Face ID glyph and the
/// words "Face ID", and the "not recognized" alert that follows a failure offers
/// only retry and cancel. Verified on an iPhone Xr running iOS 18.7.9, against
/// both `localizedReason` and the deprecated `kSecUseOperationPrompt` set at the
/// same time — neither was rendered.
///
/// They are still worth setting: Touch ID devices draw the reason in the
/// authentication alert, and macOS shows it too.
class IosPromptInfo {
  const IosPromptInfo({
    this.saveTitle = 'Unlock to save data',
    this.accessTitle = 'Unlock to access data',
  });

  final String saveTitle;
  final String accessTitle;

  static const defaultValues = IosPromptInfo();

  Map<String, dynamic> _toJson() => <String, dynamic>{
    'saveTitle': saveTitle,
    'accessTitle': accessTitle,
  };
}

/// Wrapper for platform specific prompt infos.
class PromptInfo {
  const PromptInfo({
    this.androidPromptInfo = AndroidPromptInfo.defaultValues,
    this.iosPromptInfo = IosPromptInfo.defaultValues,
    this.macOsPromptInfo = IosPromptInfo.defaultValues,
  });
  static const defaultValues = PromptInfo();

  final AndroidPromptInfo androidPromptInfo;
  final IosPromptInfo iosPromptInfo;
  final IosPromptInfo macOsPromptInfo;
}

/// Main plugin class to interact with. Is always a singleton right now,
/// factory constructor will always return the same instance.
///
/// * call [canAuthenticate] to check support on the platform/device.
/// * call [getStorage] to initialize a storage.
abstract class BiometricStorage extends PlatformInterface {
  // Returns singleton instance.
  factory BiometricStorage() => _instance;

  BiometricStorage.create() : super(token: _token);

  static BiometricStorage _instance = MethodChannelBiometricStorage();

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [UrlLauncherPlatform] when they register themselves.
  static set instance(BiometricStorage instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  static const Object _token = Object();

  /// Returns whether this device supports biometric/secure storage or
  /// the reason [CanAuthenticateResponse] why it is not supported.
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  });

  /// Returns true when there is an AppArmor error when trying to read a value.
  ///
  /// When used inside a snap, there might be app armor limitations
  /// which lead to an error like:
  /// org.freedesktop.DBus.Error.AccessDenied: An AppArmor policy prevents
  /// this sender from sending this message to this recipient;
  /// type="method_call", sender=":1.140" (uid=1000 pid=94358
  /// comm="/snap/biometric-storage-example/x1/biometric_stora"
  /// label="snap.biometric-storage-example.biometric (enforce)")
  /// interface="org.freedesktop.Secret.Service" member="OpenSession"
  /// error name="(unset)" requested_reply="0" destination=":1.30"
  /// (uid=1000 pid=1153 comm="/usr/bin/gnome-keyring-daemon
  /// --daemonize --login " label="unconfined")
  Future<bool> linuxCheckAppArmorError();

  /// Retrieves the given biometric storage file.
  /// Each store is completely separated, and has it's own encryption and
  /// biometric lock.
  /// if [forceInit] is true, will throw an exception if the store was already
  /// created in this runtime.
  Future<BiometricStorageFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  });

  @protected
  Future<String?> read(String name, PromptInfo promptInfo);

  @protected
  Future<bool?> delete(String name, PromptInfo promptInfo);

  @protected
  Future<void> write(String name, String content, PromptInfo promptInfo);
}

class MethodChannelBiometricStorage extends BiometricStorage {
  MethodChannelBiometricStorage() : super.create();

  static const MethodChannel _channel = MethodChannel('biometric_storage');

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async {
    if (kIsWeb) {
      return CanAuthenticateResponse.unsupported;
    }
    if (const {'android', 'ios', 'macos', 'linux'}.contains(operatingSystem)) {
      final response = await _channel.invokeMethod<String>('canAuthenticate', {
        'options': options?.toJson() ?? StorageFileInitOptions().toJson(),
      });
      final ret = _canAuthenticateMapping[response];
      if (ret == null) {
        throw StateError('Invalid response from native platform. {$response}');
      }
      return ret;
    }
    return CanAuthenticateResponse.unsupported;
  }

  /// Returns true when there is an AppArmor error when trying to read a value.
  ///
  /// When used inside a snap, there might be app armor limitations
  /// which lead to an error like:
  /// org.freedesktop.DBus.Error.AccessDenied: An AppArmor policy prevents
  /// this sender from sending this message to this recipient;
  /// type="method_call", sender=":1.140" (uid=1000 pid=94358
  /// comm="/snap/biometric-storage-example/x1/biometric_stora"
  /// label="snap.biometric-storage-example.biometric (enforce)")
  /// interface="org.freedesktop.Secret.Service" member="OpenSession"
  /// error name="(unset)" requested_reply="0" destination=":1.30"
  /// (uid=1000 pid=1153 comm="/usr/bin/gnome-keyring-daemon
  /// --daemonize --login " label="unconfined")
  @override
  Future<bool> linuxCheckAppArmorError() async {
    if (operatingSystem != 'linux') {
      return false;
    }
    final tmpStorage = await getStorage(
      'appArmorCheck',
      options: StorageFileInitOptions(authenticationRequired: false),
    );
    _logger.finer('Checking app armor');
    try {
      await tmpStorage.read();
      _logger.finer('Everything okay.');
      return false;
    } on AuthException catch (e, stackTrace) {
      if (e.code == AuthExceptionCode.linuxAppArmorDenied) {
        return true;
      }
      _logger.warning(
        'Unknown error while checking for app armor.',
        e,
        stackTrace,
      );
      // some other weird error?
      rethrow;
    }
  }

  /// Retrieves the given biometric storage file.
  /// Each store is completely separated, and has it's own encryption and
  /// biometric lock.
  /// if [forceInit] is true, will throw an exception if the store was already
  /// created in this runtime.
  @override
  Future<BiometricStorageFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('init', {
        'name': name,
        'options': options?.toJson() ?? StorageFileInitOptions().toJson(),
        'forceInit': forceInit,
      });
      _logger.finest('getting storage. was created: $result');
      return BiometricStorageFile(this, name, promptInfo);
    } on PlatformException catch (e, stackTrace) {
      // The platforms implemented in Dart — Windows and web — raise this
      // themselves, so without translating here the same failure would reach
      // callers as two different types and need two catch clauses.
      if (e.code == 'AlreadyInitialized') {
        _logger.warning(
          'Storage $name was already initialized.',
          e,
          stackTrace,
        );
        // Not a plain `throw`: that would restart the trace here and lose the
        // frames showing which call re-initialized the store.
        Error.throwWithStackTrace(
          BiometricStorageException(
            e.message ?? e.code,
            code: BiometricStorageExceptionCode.alreadyInitialized,
          ),
          stackTrace,
        );
      }
      _logger.warning(
        'Error while initializing biometric storage.',
        e,
        stackTrace,
      );
      rethrow;
    } catch (e, stackTrace) {
      _logger.warning(
        'Error while initializing biometric storage.',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<String?> read(String name, PromptInfo promptInfo) => _transformErrors(
    _channel.invokeMethod<String>('read', <String, dynamic>{
      'name': name,
      ..._promptInfoForCurrentPlatform(promptInfo),
    }),
  );

  @override
  Future<bool?> delete(String name, PromptInfo promptInfo) => _transformErrors(
    _channel.invokeMethod<bool>('delete', <String, dynamic>{
      'name': name,
      ..._promptInfoForCurrentPlatform(promptInfo),
    }),
  );

  @override
  Future<void> write(String name, String content, PromptInfo promptInfo) =>
      _transformErrors(
        _channel.invokeMethod('write', <String, dynamic>{
          'name': name,
          'content': content,
          ..._promptInfoForCurrentPlatform(promptInfo),
        }),
      );

  Map<String, dynamic> _promptInfoForCurrentPlatform(PromptInfo promptInfo) =>
      switch (operatingSystem) {
        // Don't expose Android configurations to other platforms.
        'android' => <String, dynamic>{
          'androidPromptInfo': promptInfo.androidPromptInfo._toJson(),
        },
        'ios' => <String, dynamic>{
          'iosPromptInfo': promptInfo.iosPromptInfo._toJson(),
        },
        // This is no typo, we use the same implementation on iOS and MacOS,
        // so we use the same parameter.
        'macos' => <String, dynamic>{
          'iosPromptInfo': promptInfo.macOsPromptInfo._toJson(),
        },
        'linux' => <String, dynamic>{},
        // Windows has no method channel implementation
        // Web has a Noop implementation.
        final os => throw StateError('Unsupported Platform $os'),
      };

  Future<T> _transformErrors<T>(Future<T> future) =>
      future.catchError((Object error, StackTrace stackTrace) {
        if (error is PlatformException) {
          _logger.finest(
            'Error during plugin operation (details: ${error.details})',
            error,
            stackTrace,
          );
          if (error.code.startsWith('AuthError:')) {
            return Future<T>.error(
              AuthException(
                _authErrorCodeMapping[error.code] ?? AuthExceptionCode.unknown,
                error.message ?? 'Unknown error',
              ),
              stackTrace,
            );
          }
          if (error.details is Map) {
            final message = error.details['message'] as String;
            if (message.contains('org.freedesktop.DBus.Error.AccessDenied') ||
                message.contains('AppArmor')) {
              _logger.fine('Got app armor error.');
              return Future<T>.error(
                AuthException(
                  AuthExceptionCode.linuxAppArmorDenied,
                  error.message!,
                ),
                stackTrace,
              );
            }
          }
        }
        return Future<T>.error(error, stackTrace);
      });
}

class BiometricStorageFile {
  BiometricStorageFile(this._plugin, this.name, this.defaultPromptInfo);

  final BiometricStorage _plugin;
  final String name;
  final PromptInfo defaultPromptInfo;

  /// read from the secure file and returns the content.
  /// Will return `null` if file does not exist.
  Future<String?> read({PromptInfo? promptInfo}) =>
      _plugin.read(name, promptInfo ?? defaultPromptInfo);

  /// Write content of this file. Previous value will be overwritten.
  Future<void> write(String content, {PromptInfo? promptInfo}) =>
      _plugin.write(name, content, promptInfo ?? defaultPromptInfo);

  /// Delete the content of this storage.
  Future<void> delete({PromptInfo? promptInfo}) =>
      _plugin.delete(name, promptInfo ?? defaultPromptInfo);
}
