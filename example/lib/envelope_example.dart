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
// What this costs. The app owns one piece of cryptography (below), and the
// data key sits in the Dart heap for the duration of a session — which is
// where the plaintext secret already sat in every design these issues
// describe. The simpler variant, putting the secret straight into the per-use
// store, needs no crypto here but brings back a prompt on every rotation.

import 'dart:convert';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final _logger = Logger('envelope_example');

/// AES-GCM over the token, with a fresh nonce per encryption.
///
/// `package:cryptography` is one choice among several; any authenticated
/// cipher (AEAD) will do. What matters is that it is authenticated — a plain
/// stream cipher would leave the token file malleable, and the token store is
/// deliberately unprotected on disk.
class _Envelope {
  static final _algorithm = AesGcm.with256bits();

  static Future<List<int>> newDataKey() async {
    final key = await _algorithm.newSecretKey();
    return key.extractBytes();
  }

  /// Nonce, ciphertext and MAC in one blob, so the caller stores one string.
  /// A new nonce is generated for every call — reusing one under the same key
  /// would be the one mistake in this file that actually breaks AES-GCM.
  static Future<String> seal(String plainText, List<int> dataKey) async {
    final box = await _algorithm.encrypt(
      utf8.encode(plainText),
      secretKey: SecretKey(dataKey),
    );
    return base64Encode(box.concatenation());
  }

  static Future<String> open(String sealed, List<int> dataKey) async {
    final box = SecretBox.fromConcatenation(
      base64Decode(sealed),
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final clear = await _algorithm.decrypt(box, secretKey: SecretKey(dataKey));
    return utf8.decode(clear);
  }
}

/// The two stores and the operations over them.
///
/// Hold one of these for the lifetime of the app. [dataKey] is non-null
/// exactly while the user is logged in; [lock] drops it.
class EnvelopeStore {
  EnvelopeStore({
    this.gateName = 'envelope_gate',
    this.tokenName = 'envelope_token',
    StorageFileInitOptions? gateOptions,
  }) : gateOptions =
           gateOptions ?? StorageFileInitOptions(authenticationRequired: true);

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

  /// Null while locked. Present only between a successful [login] and a
  /// [lock], a [reset], or the process ending.
  List<int>? get dataKey => _dataKey;

  Future<BiometricStorageFile> _gate() =>
      BiometricStorage().getStorage(gateName, options: gateOptions);

  Future<BiometricStorageFile> _token() =>
      BiometricStorage().getStorage(tokenName, options: _tokenOptions);

  /// First run: mint a data key, put it behind the prompt, and seal the secret
  /// under it. Raises one prompt, for the gate write.
  ///
  /// The order matters on a migration from a single store: read the old secret
  /// first, then write both of these, and only then delete the old store. A
  /// crash anywhere in that sequence then leaves the old store intact.
  Future<void> enroll(String secret) async {
    final key = await _Envelope.newDataKey();
    await (await _gate()).write(base64Encode(key));
    await (await _token()).write(await _Envelope.seal(secret, key));
    _dataKey = key;
    _logger.fine('enrolled; data key held in memory');
  }

  /// The login. Raises exactly one prompt — the gate read — and returns the
  /// secret, or null when nothing is enrolled.
  Future<String?> login() async {
    final gateValue = await (await _gate()).read();
    if (gateValue == null) {
      return null;
    }
    final key = base64Decode(gateValue);
    final sealed = await (await _token()).read();
    _dataKey = key;
    if (sealed == null) {
      // The gate survived but the token did not. Treat it as "nothing stored"
      // rather than an error: [rotate] can write a fresh secret under the key
      // that was just unlocked.
      _logger.warning('gate holds a key but no sealed token exists');
      return null;
    }
    return _Envelope.open(sealed, key);
  }

  /// Replace the secret with no prompt, using the key [login] left in memory.
  /// This is the operation a validity window was being stretched to allow.
  Future<void> rotate(String secret) async {
    final key = _dataKey;
    if (key == null) {
      throw StateError('rotate() needs a successful login() first');
    }
    await (await _token()).write(await _Envelope.seal(secret, key));
    _logger.fine('rotated without a prompt');
  }

  /// Log out: forget the data key. The next [login] must authenticate again,
  /// and nothing about the device's authentication state can shorten that.
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
    final unlocked = _store.dataKey != null;
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
                return 'Enrolled. One prompt, for the gate write.';
              }),
              child: const Text('Enroll (prompts)'),
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
