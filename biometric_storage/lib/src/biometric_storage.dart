import 'package:biometric_storage_platform_interface/biometric_storage_platform_interface.dart';

class BiometricStorage {
  factory BiometricStorage() => _instance;

  BiometricStorage._();

  static final BiometricStorage _instance = BiometricStorage._();

  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) => BiometricStoragePlatform.instance.canAuthenticate(options: options);

  Future<bool> isSupported({StorageFileInitOptions? options}) =>
      BiometricStoragePlatform.instance.isSupported(options: options);

  Future<bool> canAuthenticateWithBiometrics({
    StorageFileInitOptions? options,
  }) async =>
      (await canAuthenticate(options: options)).canAuthenticateWithBiometrics;

  Future<PasskeyAvailability> getPasskeyAvailability() =>
      BiometricStoragePlatform.instance.getPasskeyAvailability();

  Future<bool> isPasskeySupported() =>
      BiometricStoragePlatform.instance.isPasskeySupported();

  Future<bool> isPasskeyAvailable() =>
      BiometricStoragePlatform.instance.isPasskeyAvailable();

  Future<BiometricStorageCapabilities> getCapabilities({
    StorageFileInitOptions? options,
  }) async {
    final results = await Future.wait<Object>(<Future<Object>>[
      canAuthenticate(options: options),
      getPasskeyAvailability(),
    ]);
    return BiometricStorageCapabilities(
      biometricStorage: results[0] as CanAuthenticateResponse,
      passkeys: results[1] as PasskeyAvailability,
    );
  }

  Future<SecureAccessCapabilitySet> getSupportedCapabilities({
    StorageFileInitOptions? options,
  }) async => (await getCapabilities(options: options)).supportedCapabilities;

  Future<SecureAccessCapabilitySet> getAvailableCapabilities({
    StorageFileInitOptions? options,
  }) async => (await getCapabilities(options: options)).availableCapabilities;

  Future<bool> isCapabilitySupported(
    SecureAccessCapability capability, {
    StorageFileInitOptions? options,
  }) async => (await getCapabilities(
    options: options,
  )).isCapabilitySupported(capability);

  Future<bool> isCapabilityAvailable(
    SecureAccessCapability capability, {
    StorageFileInitOptions? options,
  }) async => (await getCapabilities(
    options: options,
  )).isCapabilityAvailable(capability);

  Future<PublicKeyCredentialAttestationJson> registerPasskey(
    PublicKeyCredentialCreationOptionsJson options,
  ) => BiometricStoragePlatform.instance.registerPasskey(options);

  Future<PublicKeyCredentialAssertionJson> authenticateWithPasskey(
    PublicKeyCredentialRequestOptionsJson options,
  ) => BiometricStoragePlatform.instance.authenticateWithPasskey(options);

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

  Future<BiometricStorageFile?> getStorageIfSupported(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  }) async {
    if (!await isSupported(options: options)) {
      return null;
    }

    return getStorage(
      name,
      options: options,
      forceInit: forceInit,
      promptInfo: promptInfo,
    );
  }
}

class BiometricStorageFile {
  BiometricStorageFile(this.name, this.defaultPromptInfo);

  final String name;
  final PromptInfo defaultPromptInfo;

  Future<String?> read({
    PromptInfo? promptInfo,
    bool forceBiometricAuthentication = false,
  }) => BiometricStoragePlatform.instance.read(
    name,
    promptInfo ?? defaultPromptInfo,
    forceBiometricAuthentication: forceBiometricAuthentication,
  );

  Future<void> write(
    String content, {
    PromptInfo? promptInfo,
    bool forceBiometricAuthentication = false,
  }) => BiometricStoragePlatform.instance.write(
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

  Future<bool> exists({PromptInfo? promptInfo}) => BiometricStoragePlatform
      .instance
      .exists(name, promptInfo ?? defaultPromptInfo);

  Future<void> deleteAndDispose({PromptInfo? promptInfo}) async {
    final resolvedPromptInfo = promptInfo ?? defaultPromptInfo;
    await delete(promptInfo: resolvedPromptInfo);
    await BiometricStoragePlatform.instance.dispose(name, resolvedPromptInfo);
  }
}
