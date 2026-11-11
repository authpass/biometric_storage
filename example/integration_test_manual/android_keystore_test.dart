// Settles, on a device, the claims this package makes about what a keystore
// key keeps from the moment it is created. Those claims are in `dispose()`'s
// doc comment and in the 6.0.0-dev.10 changelog, and until this ran they were
// established by reading the plugin's sources.
//
// Unlike `storage_test.dart`, these stores authenticate, so the run needs an
// emulator with a lock credential and an enrolled fingerprint, and something
// outside the test answering the prompts:
//
//     adb shell locksettings set-pin 1234
//     # enroll a print: Settings, then `adb emu finger touch 1` at the sensor
//     # screen until it says "Fingerprint added"
//     while true; do adb emu finger touch 1; sleep 1; done
//     flutter test integration_test_manual/android_keystore_test.dart -d <id>
//
// This directory is deliberately not `integration_test/`, which CI runs whole.
// `flutter test` relaunches the app once per file, and the second launch fails
// on desktop with "Unable to start the app on the device" — so a second file
// in there breaks the Linux job even when every test in it would skip. Run
// this one by path, on purpose.
//
// Each test reports what it observed before asserting, because the point here
// is to find out, and the interesting outcome is the one nobody predicted. In
// particular, a read that answers `null` rather than throwing would mean the
// file was moved aside as unreadable — silent data loss, and a worse finding
// than the error this expects.

import 'dart:io';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final storage = BiometricStorage();

  String freshName(String label) =>
      'keystore_${label}_${DateTime.now().microsecondsSinceEpoch}';

  /// Runs [body] and describes how it ended, so a failure reports the thing
  /// that happened rather than only the thing that did not.
  Future<String> outcomeOf(Future<String?> Function() body) async {
    try {
      final value = await body();
      return value == null ? 'returned null' : 'returned a value';
    } on AuthException catch (e) {
      return 'AuthException(${e.code})';
    } on PlatformException catch (e) {
      return 'PlatformException(${e.code})';
    } catch (e) {
      return '${e.runtimeType}';
    }
  }

  group('a key keeps the authentication it was created with', () {
    testWidgets('a duration set over a per-use key', (tester) async {
      final name = freshName('perUseThenDuration');

      final perUse = await storage.getStorage(
        name,
        options: StorageFileInitOptions(authenticationRequired: true),
      );
      await perUse.write('secret');
      expect(await perUse.dispose(), isTrue);

      final windowed = await storage.getStorage(
        name,
        options: StorageFileInitOptions(
          authenticationRequired: true,
          androidAuthenticationValidityDuration: const Duration(seconds: 5),
        ),
      );
      final outcome = await outcomeOf(windowed.read);
      addTearDown(windowed.delete);

      // ignore: avoid_print
      print('OBSERVED perUse -> duration: $outcome');
      // Pinned to what the emulator did, not loosened to "something failed":
      // `returned null` here would mean readFile had moved the file aside as
      // unreadable, which is data loss wearing the same face as an empty
      // store, and that is the outcome worth failing for.
      expect(outcome, 'PlatformException(Unexpected Error)');
    }, skip: !Platform.isAndroid);

    testWidgets('a per-use key over a duration, window closed', (tester) async {
      final name = freshName('durationThenPerUse');

      final windowed = await storage.getStorage(
        name,
        options: StorageFileInitOptions(
          authenticationRequired: true,
          androidAuthenticationValidityDuration: const Duration(seconds: 3),
        ),
      );
      await windowed.write('secret');
      expect(await windowed.dispose(), isTrue);

      final perUse = await storage.getStorage(
        name,
        options: StorageFileInitOptions(authenticationRequired: true),
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      final outcome = await outcomeOf(perUse.read);
      addTearDown(perUse.delete);

      // ignore: avoid_print
      print('OBSERVED duration -> perUse (window closed): $outcome');
      expect(outcome, 'PlatformException(Unexpected Error)');
    }, skip: !Platform.isAndroid);

    testWidgets('a per-use key over a duration, window still open', (
      tester,
    ) async {
      // The other half of the claim that this direction is *intermittent*
      // rather than broken: with the window open the keystore should authorize
      // the operation, so the same reconfiguration that fails above is
      // expected to succeed here. If it fails too, the honest description is
      // "always fails", which is a better story than a flaky store — so this
      // test exists to be able to say which.
      final name = freshName('durationThenPerUseOpen');

      final windowed = await storage.getStorage(
        name,
        options: StorageFileInitOptions(
          authenticationRequired: true,
          androidAuthenticationValidityDuration: const Duration(seconds: 30),
        ),
      );
      await windowed.write('secret');
      expect(await windowed.dispose(), isTrue);

      final perUse = await storage.getStorage(
        name,
        options: StorageFileInitOptions(authenticationRequired: true),
      );
      // No delay: the write above authenticated moments ago, so the key's
      // 30 second window is open.
      final outcome = await outcomeOf(perUse.read);
      addTearDown(perUse.delete);

      // ignore: avoid_print
      print('OBSERVED duration -> perUse (window open): $outcome');
      // This is what makes the direction intermittent rather than broken, and
      // it is the pair with the test above that earns the word: same
      // reconfiguration, opposite outcome, decided only by how long the user
      // waited.
      expect(outcome, 'returned a value');
    }, skip: !Platform.isAndroid);

    testWidgets('a store that was never reconfigured still works', (
      tester,
    ) async {
      // The control. Without it, the two tests above could both be reporting
      // "authenticated stores do not work on this emulator" and look like a
      // finding.
      final name = freshName('control');
      final file = await storage.getStorage(
        name,
        options: StorageFileInitOptions(authenticationRequired: true),
      );
      addTearDown(file.delete);

      await file.write('secret');
      expect(await file.read(), 'secret');
    }, skip: !Platform.isAndroid);
  });
}
