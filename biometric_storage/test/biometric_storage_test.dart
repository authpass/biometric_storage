// ignore_for_file: deprecated_member_use

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RecordingBiometricStoragePlatform platform;

  setUp(() {
    platform = RecordingBiometricStoragePlatform();
    BiometricStoragePlatform.instance = platform;
  });

  group('StorageFileInitOptions', () {
    test('serializes configured durations and flags', () {
      final options = StorageFileInitOptions(
        androidAuthenticationValidityDuration: const Duration(seconds: 11),
        darwinTouchIDAuthenticationAllowableReuseDuration:
            const Duration(seconds: 22),
        darwinTouchIDAuthenticationForceReuseContextDuration:
            const Duration(seconds: 33),
        authenticationRequired: false,
        androidUseStrongBox: false,
        androidBiometricOnly: false,
        darwinBiometricOnly: false,
      );

      expect(options.toJson(), <String, dynamic>{
        'androidAuthenticationValidityDurationSeconds': 11,
        'darwinTouchIDAuthenticationAllowableReuseDurationSeconds': 22,
        'darwinTouchIDAuthenticationForceReuseContextDurationSeconds': 33,
        'authenticationRequired': false,
        'androidUseStrongBox': false,
        'androidBiometricOnly': false,
        'darwinBiometricOnly': false,
      });
    });

    test('supports deprecated authentication validity seconds fallback', () {
      final options = StorageFileInitOptions(
        authenticationValidityDurationSeconds: 7,
      );

      expect(options.toJson(), <String, dynamic>{
        'androidAuthenticationValidityDurationSeconds': 7,
        'darwinTouchIDAuthenticationAllowableReuseDurationSeconds': 7,
        'darwinTouchIDAuthenticationForceReuseContextDurationSeconds': null,
        'authenticationRequired': true,
        'androidUseStrongBox': true,
        'androidBiometricOnly': true,
        'darwinBiometricOnly': true,
      });
    });
  });

  test('delegates canAuthenticate and app armor checks', () async {
    platform.canAuthenticateResponse = CanAuthenticateResponse.success;
    platform.linuxCheckAppArmorErrorResponse = true;

    expect(
      await BiometricStorage().canAuthenticate(),
      CanAuthenticateResponse.success,
    );
    expect(await BiometricStorage().linuxCheckAppArmorError(), isTrue);
  });

  test('initializes storage and forwards read write delete calls', () async {
    const promptInfo = PromptInfo(
      macOsPromptInfo: IosPromptInfo(
        saveTitle: 'Save title',
        accessTitle: 'Access title',
      ),
    );
    final options = StorageFileInitOptions(
      authenticationRequired: false,
      androidBiometricOnly: false,
      darwinBiometricOnly: false,
    );
    platform.readResponse = 'stored value';

    final storage = await BiometricStorage().getStorage(
      'secret-name',
      options: options,
      forceInit: true,
      promptInfo: promptInfo,
    );

    expect(storage.name, 'secret-name');
    expect(await storage.read(), 'stored value');
    await storage.write('next value');
    await storage.delete();

    expect(platform.initCalls.single.name, 'secret-name');
    expect(platform.initCalls.single.options?.toJson(), options.toJson());
    expect(platform.initCalls.single.forceInit, isTrue);

    expect(platform.readCalls.single.name, 'secret-name');
    expect(platform.readCalls.single.forceBiometricAuthentication, isFalse);
    expect(platform.readCalls.single.promptInfo.macOsPromptInfo.saveTitle,
        'Save title');

    expect(platform.writeCalls.single.name, 'secret-name');
    expect(platform.writeCalls.single.content, 'next value');
    expect(platform.writeCalls.single.forceBiometricAuthentication, isFalse);

    expect(platform.deleteCalls.single.name, 'secret-name');
  });

  test('allows overriding prompt info per operation', () async {
    const defaultPromptInfo = PromptInfo(
      macOsPromptInfo: IosPromptInfo(
        saveTitle: 'Default save',
        accessTitle: 'Default access',
      ),
    );
    const overridePromptInfo = PromptInfo(
      macOsPromptInfo: IosPromptInfo(
        saveTitle: 'Override save',
        accessTitle: 'Override access',
      ),
    );

    final storage = await BiometricStorage().getStorage(
      'overridden-secret',
      promptInfo: defaultPromptInfo,
    );

    await storage.read(promptInfo: overridePromptInfo);
    await storage.write('content', promptInfo: overridePromptInfo);
    await storage.delete(promptInfo: overridePromptInfo);

    expect(platform.readCalls.single.promptInfo.macOsPromptInfo.saveTitle,
        'Override save');
    expect(platform.writeCalls.single.promptInfo.macOsPromptInfo.saveTitle,
        'Override save');
    expect(platform.deleteCalls.single.promptInfo.macOsPromptInfo.saveTitle,
        'Override save');
  });

  test('deleteAndDispose forwards delete then dispose', () async {
    final storage = await BiometricStorage().getStorage('dispose-secret');

    await storage.deleteAndDispose();

    expect(platform.deleteCalls.single.name, 'dispose-secret');
    expect(platform.disposeCalls.single.name, 'dispose-secret');
  });
}

class RecordingBiometricStoragePlatform extends BiometricStoragePlatform {
  CanAuthenticateResponse canAuthenticateResponse =
      CanAuthenticateResponse.unsupported;
  bool linuxCheckAppArmorErrorResponse = false;
  String? readResponse;

  final List<InitCall> initCalls = <InitCall>[];
  final List<ReadCall> readCalls = <ReadCall>[];
  final List<WriteCall> writeCalls = <WriteCall>[];
  final List<DeleteCall> deleteCalls = <DeleteCall>[];
  final List<DisposeCall> disposeCalls = <DisposeCall>[];

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async =>
      canAuthenticateResponse;

  @override
  Future<bool?> init(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
  }) async {
    initCalls.add(InitCall(name, options, forceInit));
    return true;
  }

  @override
  Future<bool> linuxCheckAppArmorError() async =>
      linuxCheckAppArmorErrorResponse;

  @override
  Future<String?> read(
    String name,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) async {
    readCalls.add(ReadCall(name, promptInfo, forceBiometricAuthentication));
    return readResponse;
  }

  @override
  Future<bool?> delete(
    String name,
    PromptInfo promptInfo,
  ) async {
    deleteCalls.add(DeleteCall(name, promptInfo));
    return true;
  }

  @override
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) async {
    writeCalls.add(
      WriteCall(name, content, promptInfo, forceBiometricAuthentication),
    );
  }

  @override
  Future<void> dispose(
    String name,
    PromptInfo promptInfo,
  ) async {
    disposeCalls.add(DisposeCall(name, promptInfo));
  }
}

class InitCall {
  InitCall(this.name, this.options, this.forceInit);
  final String name;
  final StorageFileInitOptions? options;
  final bool forceInit;
}

class ReadCall {
  ReadCall(this.name, this.promptInfo, this.forceBiometricAuthentication);
  final String name;
  final PromptInfo promptInfo;
  final bool forceBiometricAuthentication;
}

class WriteCall {
  WriteCall(
    this.name,
    this.content,
    this.promptInfo,
    this.forceBiometricAuthentication,
  );
  final String name;
  final String content;
  final PromptInfo promptInfo;
  final bool forceBiometricAuthentication;
}

class DeleteCall {
  DeleteCall(this.name, this.promptInfo);
  final String name;
  final PromptInfo promptInfo;
}

class DisposeCall {
  DisposeCall(this.name, this.promptInfo);
  final String name;
  final PromptInfo promptInfo;
}
