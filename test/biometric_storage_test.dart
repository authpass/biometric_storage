// Deliberately the public barrel rather than `src/`: it re-exports the Windows
// implementation on every `dart.library.io` platform, so importing it here is
// what makes `flutter test` on macOS or Linux compile the win32 bindings. A
// breaking change in package:win32 shows up as a failing test run rather than
// as a broken iOS build in somebody else's app.
import 'package:biometric_storage/biometric_storage.dart';
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

  test('the windows implementation is part of the compiled library', () {
    expect(Win32BiometricStoragePlugin, isNotNull);
  });

  group('BiometricStorageException', () {
    test('defaults to unknown, so the positional constructor still works', () {
      final e = BiometricStorageException('boom');
      expect(e.code, BiometricStorageExceptionCode.unknown);
      expect(e.message, 'boom');
    });

    test('carries the code it was given, and shows it', () {
      final e = BiometricStorageException(
        'boom',
        code: BiometricStorageExceptionCode.storageFailure,
      );
      expect(e.code, BiometricStorageExceptionCode.storageFailure);
      expect(e.toString(), contains('storageFailure'));
    });
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
