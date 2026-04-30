import 'package:biometric_storage_platform_interface/biometric_storage_platform_interface.dart';

class BiometricStorageAndroid extends MethodChannelBiometricStoragePlatform {
  static void registerWith() {
    BiometricStoragePlatform.instance = BiometricStorageAndroid();
  }

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async {
    final response = await MethodChannelBiometricStoragePlatform.channel
        .invokeMethod<String>(
      'canAuthenticate',
      <String, dynamic>{
        'options': options?.toJson() ?? StorageFileInitOptions().toJson(),
      },
    );
    return mapCanAuthenticateResponse(response);
  }

  @override
  Map<String, dynamic> buildPromptInfoArguments(PromptInfo promptInfo) =>
      <String, dynamic>{
        'androidPromptInfo': promptInfo.androidPromptInfo.toJson(),
      };

  @override
  Future<bool> linuxCheckAppArmorError() async => false;
}
