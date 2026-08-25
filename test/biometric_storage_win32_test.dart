@TestOn('windows')
library;

// Deliberately `src/` rather than the barrel: the barrel reaches this class
// through a conditional export whose *default* branch is an empty stub, and the
// analyzer resolves to that stub, so calls through it would not type-check.
// biometric_storage_test.dart keeps the barrel import, which is what makes the
// bindings compile on every host.
import 'package:biometric_storage/src/biometric_storage.dart';
import 'package:biometric_storage/src/biometric_storage_win32.dart';
import 'package:flutter_test/flutter_test.dart';

/// The only place the win32 bindings are *executed* rather than merely
/// compiled. Everything else in the suite compiles them on whatever host it
/// runs on, which catches an API break but not a wrong pointer.
///
/// This talks to the real Windows credential store, which is available headless
/// — including on CI runners. Each test uses a name of its own and deletes it
/// again, so it cannot collide with a developer's own credentials.
void main() {
  final plugin = Win32BiometricStoragePlugin();

  Future<BiometricStorageFile> storageForThisTest() async {
    final name = 'test_${DateTime.now().microsecondsSinceEpoch}';
    final file = await plugin.getStorage(name);
    addTearDown(() => file.delete());
    return file;
  }

  test('a value written can be read back, and is gone after delete', () async {
    final file = await storageForThisTest();

    expect(await file.read(), isNull, reason: 'nothing stored yet');

    // Deliberately not ASCII: the blob round-trips through utf8.
    await file.write('hello wörld');
    expect(await file.read(), 'hello wörld');

    await file.delete();
    expect(await file.read(), isNull);
  });

  test('an empty value round-trips', () async {
    final file = await storageForThisTest();

    // Regression: this used to reach Uint8List.toNative(), which rejects an
    // empty list, so writing an empty value threw.
    await file.write('');
    expect(await file.read(), '');
  });

  test('writing twice keeps the second value', () async {
    final file = await storageForThisTest();

    await file.write('first');
    await file.write('second');
    expect(await file.read(), 'second');
  });

  test('the credential name keeps its historical prefix', () async {
    // Every other test here writes and reads through the same prefix, so all of
    // them would stay green if it changed — while every existing user's stored
    // value was orphaned. This pins the on-disk contract. `getStorage` only
    // builds the name; it does not touch the credential store.
    final file = await plugin.getStorage('example');
    expect(file.name, 'design.codeux.authpass.example');
  });

  test('forceInit rejects a second getStorage for the same name', () async {
    final name = 'test_force_${DateTime.now().microsecondsSinceEpoch}';

    // The first call establishes it; a plain second call is a no-op. Only
    // forceInit turns "already initialized" into an error, which is what the
    // API documents and what Android has always done.
    await plugin.getStorage(name);
    await plugin.getStorage(name);

    expect(
      () => plugin.getStorage(name, forceInit: true),
      throwsA(isA<BiometricStorageException>()),
    );
  });

  test('reading an unknown name returns null rather than throwing', () async {
    final file = await plugin.getStorage(
      'test_absent_${DateTime.now().microsecondsSinceEpoch}',
    );
    expect(await file.read(), isNull);
  });
}
