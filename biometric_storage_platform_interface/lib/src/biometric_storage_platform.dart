import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'types.dart';

abstract class BiometricStoragePlatform extends PlatformInterface {
  BiometricStoragePlatform() : super(token: _token);

  static final Object _token = Object();

  static BiometricStoragePlatform _instance =
      UnsupportedBiometricStoragePlatform();

  static BiometricStoragePlatform get instance => _instance;

  static set instance(BiometricStoragePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  });

  Future<bool> linuxCheckAppArmorError();

  Future<bool?> init(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
  });

  Future<String?> read(
    String name,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  });

  Future<bool?> delete(
    String name,
    PromptInfo promptInfo,
  );

  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  });

  Future<void> dispose(
    String name,
    PromptInfo promptInfo,
  );
}

class UnsupportedBiometricStoragePlatform extends BiometricStoragePlatform {
  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async =>
      CanAuthenticateResponse.unsupported;

  @override
  Future<bool?> init(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
  }) async =>
      false;

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<String?> read(
    String name,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) {
    throw UnsupportedError(
        'No biometric_storage platform implementation registered.');
  }

  @override
  Future<bool?> delete(
    String name,
    PromptInfo promptInfo,
  ) {
    throw UnsupportedError(
        'No biometric_storage platform implementation registered.');
  }

  @override
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) {
    throw UnsupportedError(
        'No biometric_storage platform implementation registered.');
  }

  @override
  Future<void> dispose(
    String name,
    PromptInfo promptInfo,
  ) async {}
}
