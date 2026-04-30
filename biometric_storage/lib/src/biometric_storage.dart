import 'package:biometric_storage_platform_interface/biometric_storage_platform_interface.dart';

class BiometricStorage {
  factory BiometricStorage() => _instance;

  BiometricStorage._();

  static final BiometricStorage _instance = BiometricStorage._();

  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) =>
      BiometricStoragePlatform.instance.canAuthenticate(options: options);

  Future<bool> linuxCheckAppArmorError() =>
      BiometricStoragePlatform.instance.linuxCheckAppArmorError();

  Future<BiometricStorageFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  }) async {
    await BiometricStoragePlatform.instance.init(
      name,
      options: options,
      forceInit: forceInit,
    );
    return BiometricStorageFile(name, promptInfo);
  }
}

class BiometricStorageFile {
  BiometricStorageFile(this.name, this.defaultPromptInfo);

  final String name;
  final PromptInfo defaultPromptInfo;

  Future<String?> read({
    PromptInfo? promptInfo,
    bool forceBiometricAuthentication = false,
  }) =>
      BiometricStoragePlatform.instance.read(
        name,
        promptInfo ?? defaultPromptInfo,
        forceBiometricAuthentication: forceBiometricAuthentication,
      );

  Future<void> write(
    String content, {
    PromptInfo? promptInfo,
    bool forceBiometricAuthentication = false,
  }) =>
      BiometricStoragePlatform.instance.write(
        name,
        content,
        promptInfo ?? defaultPromptInfo,
        forceBiometricAuthentication: forceBiometricAuthentication,
      );

  Future<void> delete({PromptInfo? promptInfo}) async {
    await BiometricStoragePlatform.instance.delete(
      name,
      promptInfo ?? defaultPromptInfo,
    );
  }

  Future<void> deleteAndDispose({PromptInfo? promptInfo}) async {
    final resolvedPromptInfo = promptInfo ?? defaultPromptInfo;
    await delete(promptInfo: resolvedPromptInfo);
    await BiometricStoragePlatform.instance.dispose(name, resolvedPromptInfo);
  }
}
