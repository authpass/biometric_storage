import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final _logger = Logger('biometric_storage');

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

class PromptMessages {
  PromptMessages({
    this.title,
    this.subtitle,
    this.description,
    this.negativeButton,
  });

  final String title;
  final String subtitle;
  final String description;
  final String negativeButton;

  Map<String, String> _toJson() {
    final json = Map<String, String>();
    if (title != null) {
      json['title'] = title;
    }

    if (subtitle != null) {
      json['subtitle'] = subtitle;
    }

    if (description != null) {
      json['description'] = description;
    }

    if (negativeButton != null) {
      json['negativeButton'] = negativeButton;
    }

    return json;
  }
}

class BiometricStorage {
  factory BiometricStorage() => _instance;

  BiometricStorage._();

  static final _instance = BiometricStorage._();

  static const MethodChannel _channel = MethodChannel('biometric_storage');

  Future<CanAuthenticateResponse> canAuthenticate() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      return _canAuthenticateMapping[
          await _channel.invokeMethod<String>('canAuthenticate')];
    }
    return CanAuthenticateResponse.unsupported;
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
    PromptMessages promptMessages,
    bool confirmationRequired,
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
        promptMessages: promptMessages,
        confirmationRequired: confirmationRequired,
      );
    } catch (e, stackTrace) {
      _logger.warning(
          'Error while initializing biometric storage.', e, stackTrace);
      rethrow;
    }
  }

  Future<String> _read(String name,
          {PromptMessages promptMessages, bool confirmationRequired}) =>
      _transformErrors(_channel.invokeMethod<String>('read', {
        'name': name,
        'promptMessages': promptMessages?._toJson(),
        'confirmationRequired': confirmationRequired
      }));

  Future<bool> _delete(String name,
          {PromptMessages promptMessages, bool confirmationRequired}) =>
      _transformErrors(_channel.invokeMethod<bool>('delete', {
        'name': name,
        'promptMessages': promptMessages?._toJson(),
        'confirmationRequired': confirmationRequired
      }));

  Future<void> _write(String name, String content,
          {PromptMessages promptMessages, bool confirmationRequired}) =>
      _transformErrors(_channel.invokeMethod('write', {
        'name': name,
        'content': content,
        'promptMessages': promptMessages?._toJson(),
        'confirmationRequired': confirmationRequired
      }));

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
  BiometricStorageFile(
    this._plugin,
    this.name, {
    this.promptMessages,
    this.confirmationRequired,
  });

  final BiometricStorage _plugin;
  final String name;
  final PromptMessages promptMessages;
  final bool confirmationRequired;

  /// read from the secure file and returns the content.
  /// Will return `null` if file does not exist.
  Future<String> read() => _plugin._read(
        name,
        promptMessages: promptMessages,
        confirmationRequired: confirmationRequired,
      );

  /// Write content of this file. Previous value will be overwritten.
  Future<void> write(String content) => _plugin._write(
        name,
        content,
        promptMessages: promptMessages,
        confirmationRequired: confirmationRequired,
      );

  /// Delete the content of this storage.
  Future<void> delete() => _plugin._delete(
        name,
        promptMessages: promptMessages,
        confirmationRequired: confirmationRequired,
      );
}
