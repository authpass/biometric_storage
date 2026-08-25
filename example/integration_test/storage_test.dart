import 'dart:io';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs the plugin against the real platform backend — libsecret on Linux, the
/// keychain on macOS, the keystore on Android.
///
/// The unit suite only *compiles* the native side; nothing here or in CI has
/// ever executed the Linux implementation, so its `forceInit` bookkeeping, the
/// hash table's lifetime and six rewritten response sites are verified by
/// reading alone. These tests are what make that code run.
///
/// Everything uses `authenticationRequired: false`. An authenticated store
/// would need a real biometric or credential gesture, which no CI runner can
/// give — see the emulator work in #151 for how much scaffolding that takes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final storage = BiometricStorage();
  // Not const: StorageFileInitOptions resolves defaults in its initialiser list.
  final options = StorageFileInitOptions(authenticationRequired: false);

  /// A name no other run can collide with; the store is deleted afterwards even
  /// if the test fails, so a crashed run cannot poison the next one.
  ///
  /// Deliberately uncaught. Deleting a store that was never written is a
  /// success on every platform — Android guards on `exists()`, libsecret
  /// reports `removed = false` without an error, the keychain maps
  /// `errSecItemNotFound` to `true`, and win32 maps `ERROR_NOT_FOUND` to
  /// `false` — so the only thing a `catch` here could swallow is a store that
  /// genuinely failed, which is exactly what this suite exists to surface.
  Future<BiometricStorageFile> freshStore(String label) async {
    final name =
        'integration_${label}_${DateTime.now().microsecondsSinceEpoch}';
    final file = await storage.getStorage(name, options: options);
    addTearDown(() => file.delete());
    return file;
  }

  testWidgets('a value written can be read back, and is gone after delete', (
    tester,
  ) async {
    final file = await freshStore('roundtrip');

    expect(await file.read(), isNull, reason: 'nothing stored yet');

    // Deliberately not ASCII: the value crosses the channel as UTF-8 and, on
    // Linux, goes through libsecret's own string handling.
    await file.write('hello wörld — ✓');
    expect(await file.read(), 'hello wörld — ✓');

    await file.delete();
    expect(await file.read(), isNull);
  });

  testWidgets('writing twice keeps the second value', (tester) async {
    final file = await freshStore('overwrite');

    await file.write('first');
    await file.write('second');
    expect(await file.read(), 'second');
  });

  testWidgets('an empty value round-trips', (tester) async {
    final file = await freshStore('empty');

    await file.write('');
    expect(await file.read(), '');
  });

  testWidgets('reading a store that was never written returns null', (
    tester,
  ) async {
    final file = await freshStore('absent');
    expect(await file.read(), isNull);
  });

  testWidgets('a repeat getStorage is a no-op, and forceInit rejects it', (
    tester,
  ) async {
    // The point of this test. `handleInit` on Linux gained per-run bookkeeping
    // in 6.0.0-dev.3 that nothing has ever executed; a round-trip test alone
    // would not reach it, because it never calls getStorage twice.
    final name =
        'integration_forceinit_${DateTime.now().microsecondsSinceEpoch}';

    final first = await storage.getStorage(name, options: options);
    addTearDown(() => first.delete());

    // Without the flag a repeat is silently accepted. This executes the native
    // no-op branch but cannot pin it: the `false` never surfaces through the
    // public API.
    await storage.getStorage(name, options: options);

    // The code, not just the type. On the method-channel platforms the type
    // alone is already discriminating — only the native repeat-plus-forceInit
    // branch emits `AlreadyInitialized`, and anything else stays a
    // PlatformException — but naming the code guards the day a second native
    // code becomes translated, and matches the unit suite.
    await expectLater(
      storage.getStorage(name, options: options, forceInit: true),
      throwsA(
        isA<BiometricStorageException>().having(
          (e) => e.code,
          'code',
          BiometricStorageExceptionCode.alreadyInitialized,
        ),
      ),
    );
  });

  testWidgets('canAuthenticate reports something the Dart side understands', (
    tester,
  ) async {
    // The assertion is `completes`, not a value: what fails here is an
    // unmapped native string, which throws a StateError inside
    // canAuthenticate. That is how #148 surfaced on Android 16. `isA<
    // CanAuthenticateResponse>()` would be the same test — the return type
    // makes it a tautology — but it reads as though the type were the point,
    // and invites a later reader to "fix" it by deleting the test.
    await expectLater(storage.canAuthenticate(options: options), completes);

    // Linux is the one platform whose answer does not depend on the machine:
    // the C hard-codes "ErrorHwUnavailable", so the native-string-to-enum
    // mapping itself can be pinned there.
    if (Platform.isLinux) {
      expect(
        await storage.canAuthenticate(options: options),
        CanAuthenticateResponse.errorHwUnavailable,
      );
    }
  });
}
