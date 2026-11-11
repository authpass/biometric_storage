// The envelope pattern: a biometric prompt on every login, with no
// authentication validity window, and secret rotation that raises no prompt.
//
// Why this file exists. The obvious way to avoid a prompt on every write is a
// long `androidAuthenticationValidityDuration`, and that is what
// https://github.com/authpass/biometric_storage/issues/129,
// https://github.com/authpass/biometric_storage/issues/108 and
// https://github.com/authpass/biometric_storage/issues/112 all reach for. It
// has a flaw the platform will not let the plugin fix: once the window is open
// there is no way to close it early. Android has no API to revoke an
// authentication, a device unlock renews the window, and a store cannot be
// reconfigured to a shorter one — on Android a key's authentication parameters
// are fixed when the key is created, so neither `dispose()` nor a repeat
// `getStorage` changes them.
//
// So instead of asking the OS to forget an authentication, do not open a
// window at all. Keep two stores:
//
//   * a *gate* that authenticates per use and holds a random data key, and
//   * a *token* store with no authentication at all, holding the secret
//     encrypted under that data key.
//
// Reading the gate is the login: on Android a `BiometricPrompt` bound to a
// `CryptoObject` over a per-use key, enforced by the keystore rather than by
// this app; on iOS and macOS a keychain access-control evaluation with a fresh
// `LAContext`. There is no window to leak and nothing for an attacker to
// inherit from a device unlock. Rotating the secret needs only the data key
// that is already in memory, so it raises no prompt — which is the whole of
// what #108 and #112 were asking for.
//
// What this costs, and the first one is the one that decides whether you
// should use this at all:
//
//   * **A biometric enrollment change destroys the secret.** The gate key is
//     biometric-only, so both platforms invalidate it when the enrolled set
//     changes — Android on a new enrollment or the removal of the last
//     biometric, darwin because the item is held under `.biometryCurrentSet`.
//     The sealed token is then undecryptable. Only Android says so, reporting
//     `AuthExceptionCode.keyInvalidated`; on iOS and macOS the keychain cannot
//     distinguish that from a failed attempt, so it arrives as
//     `AuthExceptionCode.authFailed` and keeps arriving. See the README for
//     what to do about that. Note what this means for anyone arriving from #129 or
//     #108: a store with a validity duration allows the device credential as
//     well, and keys like that are *not* invalidated by enrollment — so this
//     pattern trades a window you cannot close for a secret you can lose. For
//     a refresh token that is a good trade, because the user can log in again
//     and you re-enroll. For a secret that cannot be regenerated it is the
//     wrong pattern, and you should keep a recovery path outside it.
//   * It is an Android and darwin pattern. On Linux there is no biometric
//     support, and on web both stores are unencrypted `localStorage`, so the
//     gate raises no prompt and the data key sits beside the ciphertext it
//     protects. The pattern gives nothing there.
//   * The app owns one piece of cryptography (below), and the data key sits in
//     the Dart heap for the duration of a session — which is where the
//     plaintext secret already sat in every design these issues describe.
//
// The simpler variant, putting the secret straight into the per-use store,
// needs no crypto here but brings back a prompt on every rotation.

import 'dart:convert';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final _logger = Logger('envelope_example');

/// AES-GCM over the token, with a fresh nonce per encryption and the store's
/// name bound in as associated data.
///
/// `package:cryptography` is one choice among several; any authenticated
/// cipher (AEAD) will do. What matters is that it is authenticated: the token
/// store is deliberately unprotected on disk, so a non-authenticated cipher
/// would let anything that can write there change the plaintext by changing
/// the ciphertext. Authentication detects that — it does not prevent the
/// write, and it does not make the file tamper-*proof*. In particular it does
/// not stop an *old* sealed token being put back, since that one was sealed
/// by this key too; defending against rollback needs a counter or a timestamp
/// inside the plaintext.
///
/// Without `cryptography_flutter` added as well, this runs as pure Dart on
/// mobile rather than through the platform's own implementation, so it is not
/// constant-time. For a locally stored token that does not matter; know it
/// before reusing the helper for something else.
class _Envelope {
  static final _algorithm = AesGcm.with256bits();

