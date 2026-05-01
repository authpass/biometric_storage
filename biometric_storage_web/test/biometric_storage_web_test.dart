import 'dart:typed_data';

import 'package:biometric_storage_platform_interface/biometric_storage_platform_interface.dart';
import 'package:biometric_storage_web/biometric_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const promptInfo = PromptInfo.defaultValues;
  test('support checks report unsupported when PRF is missing', () async {
    final storage = BiometricStorageWeb(
      runtime: FakeWebAuthnRuntime(
        support: const WebAuthnSupport(
          isSecureContext: true,
          hasCredentialsApi: true,
          hasPublicKeyCredential: true,
          supportsPrf: false,
          hasPlatformAuthenticator: true,
        ),
      ),
    );

    expect(await storage.isSupported(), isFalse);
    expect(
        await storage.canAuthenticate(), CanAuthenticateResponse.unsupported);
  });

  test('support checks report missing platform authenticator separately',
      () async {
    final storage = BiometricStorageWeb(
      runtime: FakeWebAuthnRuntime(
        support: const WebAuthnSupport(
          isSecureContext: true,
          hasCredentialsApi: true,
          hasPublicKeyCredential: true,
          supportsPrf: true,
          hasPlatformAuthenticator: false,
        ),
      ),
    );

    expect(await storage.isSupported(), isTrue);
    expect(await storage.canAuthenticate(),
        CanAuthenticateResponse.errorNoHardware);
  });

  test('read returns null before biometric enrollment is written', () async {
    final storage = BiometricStorageWeb(runtime: FakeWebAuthnRuntime());

    expect(await storage.init('startup-secret'), isTrue);
    expect(await storage.read('startup-secret', promptInfo), isNull);
    expect(await storage.exists('startup-secret', promptInfo), isFalse);
  });

  test('write read exists and delete round-trip with PRF-backed runtime',
      () async {
    final storage = BiometricStorageWeb(runtime: FakeWebAuthnRuntime());
    const name = 'folder/🔐/demo';

    expect(await storage.init(name), isTrue);
    await storage.write(name, 'hello world', promptInfo);
    expect(await storage.exists(name, promptInfo), isTrue);
    expect(await storage.read(name, promptInfo), 'hello world');
    expect(await storage.delete(name, promptInfo), isTrue);
    expect(await storage.exists(name, promptInfo), isFalse);
    expect(await storage.read(name, promptInfo), isNull);
  });

  test('write throws unsupported when browser support probe fails', () async {
    final storage = BiometricStorageWeb(
      runtime: FakeWebAuthnRuntime(
        support: const WebAuthnSupport(
          isSecureContext: true,
          hasCredentialsApi: true,
          hasPublicKeyCredential: true,
          supportsPrf: false,
          hasPlatformAuthenticator: true,
        ),
      ),
    );

    await expectLater(
      storage.write('web-only', 'hello', promptInfo),
      throwsA(isA<UnsupportedError>()),
    );
  });
}

class FakeWebAuthnRuntime implements WebAuthnRuntime {
  FakeWebAuthnRuntime({
    this.support = const WebAuthnSupport(
      isSecureContext: true,
      hasCredentialsApi: true,
      hasPublicKeyCredential: true,
      supportsPrf: true,
      hasPlatformAuthenticator: true,
    ),
  });

  final WebAuthnSupport support;
  final Map<String, String> _records = <String, String>{};
  final Map<String, Uint8List> _credentialSecrets = <String, Uint8List>{};
  int _counter = 0;

  @override
  Future<WebAuthnSupport> probeSupport() async => support;

  @override
  String? readRecord(String key) => _records[key];

  @override
  void writeRecord(String key, String value) {
    _records[key] = value;
  }

  @override
  void deleteRecord(String key) {
    _records.remove(key);
  }

  @override
  Future<Uint8List> registerCredential({
    required String storageName,
    required Uint8List challenge,
    required Uint8List userId,
    required Uint8List prfSalt,
  }) async {
    final credentialId = Uint8List.fromList(List<int>.generate(
      16,
      (index) => (_counter + index + 1) & 0xff,
    ));
    _counter += 17;
    _credentialSecrets[_encode(credentialId)] =
        _deriveBytes(credentialId, prfSalt);
    return credentialId;
  }

  @override
  Future<Uint8List> derivePrfSecret({
    required Uint8List credentialId,
    required Uint8List prfSalt,
    required bool forceBiometricAuthentication,
  }) async {
    if (!support.isStorageSupported) {
      throw UnsupportedError('PRF unavailable');
    }
    return _credentialSecrets[_encode(credentialId)] ??
        _deriveBytes(credentialId, prfSalt);
  }

  String _encode(Uint8List value) => value.join(',');

  Uint8List _deriveBytes(Uint8List credentialId, Uint8List prfSalt) {
    final output = Uint8List(32);
    for (var i = 0; i < output.length; i++) {
      final left = credentialId[i % credentialId.length];
      final right = prfSalt[i % prfSalt.length];
      output[i] = (left ^ right ^ i) & 0xff;
    }
    return output;
  }
}
