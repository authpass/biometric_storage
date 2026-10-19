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

  // Android only: the Linux backend does not keep unawaited calls in order
  // (CI on #159 read null here), and nothing in this change touches it.
  testWidgets(
    'a read issued behind a write sees the write',
    skip: !Platform.isAndroid,
    (tester) async {
      // The calls leave Dart in order and the platform must keep that order,
      // whichever thread does the work. On Android the work moved off the main
      // thread in 6.0.0-dev.6, and a read that decided "no file yet" on the main
      // thread while the write still sat on the worker answered null here.
      final file = await freshStore('ordering');

      final write = file.write('queued');
      final read = file.read();
      final delete = file.delete();
      expect(await read, 'queued');
      await delete;
      await write;
      expect(
        await file.read(),
        isNull,
        reason: 'the delete ran after the write',
      );
    },
  );

  /// The Android backend's file for [file]: `<filesDir>/biometric_storage/`,
  /// beside the cache directory `Directory.systemTemp` names.
  File androidStoreFile(BiometricStorageFile file) => File(
    '${Directory.systemTemp.parent.path}/files/biometric_storage/'
    '${file.name}.v2.txt',
  );

  // Android only, both: they reach into the backend's own file.
  testWidgets(
    'a file whose key is gone reads as nothing, and the store works again',
    skip: !Platform.isAndroid,
    (tester) async {
      // A backup restored onto another device brings the file and never the
      // keystore key. `delete` removes both; putting the bytes back is that.
      final file = await freshStore('keyless');
      await file.write('before the restore');
      final onDisk = androidStoreFile(file);
      final bytes = await onDisk.readAsBytes();
      await file.delete();
      await onDisk.writeAsBytes(bytes);

      expect(await file.read(), isNull);
      expect(onDisk.existsSync(), isFalse, reason: 'the orphan is set aside');
      expect(
        File('${onDisk.path}.unreadable').existsSync(),
        isTrue,
        reason: 'set aside, not deleted: a wrong verdict costs a rename',
      );
      await file.write('after');
      expect(await file.read(), 'after');
      await file.delete();
      expect(
        File('${onDisk.path}.unreadable').existsSync(),
        isFalse,
        reason: 'delete removes the side file too',
      );
    },
  );

  testWidgets(
    'delete removes a file set aside even when nothing was written since',
    skip: !Platform.isAndroid,
    (tester) async {
      final file = await freshStore('aside');
      await file.write('to be set aside');
      final onDisk = androidStoreFile(file);
      await onDisk.writeAsBytes([]);
      expect(await file.read(), isNull);
      final aside = File('${onDisk.path}.unreadable');
      expect(aside.existsSync(), isTrue);

      await file.delete();
      expect(aside.existsSync(), isFalse);
    },
  );

  testWidgets(
    'a file too short to hold a tag reads as nothing, and the store works again',
    skip: !Platform.isAndroid,
    (tester) async {
      // What a power loss leaves after a rename that landed before its data,
      // or a write torn before writes went through a partial file. Neither
      // heal path on the PR covered it: every read threw.
      final file = await freshStore('short');
      await file.write('intact');
      final onDisk = androidStoreFile(file);
      await onDisk.writeAsBytes([]);

      expect(await file.read(), isNull);
      expect(onDisk.existsSync(), isFalse);
      await file.write('again');
      expect(await file.read(), 'again');
    },
  );

  testWidgets(
    'a file that does not decrypt reads as nothing, and the store works again',
    skip: !Platform.isAndroid,
    (tester) async {
      final file = await freshStore('torn');
      await file.write('intact');
      final onDisk = androidStoreFile(file);
      final bytes = await onDisk.readAsBytes();
      bytes[bytes.length - 1] ^= 0xff; // the GCM tag no longer matches
      await onDisk.writeAsBytes(bytes);

      expect(await file.read(), isNull);
      await file.write('again');
      expect(await file.read(), 'again');
      expect(
        File('${onDisk.path}.partial').existsSync(),
        isFalse,
        reason: 'a write leaves no partial file behind',
      );
    },
  );

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
