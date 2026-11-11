import 'dart:convert';
import 'dart:io';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:biometric_storage_example/envelope_example.dart';
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
  /// success on every platform — Android removes an absent key and file
  /// without complaint, libsecret
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

  /// A name for a test that disposes the store itself.
  ///
  /// [freshStore] cannot be used for those: it holds the file it handed out
  /// and deletes through it, and a disposed handle refuses every operation.
  /// Re-acquiring first is what makes the cleanup work whether or not the test
  /// left the name disposed.
  String disposableName(String label) {
    final name =
        'integration_${label}_${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(() async {
      final file = await storage.getStorage(name, options: options);
      await file.delete();
    });
    return name;
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

  testWidgets('delete is safe on a store with nothing stored', (tester) async {
    // `delete` no longer guards the removal on a file existing, because a key
    // can outlive one — `cipherForEncrypt` mints it before the prompt, so a
    // cancelled first write leaves a key alone. That makes the keystore
    // removal run for a store that may have no key either, which has to be
    // harmless, and twice over.
    //
    // What this does not reach is the leak that motivated the change: it needs
    // a write cancelled at a biometric prompt, which no runner can do. So this
    // covers the new unconditional path's safety, not the case it fixes.
    final name = disposableName('delete_empty');
    final file = await storage.getStorage(name, options: options);

    // No assertion on a return value: `BiometricStorageFile.delete()` is
    // `Future<void>`, so the "was something deleted" answer the native side
    // computes never reaches a caller through this API.
    await file.delete();
    await file.delete();
    // Still usable afterwards, which is the part that would break if removing
    // an absent key threw.
    await file.write('after');
    expect(await file.read(), 'after');
    await file.delete();
    expect(await file.read(), isNull);
  });

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

  testWidgets('dispose lets a later getStorage initialize the name again', (
    tester,
  ) async {
    // The load-bearing test for dispose, and the one that fails against every
    // backend as it stood before this change: Linux had no `dispose` handler
    // at all, so the call raised MissingPluginException, and darwin replied
    // `true` from a no-op that never cleared its `stores` entry.
    //
    // forceInit is what makes the effect observable through the public API.
    // It means "assert this name is not initialized", so it succeeds only if
    // dispose really did forget the name — a dispose that silently does
    // nothing leaves this throwing alreadyInitialized.
    final name = disposableName('dispose_reinit');
    final file = await storage.getStorage(name, options: options);

    expect(await file.dispose(), isTrue, reason: 'there was one to forget');

    await expectLater(
      storage.getStorage(name, options: options, forceInit: true),
      completes,
    );
  });

  testWidgets('dispose keeps the stored content', (tester) async {
    // The contract that separates dispose from delete: it reconfigures, it
    // does not erase. Worth pinning because every backend implements it by
    // dropping a registry entry, and reaching one line further to remove the
    // secret would be an easy and very expensive mistake.
    final name = disposableName('dispose_keeps');
    final file = await storage.getStorage(name, options: options);
    await file.write('survives');

    expect(await file.dispose(), isTrue);

    final reopened = await storage.getStorage(name, options: options);
    expect(await reopened.read(), 'survives');
  });

  testWidgets('disposing twice is not an error', (tester) async {
    // Android used to throw NoSuchStorage on the second call, which made it
    // the only backend where a repeat dispose failed. The bool distinguishes
    // "forgot one" from "there was none" without anybody having to catch.
    final name = disposableName('dispose_twice');
    final file = await storage.getStorage(name, options: options);

    expect(await file.dispose(), isTrue);
    expect(await file.dispose(), isFalse, reason: 'nothing left to forget');
  });

  testWidgets('dispose is scoped to the name, not to the handle', (
    tester,
  ) async {
    // Every handle is a view onto one name-keyed initialization, so a spent
    // handle can still forget an initialization made after it. Pinned because
    // the tempting optimization — short-circuiting a repeat dispose on the
    // local flag instead of asking the platform — would quietly turn dispose
    // from name-scoped into handle-scoped and make this return false.
    final name = disposableName('dispose_scope');

    final first = await storage.getStorage(name, options: options);
    expect(await first.dispose(), isTrue);

    // A fresh initialization of the same name, which `first` knows nothing of.
    await storage.getStorage(name, options: options);

    expect(
      await first.dispose(),
      isTrue,
      reason: 'the spent handle still forgets the name it names',
    );
  });

  testWidgets('a disposed file refuses to be used again', (tester) async {
    // The backends do not agree on their own: Android and darwin resolve
    // read/write/delete against a registry and fail once the entry is gone,
    // while Linux answers from the name alone and would carry on. The guard
    // is in Dart so the answer is the same everywhere — otherwise this is a
    // mistake you make on one platform and discover on another.
    final name = disposableName('dispose_spent');
    final file = await storage.getStorage(name, options: options);

    expect(await file.dispose(), isTrue);

    expect(() => file.read(), throwsStateError);
    expect(() => file.write('x'), throwsStateError);
    expect(() => file.delete(), throwsStateError);
    // Not dispose itself, which stays idempotent.
    expect(await file.dispose(), isFalse);
  });

  group('the envelope pattern', () {
    /// Exercises `EnvelopeStore` from `lib/envelope_example.dart` against the
    /// real backends. This is the README's recommended answer to #129, #108
    /// and #112, so it should be a thing that runs rather than a snippet
    /// nobody compiled.
    ///
    /// The gate is unauthenticated here, for the reason the file header gives:
    /// no CI runner can produce a biometric gesture. So what these prove is
    /// the composition and the cryptography — two stores, a sealed token, a
    /// key that round-trips, rotation that touches only the token store. What
    /// they cannot prove is the prompt itself: that a per-use gate raises one
    /// on every read is the keystore's and the keychain's behavior, and only a
    /// device run shows it.
    EnvelopeStore freshEnvelope(String label) {
      final suffix = '${label}_${DateTime.now().microsecondsSinceEpoch}';
      final store = EnvelopeStore(
        gateName: 'integration_gate_$suffix',
        tokenName: 'integration_token_$suffix',
        gateOptions: StorageFileInitOptions(authenticationRequired: false),
      );
      addTearDown(store.reset);
      return store;
    }

    /// Either half of an [EnvelopeStore], reached around it rather than
    /// through it. Several of these tests have to assert about what is on disk,
    /// and asking the store itself would be asking the code under test.
    Future<BiometricStorageFile> gateOf(EnvelopeStore store) =>
        BiometricStorage().getStorage(
          store.gateName,
          options: StorageFileInitOptions(authenticationRequired: false),
        );

    Future<BiometricStorageFile> tokenOf(EnvelopeStore store) =>
        BiometricStorage().getStorage(
          store.tokenName,
          options: StorageFileInitOptions(authenticationRequired: false),
        );

    Future<String?> rawGate(EnvelopeStore store) async =>
        (await gateOf(store)).read();

    Future<String?> rawToken(EnvelopeStore store) async =>
        (await tokenOf(store)).read();

    testWidgets('a secret enrolled under the gate reads back', (tester) async {
      final store = freshEnvelope('roundtrip');
      await store.enroll('refresh-token-1');
      store.lock();

      expect(await store.login(), 'refresh-token-1');
    });

    testWidgets('the token store holds ciphertext, not the secret', (
      tester,
    ) async {
      // The point of the pattern: that store has no authentication at all, so
      // if it held the plaintext the whole arrangement would be pointless.
      final store = freshEnvelope('sealed');
      await store.enroll('refresh-token-1');

      final raw = await rawToken(store);

      expect(raw, isNotNull);
      // Decoded, not as stored. Asking whether the base64 *text* contains the
      // secret would pass for a `seal` that merely base64-encoded it, since
      // base64 hides a literal substring on its own — the assertion has to see
      // the bytes to mean anything.
      final bytes = utf8.decode(base64Decode(raw!), allowMalformed: true);
      expect(bytes, isNot(contains('refresh-token-1')));
    });

    testWidgets('rotation does not read the gate', (tester) async {
      // The gate is *deleted* before rotating, which is what makes the
      // property reachable: asserting only that the new value reads back
      // would pass against a rotate that re-read the gate, since nothing
      // here would notice. With no gate to read, a rotate that reaches for
      // one fails instead.
      final store = freshEnvelope('rotate');
      await store.enroll('refresh-token-1');
      final before = await rawToken(store);

      await (await gateOf(store)).delete();
      await store.rotate('refresh-token-2');

      expect(await rawToken(store), isNot(before));
    });

    testWidgets('a rotated secret is what the next login returns', (
      tester,
    ) async {
      // The companion to the test above, which deletes the gate and so cannot
      // log in afterwards. Without this one, a rotate that sealed under the
      // wrong key, or under the wrong slot, or that simply emptied the token
      // store, would pass: "the bytes changed" is not "the right bytes".
      final store = freshEnvelope('rotate_roundtrip');
      await store.enroll('refresh-token-1');
      await store.rotate('refresh-token-2');
      store.lock();

      expect(await store.login(), 'refresh-token-2');
    });

    testWidgets('a blob sealed for another store does not open', (
      tester,
    ) async {
      // What the associated data buys. Both stores share a gate, so they share
      // a data key: only the slot bound into the seal distinguishes them.
      // Remove `aad:` from seal and open and this is the test that notices —
      // without it, the binding could be deleted and the suite stay green.
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final gate = 'integration_gate_shared_$suffix';
      final unauthenticated = StorageFileInitOptions(
        authenticationRequired: false,
      );
      final a = EnvelopeStore(
        gateName: gate,
        tokenName: 'integration_token_a_$suffix',
        gateOptions: unauthenticated,
      );
      final b = EnvelopeStore(
        gateName: gate,
        tokenName: 'integration_token_b_$suffix',
        gateOptions: unauthenticated,
      );
      addTearDown(a.reset);
      addTearDown(b.reset);

      await a.enroll('secret-a');
      // b enrolls second, so the shared gate ends up holding b's key; a's blob
      // is then re-sealed under it below, leaving the slot as the only
      // difference between the two.
      await b.enroll('secret-b');
      await b.rotate('secret-a-moved');
      final bBlob = (await rawToken(b))!;

      // Move b's blob into a's store. Same key, same contents, wrong slot.
      await (await tokenOf(a)).write(bBlob);
      a.lock();

      expect(await a.login(), isNull);
    });

    testWidgets('rotation refuses without a key in memory', (tester) async {
      final store = freshEnvelope('locked');
      await store.enroll('refresh-token-1');
      store.lock();

      // awaited: rotate is async, and an un-awaited matcher on a future is a
      // bet on the framework noticing the rejection for us.
      await expectLater(
        () => store.rotate('refresh-token-2'),
        throwsStateError,
      );
    });

    testWidgets('a tampered token is refused, not returned', (tester) async {
      // The README's one cryptographic instruction is to use an authenticated
      // cipher. Without this test the whole group passes against AES-CTR, so
      // this is the test that holds that sentence up: flip one byte of the
      // ciphertext and the MAC check has to reject it.
      final store = freshEnvelope('tamper');
      await store.enroll('refresh-token-1');

      final sealed = base64Decode((await rawToken(store))!);
      // Past the 12-byte nonce, so it is the ciphertext that changes.
      sealed[20] ^= 0xff;
      await (await tokenOf(store)).write(base64Encode(sealed));
      store.lock();

      // Null rather than a throw: login treats a token it cannot open as
      // nothing stored, so the app re-enrolls rather than crashing. What
      // matters is that the tampered bytes are never returned as a secret.
      expect(await store.login(), isNull);
      expect(store.isUnlocked, isFalse);
    });

    testWidgets('a fresh nonce per seal, so two writes differ', (tester) async {
      // Guards the one mistake that would quietly break AES-GCM here. Same
      // key, same plaintext, different ciphertext.
      final store = freshEnvelope('nonce');
      await store.enroll('refresh-token-1');

      final first = await rawToken(store);
      await store.rotate('refresh-token-1');
      final second = await rawToken(store);

      expect(first, isNotNull);
      expect(second, isNot(first));
    });

    testWidgets('reset leaves nothing behind', (tester) async {
      final store = freshEnvelope('reset');
      await store.enroll('refresh-token-1');
      await store.reset();

      // Both stores are asked directly. Going through login() would pass
      // against a reset that deleted only the gate, because login() answers
      // null as soon as the gate is empty and never looks at the token.
      expect(await rawGate(store), isNull);
      expect(await rawToken(store), isNull);
      expect(store.isUnlocked, isFalse);
    });
  });
}
