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

const androidCanAuthenticateMapping = {
  'Success': CanAuthenticateResponse.success,
  'ErrorHwUnavailable': CanAuthenticateResponse.errorHwUnavailable,
  'ErrorNoBiometricEnrolled': CanAuthenticateResponse.errorNoBiometricEnrolled,
  'ErrorNoHardware': CanAuthenticateResponse.errorNoHardware,
};

class AndroidInitOptions {
  AndroidInitOptions({this.authenticationValidityDurationSeconds});

  final int authenticationValidityDurationSeconds;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'authenticationValidityDurationSeconds':
            authenticationValidityDurationSeconds,
      };
}

class BiometricStorage {
  factory BiometricStorage() => _instance;
  BiometricStorage._();
  static final _instance = BiometricStorage._();

  static const MethodChannel _channel = MethodChannel('biometric_storage');

  Future<CanAuthenticateResponse> canAuthenticate() async {
    if (Platform.isAndroid) {
      return await _androidCanAuthenticate();
    }
    return CanAuthenticateResponse.unsupported;
  }

  Future<CanAuthenticateResponse> _androidCanAuthenticate() async {
    return androidCanAuthenticateMapping[
        await _channel.invokeMethod<String>('canAuthenticate')];
  }

  Future<BiometricStorageFile> getStorage(String name,
      [AndroidInitOptions options]) async {
    assert(name != null);
    try {
      final result = await _channel.invokeMethod<String>(
          'init', {'name': name, 'options': options?.toJson()});
      assert(result == name);
      return BiometricStorageFile(this, name);
    } catch (e, stackTrace) {
      _logger.warning(
          'Error while initializing biometric storage.', e, stackTrace);
      rethrow;
    }
  }

  Future<String> _read(String name) async {
    return await _channel.invokeMethod<String>('read', {'name': name});
  }

  Future<void> _write(String name, String content) =>
      _channel.invokeMethod('write', {
        'name': name,
        'content': content,
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
}