  static Future<List<int>> newDataKey() async {
    final key = await _algorithm.newSecretKey();
    return key.extractBytes();
  }

  /// Nonce, ciphertext and MAC in one blob, so the caller stores one string.
  /// A new nonce is generated for every call — reusing one under the same key
  /// would be the one mistake in this file that actually breaks AES-GCM.
  ///
  /// [slot] is bound in as associated data rather than encrypted: it is not
  /// secret, but binding it means a blob sealed for one store cannot be opened
  /// as another. That costs nothing here, where there is one token, and is
  /// what keeps two secrets from being swapped if you extend this to several.
  static Future<String> seal(
    String plainText,
    List<int> dataKey,
    String slot,
  ) async {
    final box = await _algorithm.encrypt(
      utf8.encode(plainText),
      secretKey: SecretKey(dataKey),
      aad: utf8.encode(slot),
    );
    return base64Encode(box.concatenation());
  }

  /// Throws [SecretBoxAuthenticationError] when the blob was not sealed by
  /// this key for this [slot], which covers a tampered file, a stale token
  /// left behind by an interrupted enrollment, and a mismatched store.
  static Future<String> open(
    String sealed,
    List<int> dataKey,
    String slot,
  ) async {
    final box = SecretBox.fromConcatenation(
      base64Decode(sealed),
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final clear = await _algorithm.decrypt(
      box,
      secretKey: SecretKey(dataKey),
      aad: utf8.encode(slot),
    );
    return utf8.decode(clear);
  }
}

/// The two stores and the operations over them.
///
/// Hold one of these for the lifetime of the app. [isUnlocked] is true exactly
/// while the user is logged in; [lock] ends that.
class EnvelopeStore {
  EnvelopeStore({
    this.gateName = 'envelope_gate',
    this.tokenName = 'envelope_token',
    StorageFileInitOptions? gateOptions,
  }) : gateOptions =
           gateOptions ?? StorageFileInitOptions(authenticationRequired: true) {
    if (!this.gateOptions.authenticationRequired) {
      // Says it out loud, because an unauthenticated gate is not a weaker
      // version of this pattern — it is the pattern switched off, with the
      // data key sitting unprotected next to the ciphertext it unlocks. The
      // integration test does exactly this on purpose; nothing else should.
      _logger.warning(
        'the gate does not require authentication: no prompt will be raised '
        'and the envelope protects nothing',
      );
    }
  }

  final String gateName;
  final String tokenName;

  /// Authenticates on every single use. No validity duration on Android, and
  /// neither darwin reuse duration, so there is no window on any platform.
  ///
  /// `androidBiometricOnly` stays at its default `true`: a per-use key is
  /// bound to `AUTH_BIOMETRIC_STRONG`, and the plugin rejects a null validity
  /// duration combined with device-credential authentication.
  ///
  /// Injectable for one reason only — the integration test runs this whole
  /// flow with `authenticationRequired: false`, because no CI runner can
  /// perform a biometric gesture. An app has no reason to pass it.
  final StorageFileInitOptions gateOptions;

  /// No authentication at all. The file on disk is ciphertext; its
  /// confidentiality comes from the data key in the gate, not from this store.
  static final _tokenOptions = StorageFileInitOptions(
    authenticationRequired: false,
  );

  List<int>? _dataKey;

  /// Whether a data key is held, which is to say whether the user is logged
  /// in. The bytes themselves stay private: a getter for them exists only to
  /// be misused, and the one thing a caller needs is this.
  bool get isUnlocked => _dataKey != null;

  Future<BiometricStorageFile> _gate() =>
      BiometricStorage().getStorage(gateName, options: gateOptions);

