import 'package:biometric_storage_platform_interface/biometric_storage_platform_interface.dart';
import 'package:flutter/foundation.dart';

class BiometricStorageDarwin extends MethodChannelBiometricStoragePlatform {
  static void registerWith() {
    BiometricStoragePlatform.instance = BiometricStorageDarwin();
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
  Map<String, dynamic> buildPromptInfoArguments(PromptInfo promptInfo) {
    final iosPromptInfo = switch (defaultTargetPlatform) {
      TargetPlatform.macOS => promptInfo.macOsPromptInfo,
      _ => promptInfo.iosPromptInfo,
    };
    return <String, dynamic>{'iosPromptInfo': iosPromptInfo.toJson()};
  }

  @override
  Future<bool> linuxCheckAppArmorError() async => false;
}
