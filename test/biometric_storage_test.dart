import 'package:biometric_storage/src/biometric_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('biometric_storage');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'canAuthenticate') {
            return 'ErrorUnknown';
          }
          throw PlatformException(code: 'NotImplemented');
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('canAuthenticate', () async {
    final result = await BiometricStorage().canAuthenticate();
    expect(result, CanAuthenticateResponse.unsupported);
  });

  group('StorageFileInitOptions', () {
    test('omits the keychain access group by default', () {
      expect(
        StorageFileInitOptions().toJson()['darwinKeychainAccessGroup'],
        isNull,
      );
    });

    test('passes the keychain access group to the platform', () {
      final options = StorageFileInitOptions(
        darwinKeychainAccessGroup: 'ABCDE12345.com.example.app',
      );
      expect(
        options.toJson()['darwinKeychainAccessGroup'],
        'ABCDE12345.com.example.app',
      );
    });
  });
}