  Future<BiometricStorageFile> _token() =>
      BiometricStorage().getStorage(tokenName, options: _tokenOptions);

  /// First run: mint a data key, put it behind the prompt, and seal the secret
  /// under it. Raises a prompt for the gate write — though not necessarily on
  /// a first enrollment on iOS and macOS, where adding a keychain item is not
  /// the operation that evaluates its access control.
  ///
  /// The order matters on a migration from a single store: read the old secret
  /// first, then write both of these, and only then delete the old store. A
  /// crash anywhere in that sequence then leaves the old store intact.
  ///
  /// Re-enrolling over an existing enrollment has a window of its own: the new
  /// key lands before the new token, so a process that dies in between leaves
  /// a token sealed under a key that no longer exists. [login] reports that as
  /// "nothing stored", which is the recoverable answer — the app re-enrolls.
  Future<void> enroll(String secret) async {
    final key = await _Envelope.newDataKey();
    await (await _gate()).write(base64Encode(key));
    await (await _token()).write(await _Envelope.seal(secret, key, tokenName));
    _dataKey = key;
    _logger.fine('enrolled; data key held in memory');
  }

  /// The login. Raises one prompt — the gate read — and returns the secret, or
  /// null when there is nothing to return.
  ///
  /// Null covers every shape of "there is nothing here to give you", which a
  /// caller handles one way, by enrolling again: nothing was ever stored, the
  /// gate outlived its token, the gate holds something that is not a key, and
  /// the token is unopenable — whether it was tampered with, truncated, not a
  /// sealed blob at all, or sealed under a key an interrupted re-enrollment
  /// replaced.
  ///
  /// It does **not** cover a gate the OS has destroyed, which on Android
  /// arrives as `AuthException` with `AuthExceptionCode.keyInvalidated` —
  /// deliberately not caught here, because the secret is gone rather than
  /// absent, and an app usually wants to say so rather than silently start
  /// over. On iOS and macOS no such signal exists: the same loss arrives as
  /// `AuthExceptionCode.authFailed`, indistinguishable from a failed attempt,
  /// so it propagates from here too but tells the caller less. The file header
  /// and the README say what to do about that.
  Future<String?> login() async {
    // Any previous session ends here, before the attempt rather than after it.
    // A failed login that left an earlier key in place would report failure
    // while [rotate] still worked.
    _dataKey = null;

    final gateValue = await (await _gate()).read();
    if (gateValue == null) {
      return null;
    }
    final List<int> key;
    try {
      key = base64Decode(gateValue);
    } on FormatException catch (e) {
      // Whatever is under that name was not written by this class.
      _logger.warning('the gate does not hold a base64 key', e);
      return null;
    }
    final sealed = await (await _token()).read();
    if (sealed == null) {
      // The gate survived but the token did not. Hold the key so [rotate] can
      // write a fresh secret under the one just unlocked.
      _dataKey = key;
      _logger.warning('gate holds a key but no sealed token exists');
      return null;
    }
    try {
      final secret = await _Envelope.open(sealed, key, tokenName);
      // Only now: a key that cannot open the token is not a logged-in
      // session, and leaving it set would let [rotate] write under it.
      _dataKey = key;
      return secret;
    } on SecretBoxAuthenticationError catch (e) {
      _logger.warning('the stored token does not open with the gate key', e);
      return null;
    } on FormatException catch (e) {
      // Not base64 at all.
      _logger.warning('the stored token is not a sealed blob', e);
      return null;
    } on ArgumentError catch (e) {
      // Shorter than a nonce and a tag, so `SecretBox.fromConcatenation`
      // rejects it before any key is involved. Truncation on disk looks like
      // this.
      _logger.warning('the stored token is too short to be a sealed blob', e);
      return null;
    }
  }

