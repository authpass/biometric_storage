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

  group('AlreadyInitialized translation', () {
    /// Replaces the default handler with one that fails `init` the way the
    /// method-channel platforms do. This is the only coverage of the clause in
    /// `getStorage` that turns their `PlatformException` into the package's own
    /// type — the path every platform except Windows and web takes.
    void mockInitFailure(PlatformException e) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            if (methodCall.method == 'init') {
              throw e;
            }
            throw PlatformException(code: 'NotImplemented');
          });
    }

    test('becomes a BiometricStorageException carrying the code', () async {
      mockInitFailure(
        PlatformException(
          code: 'AlreadyInitialized',
          message: "A storage file with the name 'x' was already initialized.",
        ),
      );

      await expectLater(
        BiometricStorage().getStorage('x', forceInit: true),
        throwsA(
          isA<BiometricStorageException>()
              .having(
                (e) => e.code,
                'code',
                BiometricStorageExceptionCode.alreadyInitialized,
              )
              .having((e) => e.message, 'message', contains('already')),
        ),
      );
    });

    test('any other platform error is passed through untranslated', () async {
      // The clause must be narrow: a storage failure from the native side is
      // still a PlatformException, which is the boundary the changelog names.
      mockInitFailure(
        PlatformException(code: 'SecurityError', message: 'keychain said no'),
      );

      await expectLater(
        BiometricStorage().getStorage('x'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'SecurityError',
          ),
        ),
      );
    });

    test('the original stack trace survives the translation', () async {
      // Regression guard for the Error.throwWithStackTrace introduced alongside
      // this: a plain `throw` would restart the trace inside getStorage.
      mockInitFailure(PlatformException(code: 'AlreadyInitialized'));

      try {
        await BiometricStorage().getStorage('x', forceInit: true);
        fail('expected a BiometricStorageException');
      } on BiometricStorageException catch (_, stackTrace) {
        // Not `contains('biometric_storage')` — that passes either way, since a
        // plain `throw` also originates in this package. The channel frames are
        // what only a preserved trace has; a restarted one begins at
        // getStorage.
        expect(
          stackTrace.toString(),
          contains('MethodChannel._invokeMethod'),
          reason: 'the trace should still start at the failing channel call',
        );
      }
    });
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
      // Both halves: dropping either from toString() should fail this.
      expect(e.toString(), contains('storageFailure'));
      expect(e.toString(), contains('boom'));
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
