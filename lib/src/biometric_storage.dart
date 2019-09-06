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

const canAuthenticateMapping = {
  'Success': CanAuthenticateResponse.success,
  'ErrorHwUnavailable': CanAuthenticateResponse.errorHwUnavailable,
  'ErrorNoBiometricEnrolled': CanAuthenticateResponse.errorNoBiometricEnrolled,
  'ErrorNoHardware': CanAuthenticateResponse.errorNoHardware,
  'ErrorUnknown': CanAuthenticateResponse.unsupported,
};

class StorageFileInitOptions {
  StorageFileInitOptions({
    this.authenticationValidityDurationSeconds,
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

class BiometricStorage {
  factory BiometricStorage() => _instance;

  BiometricStorage._();

  static final _instance = BiometricStorage._();

  static const MethodChannel _channel = MethodChannel('biometric_storage');

  Future<CanAuthenticateResponse> canAuthenticate() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      return canAuthenticateMapping[
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
  }) async {
    assert(name != null);
    try {
      final result = await _channel.invokeMethod<bool>(
        'init',
        {
          'name': name,
          'options': options?.toJson(),
          'forceInit': forceInit,
        },
      );
      _logger.finest('getting storage. was created: $result');
      return BiometricStorageFile(this, name);
    } catch (e, stackTrace) {
      _logger.warning(
          'Error while initializing biometric storage.', e, stackTrace);
      rethrow;
    }
  }

  Future<String> _read(String name) =>
      _warnError(_channel.invokeMethod<String>('read', {'name': name}));

  Future<bool> _delete(String name) =>
      _warnError(_channel.invokeMethod<bool>('delete', {'name': name}));

  Future<void> _write(String name, String content) =>
      _warnError(_channel.invokeMethod('write', {
        'name': name,
        'content': content,
      }));

  Future<T> _warnError<T>(Future<T> future) =>
      future.catchError((dynamic error, StackTrace stackTrace) {
        _logger.warning('Error during plugin operation', error, stackTrace);
        return Future<T>.error(error, stackTrace);
      });
}

class BiometricStorageFile {
  BiometricStorageFile(this._plugin, this.name);

  final BiometricStorage _plugin;
  final String name;

  /// ead from the secure file and returns the content.
  /// Will return `null` if file does not exist.
  Future<String> read() => _plugin._read(name);

  /// Write content of this file. Previous value will be overwritten.
  Future<void> write(String content) => _plugin._write(name, content);

  /// Delete the content of this storage.
  Future<void> delete() => _plugin._delete(name);
}