  /// Replace the secret with no prompt, using the key [login] left in memory.
  /// This is the operation a validity window was being stretched to allow.
  Future<void> rotate(String secret) async {
    final key = _dataKey;
    if (key == null) {
      throw StateError('rotate() needs a successful login() first');
    }
    await (await _token()).write(await _Envelope.seal(secret, key, tokenName));
    _logger.fine('rotated without a prompt');
  }

  /// Log out: forget the data key. The next [login] must authenticate again,
  /// and nothing about the device's authentication state can shorten that.
  ///
  /// The reference is dropped and the bytes are **not** zeroed, deliberately.
  /// Zeroing them in place looks like good hygiene and is a trap here: an
  /// in-flight [rotate] holds the same list across its awaits, so a `lock()`
  /// at the wrong moment would seal the next secret under a key of zeros and
  /// write it to the store that has no authentication on it — losing the
  /// secret and producing a blob anyone can open. Nor would it achieve much:
  /// the same key reached this process as a base64 `String` from the platform
  /// channel, and Dart strings are immutable, so that copy stays in the heap
  /// regardless. Erasing a secret from a managed heap is not something this
  /// pattern can offer; pretending otherwise is worse than not trying.
  void lock() {
    _dataKey = null;
    _logger.fine('locked');
  }

  /// Remove both stores. The gate goes first: if only one delete succeeds, a
  /// surviving sealed token without its key is inert, while a surviving key
  /// without a token would invite [rotate] to write under a key the user
  /// thinks is gone.
  Future<void> reset() async {
    _dataKey = null;
    await (await _gate()).delete();
    await (await _token()).delete();
  }
}

/// A screen for the operations above, so the prompt behavior can be seen
/// rather than described: *Login* prompts every time, however often it is
/// pressed, and *Rotate* never does.
class EnvelopePage extends StatefulWidget {
  const EnvelopePage({super.key});

  @override
  State<EnvelopePage> createState() => _EnvelopePageState();
}

class _EnvelopePageState extends State<EnvelopePage> {
  final _store = EnvelopeStore();
  final _controller = TextEditingController(text: 'refresh-token-1');
  String _status = 'Not enrolled yet.';
  int _rotations = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(String label, Future<String> Function() action) async {
    try {
      final message = await action();
      setState(() => _status = message);
    } on AuthException catch (e) {
      setState(() => _status = '$label: ${e.code}');
    } catch (e) {
      _logger.warning('$label failed', e);
      setState(() => _status = '$label failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _store.isUnlocked;
    return Scaffold(
      appBar: AppBar(title: const Text('Envelope pattern')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Secret'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _run('enroll', () async {
                await _store.enroll(_controller.text);
                return 'Enrolled. Login is where the prompt is guaranteed.';
              }),
              // Not labeled as prompting: on iOS and macOS a first enrollment
              // adds the keychain item rather than updating one, and that is
              // not the operation which evaluates its access control.
              child: const Text('Enroll'),
            ),
            ElevatedButton(
              onPressed: () => _run('login', () async {
                final secret = await _store.login();
                return secret == null
                    ? 'Nothing enrolled.'
                    : 'Logged in, secret: $secret';
              }),
              child: const Text('Login (prompts every time)'),
            ),
            ElevatedButton(
              onPressed: !unlocked
                  ? null
                  : () => _run('rotate', () async {
                      _rotations++;
                      await _store.rotate('${_controller.text}-r$_rotations');
                      return 'Rotated to r$_rotations with no prompt.';
                    }),
              child: const Text('Rotate (no prompt)'),
            ),
            ElevatedButton(
              onPressed: !unlocked
                  ? null
                  : () => _run('lock', () async {
                      _store.lock();
                      return 'Locked. The next login must authenticate.';
                    }),
              child: const Text('Log out (drop the key)'),
            ),
            ElevatedButton(
              onPressed: () => _run('reset', () async {
                await _store.reset();
                return 'Both stores deleted.';
              }),
              child: const Text('Reset'),
            ),
            const SizedBox(height: 24),
            Text(_status),
          ],
        ),
      ),
    );
  }
}
