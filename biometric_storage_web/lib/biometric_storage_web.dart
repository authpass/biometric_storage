import 'package:biometric_storage_platform_interface/biometric_storage_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

class BiometricStorageWeb extends BiometricStoragePlatform {
  BiometricStorageWeb() : _storage = const FlutterSecureStorage();

  static const namePrefix = 'design.codeux.authpass.';

  final FlutterSecureStorage _storage;

  static void registerWith(Registrar registrar) {
    BiometricStoragePlatform.instance = BiometricStorageWeb();
  }

  String _key(String name) => '$namePrefix$name';

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async =>
      CanAuthenticateResponse.errorHwUnavailable;

  @override
  Future<bool?> init(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
  }) async =>
      true;

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<String?> read(
    String name,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) =>
      _storage.read(key: _key(name));

  @override
  Future<bool?> delete(
    String name,
    PromptInfo promptInfo,
  ) async {
    final key = _key(name);
    final oldValue = await _storage.read(key: key);
    await _storage.delete(key: key);
    return oldValue != null;
  }

  @override
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) =>
      _storage.write(key: _key(name), value: content);

  @override
  Future<void> dispose(
    String name,
    PromptInfo promptInfo,
  ) async {}
}
