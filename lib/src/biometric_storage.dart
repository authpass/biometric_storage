import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

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

  /// Plugin does not support platform (ie right now everything but android)
  unsupported,
}

const _canAuthenticateMapping = {
  'Success': CanAuthenticateResponse.success,
  'ErrorHwUnavailable': CanAuthenticateResponse.errorHwUnavailable,
  'ErrorNoBiometricEnrolled': CanAuthenticateResponse.errorNoBiometricEnrolled,
  'ErrorNoHardware': CanAuthenticateResponse.errorNoHardware,
  'ErrorUnknown': CanAuthenticateResponse.unsupported,
};

enum AuthExceptionCode {
  userCanceled,
  unknown,
  timeout,
}

const _authErrorCodeMapping = {
  'AuthError:UserCanceled': AuthExceptionCode.userCanceled,
  'AuthError:Timeout': AuthExceptionCode.timeout,
};

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
    this.authenticationValidityDurationSeconds = 10,
    this.authenticationRequired = true,
  });

  final int authenticationValidityDurationSeconds;

  /// Whether an authentication is required. if this is
  /// false NO BIOMETRIC CHECK WILL BE PERFORMED! and the value
  /// will simply be save encrypted. (default: true)
  final bool authenticationRequired;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'authenticationValidityDurationSeconds':
            authenticationValidityDurationSeconds,
        'authenticationRequired': authenticationRequired,
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
  })  : assert(title != null),
        assert(negativeButton != null),
        assert(confirmationRequired != null);

  final String title;
  final String subtitle;
  final String description;
  final String negativeButton;
  final bool confirmationRequired;

  static const _defaultValues = AndroidPromptInfo();

  Map<String, dynamic> _toJson() => <String, dynamic>{
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'negativeButton': negativeButton,
        'confirmationRequired': confirmationRequired,
      };
}

/// Main plugin class to interact with. Is always a singleton right now,
/// factory constructor will always return the same instance.
///
/// * call [canAuthenticate] to check support on the platform/device.
/// * call [getStorage] to initialize a storage.
class BiometricStorage {
  /// Returns singleton instance.
  factory BiometricStorage() => _instance;

  BiometricStorage._();

  static final _instance = BiometricStorage._();

  static const MethodChannel _channel = MethodChannel('biometric_storage');

  /// Returns whether this device supports biometric/secure storage or
  /// the reason [CanAuthenticateResponse] why it is not supported.
  Future<CanAuthenticateResponse> canAuthenticate() async {
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux) {
      return _canAuthenticateMapping[
          await _channel.invokeMethod<String>('canAuthenticate')];
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
  Future<bool> linuxCheckAppArmorError() async {
    if (!Platform.isLinux) {
      return false;
    }
    final tmpStorage = await getStorage('appArmorCheck',
        options: StorageFileInitOptions(authenticationRequired: false));
    _logger.finer('Checking app armor');
    try {
      await tmpStorage.read();
      _logger.finer('Everything okay.');
      return false;
    } on PlatformException catch (e, stackTrace) {
      if (e.details is Map) {
        final message = e.details['message'] as String;
        if (message.contains('org.freedesktop.DBus.Error.AccessDenied')) {
          _logger.fine('Got app armor error.');
          return true;
        }
      }
      _logger.warning(
          'Unknown error while checking for app armor.', e, stackTrace);
      // some other weird error?
      rethrow;
    }
  }

  /// Retrieves the given biometric storage file.
  /// Each store is completely separated, and has it's own encryption and
  /// biometric lock.
  /// if [forceInit] is true, will throw an exception if the store was already
  /// created in this runtime.
  Future<BiometricStorageFile> getStorage(
    String name, {
    StorageFileInitOptions options,
    bool forceInit = false,
    AndroidPromptInfo androidPromptInfo = AndroidPromptInfo._defaultValues,
  }) async {
    assert(name != null);
    try {
      final result = await _channel.invokeMethod<bool>(
        'init',
        {
          'name': name,
          'options': options?.toJson() ?? StorageFileInitOptions().toJson(),
          'forceInit': forceInit,
        },
      );
      _logger.finest('getting storage. was created: $result');
      return BiometricStorageFile(
        this,
        name,
        androidPromptInfo,
      );
    } catch (e, stackTrace) {
      _logger.warning(
          'Error while initializing biometric storage.', e, stackTrace);
      rethrow;
    }
  }

  Future<String> _read(
    String name,
    AndroidPromptInfo androidPromptInfo,
  ) =>
      _transformErrors(_channel.invokeMethod<String>('read', <String, dynamic>{
        'name': name,
        ..._androidPromptInfoOnlyOnAndroid(androidPromptInfo),
      }));

  Future<bool> _delete(
    String name,
    AndroidPromptInfo androidPromptInfo,
  ) =>
      _transformErrors(_channel.invokeMethod<bool>('delete', <String, dynamic>{
        'name': name,
        ..._androidPromptInfoOnlyOnAndroid(androidPromptInfo),
      }));

  Future<void> _write(
    String name,
    String content,
    AndroidPromptInfo androidPromptInfo,
  ) =>
      _transformErrors(_channel.invokeMethod('write', <String, dynamic>{
        'name': name,
        'content': content,
        ..._androidPromptInfoOnlyOnAndroid(androidPromptInfo),
      }));

  Map<String, dynamic> _androidPromptInfoOnlyOnAndroid(
      AndroidPromptInfo promptInfo) {
    // Don't expose Android configurations to other platforms
    return Platform.isAndroid
        ? <String, dynamic>{'androidPromptInfo': promptInfo._toJson()}
        : <String, dynamic>{};
  }

  Future<T> _transformErrors<T>(Future<T> future) =>
      future.catchError((dynamic error, StackTrace stackTrace) {
        _logger.warning('Error during plugin operation', error, stackTrace);
        if (error is PlatformException) {
          if (error.code.startsWith('AuthError:')) {
            return Future<T>.error(
              AuthException(
                _authErrorCodeMapping[error.code] ?? AuthExceptionCode.unknown,
                error.message,
              ),
              stackTrace,
            );
          }
        }
        return Future<T>.error(error, stackTrace);
      });
}

class BiometricStorageFile {
  BiometricStorageFile(this._plugin, this.name, this.androidPromptInfo);

  final BiometricStorage _plugin;
  final String name;
  final AndroidPromptInfo androidPromptInfo;

  /// read from the secure file and returns the content.
  /// Will return `null` if file does not exist.
  Future<String> read() => _plugin._read(name, androidPromptInfo);

  /// Write content of this file. Previous value will be overwritten.
  Future<void> write(String content) =>
      _plugin._write(name, content, androidPromptInfo);

  /// Delete the content of this storage.
  Future<void> delete() => _plugin._delete(name, androidPromptInfo);
}
