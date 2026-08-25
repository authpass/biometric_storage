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
  Future<BiometricStorageFile> freshStore(String label) async {
    final name =
        'integration_${label}_${DateTime.now().microsecondsSinceEpoch}';
    final file = await storage.getStorage(name, options: options);
    addTearDown(() async {
      try {
        await file.delete();
      } catch (_) {
        // Best effort: a test that failed mid-way may have left nothing.
      }
    });
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
    addTearDown(() async {
      try {
        await first.delete();
      } catch (_) {}
    });

    // Without the flag a repeat is silently accepted.
    await storage.getStorage(name, options: options);

    await expectLater(
      storage.getStorage(name, options: options, forceInit: true),
      throwsA(isA<BiometricStorageException>()),
    );
  });

  testWidgets('canAuthenticate reports something the Dart side understands', (
    tester,
  ) async {
    // Not asserting a particular value — it depends entirely on the machine —
    // only that the native string maps to a known enum member rather than
    // throwing a StateError, which is how #148 surfaced on Android 16.
    expect(
      await storage.canAuthenticate(options: options),
      isA<CanAuthenticateResponse>(),
    );
  });
}
