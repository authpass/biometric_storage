import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:biometric_storage_platform_interface/biometric_storage_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

class BiometricStorageWeb extends BiometricStoragePlatform {
  static const _unsupportedMessage =
      'biometric_storage on web requires a secure-context browser with '
      'WebAuthn PRF support and a user-verifying platform authenticator. '
      'If the browser cannot prove that capability at runtime, web support is '
      'reported as unsupported instead of falling back to weaker storage.';

  static const _storageKeyPrefix = 'biometric_storage_web:';

  @visibleForTesting
  static WebAuthnRuntime defaultRuntime = BrowserWebAuthnRuntime();

  BiometricStorageWeb({WebAuthnRuntime? runtime})
      : _runtime = runtime ?? defaultRuntime;

  final WebAuthnRuntime _runtime;

  static void registerWith(Registrar registrar) {
    BiometricStoragePlatform.instance = BiometricStorageWeb();
  }

  Never _unsupported() => throw UnsupportedError(_unsupportedMessage);

  String _storageKey(String name) => '$_storageKeyPrefix$name';

  Future<_StoredCredentialRecord?> _loadRecord(String name) async {
    final raw = _runtime.readRecord(_storageKey(name));
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid web storage record format.');
    }

    return _StoredCredentialRecord.fromJson(decoded);
  }

  Future<void> _saveRecord(String name, _StoredCredentialRecord record) async {
    _runtime.writeRecord(_storageKey(name), jsonEncode(record.toJson()));
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    web.window.crypto.getRandomValues(bytes.toJS);
    return bytes;
  }

  Future<_StoredCredentialRecord> _ensureRecord(String name) async {
    final existing = await _loadRecord(name);
    if (existing != null) {
      return existing;
    }

    final prfSalt = _randomBytes(32);
    final credentialId = await _runtime.registerCredential(
      storageName: name,
      challenge: _randomBytes(32),
      userId: _randomBytes(32),
      prfSalt: prfSalt,
    );

    final record = _StoredCredentialRecord(
      version: 1,
      credentialIdBase64: _base64Encode(credentialId),
      prfSaltBase64: _base64Encode(prfSalt),
    );
    await _saveRecord(name, record);
    return record;
  }

  Future<Uint8List> _encrypt(Uint8List keyBytes, Uint8List plaintext) async {
    final key = await _importAesKey(keyBytes, const <String>['encrypt']);
    final iv = _randomBytes(12);
    final algorithm = _jsifyObject(<String, Object?>{
      'name': 'AES-GCM',
      'iv': iv,
    });
    final encryptedBuffer = await (web.window.crypto.subtle as JSObject)
        .callMethodVarArgs<JSPromise<JSArrayBuffer>>(
      'encrypt'.toJS,
      <JSAny?>[algorithm, key, plaintext.toJS],
    ).toDart;
    final encryptedBytes = Uint8List.fromList(
      Uint8List.view(encryptedBuffer.toDart),
    );
    return Uint8List.fromList(<int>[...iv, ...encryptedBytes]);
  }

  Future<Uint8List> _decrypt(Uint8List keyBytes, Uint8List ciphertext) async {
    if (ciphertext.length < 13) {
      throw const FormatException('Encrypted payload is truncated.');
    }

    final key = await _importAesKey(keyBytes, const <String>['decrypt']);
    final iv = Uint8List.sublistView(ciphertext, 0, 12);
    final encryptedBytes = Uint8List.sublistView(ciphertext, 12);
    final algorithm = _jsifyObject(<String, Object?>{
      'name': 'AES-GCM',
      'iv': iv,
    });

    try {
      final decryptedBuffer = await (web.window.crypto.subtle as JSObject)
          .callMethodVarArgs<JSPromise<JSArrayBuffer>>(
        'decrypt'.toJS,
        <JSAny?>[algorithm, key, encryptedBytes.toJS],
      ).toDart;
      return Uint8List.fromList(Uint8List.view(decryptedBuffer.toDart));
    } catch (error) {
      throw BiometricStorageException(
        'Unable to decrypt stored web secret. The credential may have changed or the stored payload is invalid. ${_describeError(error)}',
      );
    }
  }

  Future<JSObject> _importAesKey(Uint8List keyBytes, List<String> usages) {
    final algorithm = _jsifyObject(<String, Object?>{
      'name': 'AES-GCM',
    });
    return (web.window.crypto.subtle as JSObject)
        .callMethodVarArgs<JSPromise<JSObject>>(
      'importKey'.toJS,
      <JSAny?>[
        'raw'.toJS,
        keyBytes.toJS,
        algorithm,
        false.toJS,
        _jsifyArray(usages),
      ],
    ).toDart;
  }

  String _base64Encode(Uint8List value) => base64UrlEncode(value);

  Uint8List _base64Decode(String value) =>
      Uint8List.fromList(base64Url.decode(value));

  Never _mapAuthError(Object error) {
    final name = _jsStringProperty(error, 'name');
    final message = _describeError(error);

    switch (name) {
      case 'NotAllowedError':
        throw AuthException(AuthExceptionCode.userCanceled, message);
      case 'AbortError':
      case 'InvalidStateError':
        throw AuthException(AuthExceptionCode.canceled, message);
      case 'SecurityError':
      case 'NotSupportedError':
        _unsupported();
      default:
        throw BiometricStorageException(message);
    }
  }

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async {
    final support = await _runtime.probeSupport();
    if (!support.isStorageSupported) {
      return CanAuthenticateResponse.unsupported;
    }
    if (!support.hasPlatformAuthenticator) {
      return CanAuthenticateResponse.errorNoHardware;
    }
    return CanAuthenticateResponse.success;
  }

  @override
  Future<PasskeyAvailability> getPasskeyAvailability() async {
    final support = await _runtime.probeSupport();
    return PasskeyAvailability(
      isSupported: support.isPasskeySupported,
      isAvailable:
          support.isPasskeySupported && support.hasPlatformAuthenticator,
      hasPlatformAuthenticator: support.hasPlatformAuthenticator,
      hasConditionalUi: support.hasConditionalUi,
      hasDiscoverableCredentials: support.hasConditionalUi,
      supportsPrfStorage: support.supportsPrf,
      isPrfStorageAvailable:
          support.supportsPrf && support.hasPlatformAuthenticator,
      metadata: <String, dynamic>{
        'isSecureContext': support.isSecureContext,
        'hasCredentialsApi': support.hasCredentialsApi,
        'hasPublicKeyCredential': support.hasPublicKeyCredential,
        'supportsPrf': support.supportsPrf,
      },
    );
  }

  @override
  Future<PublicKeyCredentialAttestationJson> registerPasskey(
    PublicKeyCredentialCreationOptionsJson options,
  ) async {
    final availability = await getPasskeyAvailability();
    if (!availability.isSupported) {
      _unsupported();
    }

    try {
      return await _runtime.registerPasskey(options);
    } catch (error) {
      if (error is AuthException ||
          error is UnsupportedError ||
          error is BiometricStorageException) {
        rethrow;
      }
      _mapAuthError(error);
    }
  }

  @override
  Future<PublicKeyCredentialAssertionJson> authenticateWithPasskey(
    PublicKeyCredentialRequestOptionsJson options,
  ) async {
    final availability = await getPasskeyAvailability();
    if (!availability.isSupported) {
      _unsupported();
    }

    try {
      return await _runtime.authenticateWithPasskey(options);
    } catch (error) {
      if (error is AuthException ||
          error is UnsupportedError ||
          error is BiometricStorageException) {
        rethrow;
      }
      _mapAuthError(error);
    }
  }

  @override
  Future<bool?> init(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
  }) async {
    if (!await isSupported(options: options)) {
      return false;
    }

    if (forceInit) {
      _runtime.deleteRecord(_storageKey(name));
    }

    return true;
  }

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<String?> read(
    String name,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) async {
    final record = await _loadRecord(name);
    if (record == null || record.ciphertextBase64 == null) {
      return null;
    }

    if (!await isSupported()) {
      _unsupported();
    }

    try {
      final keyBytes = await _runtime.derivePrfSecret(
        credentialId: _base64Decode(record.credentialIdBase64),
        prfSalt: _base64Decode(record.prfSaltBase64),
        forceBiometricAuthentication: forceBiometricAuthentication,
      );
      final plaintext = await _decrypt(
        keyBytes,
        _base64Decode(record.ciphertextBase64!),
      );
      return utf8.decode(plaintext);
    } catch (error) {
      if (error is AuthException ||
          error is UnsupportedError ||
          error is BiometricStorageException) {
        rethrow;
      }
      _mapAuthError(error);
    }
  }

  @override
  Future<bool> exists(
    String name,
    PromptInfo promptInfo,
  ) async {
    final record = await _loadRecord(name);
    return record?.ciphertextBase64 != null;
  }

  @override
  Future<bool?> delete(
    String name,
    PromptInfo promptInfo,
  ) async {
    final existing = _runtime.readRecord(_storageKey(name));
    _runtime.deleteRecord(_storageKey(name));
    return existing != null;
  }

  @override
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) async {
    if (!await isSupported()) {
      _unsupported();
    }

    final record = await _ensureRecord(name);

    try {
      final keyBytes = await _runtime.derivePrfSecret(
        credentialId: _base64Decode(record.credentialIdBase64),
        prfSalt: _base64Decode(record.prfSaltBase64),
        forceBiometricAuthentication: forceBiometricAuthentication,
      );
      final encrypted =
          await _encrypt(keyBytes, Uint8List.fromList(utf8.encode(content)));
      await _saveRecord(
        name,
        record.copyWith(
          ciphertextBase64: _base64Encode(encrypted),
        ),
      );
    } catch (error) {
      if (error is AuthException ||
          error is UnsupportedError ||
          error is BiometricStorageException) {
        rethrow;
      }
      _mapAuthError(error);
    }
  }

  @override
  Future<void> dispose(
    String name,
    PromptInfo promptInfo,
  ) async {}
}

@visibleForTesting
abstract class WebAuthnRuntime {
  Future<WebAuthnSupport> probeSupport();

  String? readRecord(String key);

  void writeRecord(String key, String value);

  void deleteRecord(String key);

  Future<Uint8List> registerCredential({
    required String storageName,
    required Uint8List challenge,
    required Uint8List userId,
    required Uint8List prfSalt,
  });

  Future<PublicKeyCredentialAttestationJson> registerPasskey(
    PublicKeyCredentialCreationOptionsJson options,
  );

  Future<PublicKeyCredentialAssertionJson> authenticateWithPasskey(
    PublicKeyCredentialRequestOptionsJson options,
  );

  Future<Uint8List> derivePrfSecret({
    required Uint8List credentialId,
    required Uint8List prfSalt,
    required bool forceBiometricAuthentication,
  });
}

@visibleForTesting
class WebAuthnSupport {
  const WebAuthnSupport({
    required this.isSecureContext,
    required this.hasCredentialsApi,
    required this.hasPublicKeyCredential,
    required this.supportsPrf,
    required this.hasPlatformAuthenticator,
    this.hasConditionalUi = false,
  });

  final bool isSecureContext;
  final bool hasCredentialsApi;
  final bool hasPublicKeyCredential;
  final bool supportsPrf;
  final bool hasPlatformAuthenticator;
  final bool hasConditionalUi;

  bool get isPasskeySupported =>
      isSecureContext && hasCredentialsApi && hasPublicKeyCredential;

  bool get isStorageSupported => isPasskeySupported && supportsPrf;
}

class BrowserWebAuthnRuntime implements WebAuthnRuntime {
  static const _timeoutMs = 60 * 1000;

  Object? get _publicKeyCredentialConstructor {
    final windowObject = web.window as JSObject;
    if (!windowObject.has('PublicKeyCredential')) {
      return null;
    }
    return windowObject['PublicKeyCredential'];
  }

  @override
  Future<WebAuthnSupport> probeSupport() async {
    final publicKeyCredential = _publicKeyCredentialConstructor as JSObject?;
    final hasCredentialsApi =
        (web.window.navigator as JSObject).has('credentials');
    final isSecureContext = web.window.isSecureContext;
    final hasPublicKeyCredential = publicKeyCredential != null;

    if (!isSecureContext || !hasCredentialsApi || !hasPublicKeyCredential) {
      return WebAuthnSupport(
        isSecureContext: isSecureContext,
        hasCredentialsApi: hasCredentialsApi,
        hasPublicKeyCredential: hasPublicKeyCredential,
        supportsPrf: false,
        hasPlatformAuthenticator: false,
        hasConditionalUi: false,
      );
    }

    var hasPlatformAuthenticator = false;
    try {
      hasPlatformAuthenticator = await publicKeyCredential
          .callMethodVarArgs<JSPromise<JSBoolean>>(
            'isUserVerifyingPlatformAuthenticatorAvailable'.toJS,
            const <JSAny?>[],
          )
          .toDart
          .then((value) => value.toDart);
    } catch (_) {
      hasPlatformAuthenticator = false;
    }

    var supportsPrf = false;
    var hasConditionalUi = false;
    if (publicKeyCredential.has('getClientCapabilities')) {
      try {
        final capabilities =
            await publicKeyCredential.callMethodVarArgs<JSPromise<JSObject>>(
          'getClientCapabilities'.toJS,
          const <JSAny?>[],
        ).toDart;
        supportsPrf = _jsBoolProperty(capabilities, 'extension:prf') ??
            _jsBoolProperty(capabilities, 'prf') ??
            false;
        hasConditionalUi = _jsBoolProperty(capabilities, 'conditionalGet') ??
            _jsBoolProperty(capabilities, 'conditionalMediation') ??
            false;
      } catch (_) {
        supportsPrf = false;
        hasConditionalUi = false;
      }
    }

    return WebAuthnSupport(
      isSecureContext: isSecureContext,
      hasCredentialsApi: hasCredentialsApi,
      hasPublicKeyCredential: true,
      supportsPrf: supportsPrf,
      hasPlatformAuthenticator: hasPlatformAuthenticator,
      hasConditionalUi: hasConditionalUi,
    );
  }

  @override
  String? readRecord(String key) => web.window.localStorage.getItem(key);

  @override
  void writeRecord(String key, String value) {
    web.window.localStorage.setItem(key, value);
  }

  @override
  void deleteRecord(String key) {
    web.window.localStorage.removeItem(key);
  }

  @override
  Future<Uint8List> registerCredential({
    required String storageName,
    required Uint8List challenge,
    required Uint8List userId,
    required Uint8List prfSalt,
  }) async {
    final navigator = web.window.navigator as JSObject;
    final publicKey = JSObject()
      ..['challenge'] = challenge.toJS
      ..['timeout'] = _timeoutMs.toJS
      ..['attestation'] = 'none'.toJS
      ..['rp'] = _jsifyObject(<String, Object?>{
        'id': web.window.location.hostname,
        'name': web.window.location.hostname,
      })
      ..['user'] = _jsifyObject(<String, Object?>{
        'id': userId,
        'name':
            'biometric_storage:$storageName@${web.window.location.hostname}',
        'displayName': 'biometric_storage:$storageName',
      })
      ..['pubKeyCredParams'] = _jsifyArray(<Object?>[
        <String, Object>{'type': 'public-key', 'alg': -7},
        <String, Object>{'type': 'public-key', 'alg': -257},
      ])
      ..['authenticatorSelection'] = _jsifyObject(<String, Object?>{
        'authenticatorAttachment': 'platform',
        'residentKey': 'discouraged',
        'requireResidentKey': false,
        'userVerification': 'required',
      })
      ..['extensions'] = _buildPrfExtensions(prfSalt);

    final options = JSObject()..['publicKey'] = publicKey;

    final credential = await (navigator['credentials']! as JSObject)
        .callMethodVarArgs<JSPromise<JSAny?>>(
      'create'.toJS,
      <JSAny?>[options],
    ).toDart;
    if (credential == null) {
      throw BiometricStorageException(
        'Browser did not return a WebAuthn credential during setup.',
      );
    }

    final credentialObject = credential as JSObject;
    final extensionResults = credentialObject.callMethodVarArgs<JSObject>(
      'getClientExtensionResults'.toJS,
      const <JSAny?>[],
    );
    final prfResult = _jsObjectProperty(extensionResults, 'prf');
    final enabled =
        prfResult == null ? null : _jsBoolProperty(prfResult, 'enabled');
    if (enabled != true) {
      throw UnsupportedError(BiometricStorageWeb._unsupportedMessage);
    }

    return _arrayBufferToBytes(credentialObject['rawId']!);
  }

  @override
  Future<PublicKeyCredentialAttestationJson> registerPasskey(
    PublicKeyCredentialCreationOptionsJson options,
  ) async {
    final navigator = web.window.navigator as JSObject;
    final publicKey = _publicKeyCreationOptionsToJs(options);
    final credential = await (navigator['credentials']! as JSObject)
        .callMethodVarArgs<JSPromise<JSAny?>>(
      'create'.toJS,
      <JSAny?>[JSObject()..['publicKey'] = publicKey],
    ).toDart;
    if (credential == null) {
      throw BiometricStorageException(
        'Browser did not return a WebAuthn credential during passkey registration.',
      );
    }

    return _attestationFromCredential(credential as JSObject);
  }

  @override
  Future<PublicKeyCredentialAssertionJson> authenticateWithPasskey(
    PublicKeyCredentialRequestOptionsJson options,
  ) async {
    final navigator = web.window.navigator as JSObject;
    final publicKey = _publicKeyRequestOptionsToJs(options);
    final credential = await (navigator['credentials']! as JSObject)
        .callMethodVarArgs<JSPromise<JSAny?>>(
      'get'.toJS,
      <JSAny?>[JSObject()..['publicKey'] = publicKey],
    ).toDart;
    if (credential == null) {
      throw AuthException(
        AuthExceptionCode.canceled,
        'Browser did not return a WebAuthn assertion.',
      );
    }

    return _assertionFromCredential(credential as JSObject);
  }

  @override
  Future<Uint8List> derivePrfSecret({
    required Uint8List credentialId,
    required Uint8List prfSalt,
    required bool forceBiometricAuthentication,
  }) async {
    final navigator = web.window.navigator as JSObject;
    final publicKey = JSObject()
      ..['challenge'] = _randomChallenge().toJS
      ..['timeout'] = _timeoutMs.toJS
      ..['userVerification'] = 'required'.toJS
      ..['allowCredentials'] = _jsifyArray(<Object?>[
        <String, Object>{
          'id': credentialId,
          'type': 'public-key',
        },
      ])
      ..['extensions'] = _buildPrfExtensions(prfSalt);

    final options = JSObject()..['publicKey'] = publicKey;

    final credential = await (navigator['credentials']! as JSObject)
        .callMethodVarArgs<JSPromise<JSAny?>>(
      'get'.toJS,
      <JSAny?>[options],
    ).toDart;
    if (credential == null) {
      throw AuthException(
        AuthExceptionCode.canceled,
        'Browser did not return a WebAuthn assertion.',
      );
    }

    final credentialObject = credential as JSObject;
    final extensionResults = credentialObject.callMethodVarArgs<JSObject>(
      'getClientExtensionResults'.toJS,
      const <JSAny?>[],
    );
    final prfResult = _jsObjectProperty(extensionResults, 'prf');
    final results =
        prfResult == null ? null : _jsObjectProperty(prfResult, 'results');
    final first = results == null ? null : _jsObjectProperty(results, 'first');
    if (first == null) {
      throw UnsupportedError(BiometricStorageWeb._unsupportedMessage);
    }

    return _arrayBufferToBytes(first);
  }

  JSObject _buildPrfExtensions(Uint8List prfSalt) =>
      _jsifyObject(<String, Object?>{
        'prf': <String, Object>{
          'eval': <String, Object>{
            'first': prfSalt,
          },
        },
      });

  Uint8List _randomChallenge() {
    final bytes = Uint8List(32);
    web.window.crypto.getRandomValues(bytes.toJS);
    return bytes;
  }

  JSObject _publicKeyCreationOptionsToJs(
    PublicKeyCredentialCreationOptionsJson options,
  ) {
    final json = Map<String, dynamic>.from(options.toJson());
    json['challenge'] = _decodeBase64UrlString(options.challenge);
    final user = Map<String, dynamic>.from(options.user.toJson());
    user['id'] = _decodeBase64UrlString(options.user.id);
    json['user'] = user;
    if (options.excludeCredentials != null) {
      json['excludeCredentials'] = options.excludeCredentials!
          .map(
            (credential) => <String, dynamic>{
              ...credential.toJson(),
              'id': _decodeBase64UrlString(credential.id),
            },
          )
          .toList(growable: false);
    }
    if (options.extensions != null) {
      json['extensions'] = _convertExtensionInputs(options.extensions!);
    }
    return _jsifyObject(Map<String, Object?>.from(json));
  }

  JSObject _publicKeyRequestOptionsToJs(
    PublicKeyCredentialRequestOptionsJson options,
  ) {
    final json = Map<String, dynamic>.from(options.toJson());
    json['challenge'] = _decodeBase64UrlString(options.challenge);
    if (options.allowCredentials != null) {
      json['allowCredentials'] = options.allowCredentials!
          .map(
            (credential) => <String, dynamic>{
              ...credential.toJson(),
              'id': _decodeBase64UrlString(credential.id),
            },
          )
          .toList(growable: false);
    }
    if (options.extensions != null) {
      json['extensions'] = _convertExtensionInputs(options.extensions!);
    }
    return _jsifyObject(Map<String, Object?>.from(json));
  }

  Map<String, dynamic> _convertExtensionInputs(
      Map<String, dynamic> extensions) {
    return _convertInputValue(extensions) as Map<String, dynamic>;
  }

  Object? _convertInputValue(Object? value, {String? key}) {
    if (value is Map) {
      return value.map<String, Object?>(
        (dynamic mapKey, dynamic mapValue) => MapEntry<String, Object?>(
          mapKey as String,
          _convertInputValue(mapValue, key: mapKey),
        ),
      );
    }
    if (value is List) {
      return value
          .map((Object? item) => _convertInputValue(item, key: key))
          .toList(growable: false);
    }
    if (value is String && _extensionBinaryKeys.contains(key)) {
      return _decodeBase64UrlString(value);
    }
    return value;
  }

  PublicKeyCredentialAttestationJson _attestationFromCredential(
    JSObject credential,
  ) {
    final response = _jsObjectProperty(credential, 'response') as JSObject?;
    if (response == null) {
      throw BiometricStorageException(
        'Browser returned a WebAuthn credential without an attestation response.',
      );
    }

    final clientExtensionResults = _clientExtensionResultsFrom(credential);
    final transports = response.has('getTransports')
        ? _stringListFromDart(
            response.callMethodVarArgs<JSAny?>(
              'getTransports'.toJS,
              const <JSAny?>[],
            ).dartify(),
          )
        : null;
    final publicKey = response.has('getPublicKey')
        ? _tryBase64UrlEncode(
            response.callMethodVarArgs<JSAny?>(
              'getPublicKey'.toJS,
              const <JSAny?>[],
            ),
          )
        : null;
    final authenticatorData = response.has('getAuthenticatorData')
        ? _tryBase64UrlEncode(
            response.callMethodVarArgs<JSAny?>(
              'getAuthenticatorData'.toJS,
              const <JSAny?>[],
            ),
          )
        : null;
    final publicKeyAlgorithm = response.has('getPublicKeyAlgorithm')
        ? (response.callMethodVarArgs<JSAny?>(
            'getPublicKeyAlgorithm'.toJS,
            const <JSAny?>[],
          ).dartify() as num?)
            ?.toInt()
        : null;

    final rawId = _base64Encode(_arrayBufferToBytes(credential['rawId']!));
    return PublicKeyCredentialAttestationJson(
      id: _jsStringProperty(credential, 'id') ?? rawId,
      rawId: rawId,
      type: _jsStringProperty(credential, 'type') ?? 'public-key',
      authenticatorAttachment:
          _jsStringProperty(credential, 'authenticatorAttachment'),
      response: AuthenticatorAttestationResponseJson(
        clientDataJSON: _tryBase64UrlEncode(response['clientDataJSON'])!,
        attestationObject: _tryBase64UrlEncode(response['attestationObject'])!,
        transports: transports,
        publicKeyAlgorithm: publicKeyAlgorithm,
        publicKey: publicKey,
        authenticatorData: authenticatorData,
      ),
      clientExtensionResults: clientExtensionResults,
    );
  }

  PublicKeyCredentialAssertionJson _assertionFromCredential(
      JSObject credential) {
    final response = _jsObjectProperty(credential, 'response') as JSObject?;
    if (response == null) {
      throw BiometricStorageException(
        'Browser returned a WebAuthn credential without an assertion response.',
      );
    }

    final rawId = _base64Encode(_arrayBufferToBytes(credential['rawId']!));
    return PublicKeyCredentialAssertionJson(
      id: _jsStringProperty(credential, 'id') ?? rawId,
      rawId: rawId,
      type: _jsStringProperty(credential, 'type') ?? 'public-key',
      authenticatorAttachment:
          _jsStringProperty(credential, 'authenticatorAttachment'),
      response: AuthenticatorAssertionResponseJson(
        clientDataJSON: _tryBase64UrlEncode(response['clientDataJSON'])!,
        authenticatorData: _tryBase64UrlEncode(response['authenticatorData'])!,
        signature: _tryBase64UrlEncode(response['signature'])!,
        userHandle: _tryBase64UrlEncode(response['userHandle']),
      ),
      clientExtensionResults: _clientExtensionResultsFrom(credential),
    );
  }

  Map<String, dynamic>? _clientExtensionResultsFrom(JSObject credential) {
    final extensionResults = credential.callMethodVarArgs<JSAny?>(
      'getClientExtensionResults'.toJS,
      const <JSAny?>[],
    );
    final normalized = _normalizeJsonCompatibleValue(extensionResults);
    return normalized is Map<String, dynamic> ? normalized : null;
  }
}

const Set<String> _extensionBinaryKeys = <String>{
  'first',
  'second',
};

class _StoredCredentialRecord {
  const _StoredCredentialRecord({
    required this.version,
    required this.credentialIdBase64,
    required this.prfSaltBase64,
    this.ciphertextBase64,
  });

  factory _StoredCredentialRecord.fromJson(Map<String, dynamic> json) {
    return _StoredCredentialRecord(
      version: json['version'] as int? ?? 1,
      credentialIdBase64: json['credentialIdBase64'] as String,
      prfSaltBase64: json['prfSaltBase64'] as String,
      ciphertextBase64: json['ciphertextBase64'] as String?,
    );
  }

  final int version;
  final String credentialIdBase64;
  final String prfSaltBase64;
  final String? ciphertextBase64;

  _StoredCredentialRecord copyWith({
    String? ciphertextBase64,
  }) {
    return _StoredCredentialRecord(
      version: version,
      credentialIdBase64: credentialIdBase64,
      prfSaltBase64: prfSaltBase64,
      ciphertextBase64: ciphertextBase64,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'credentialIdBase64': credentialIdBase64,
        'prfSaltBase64': prfSaltBase64,
        'ciphertextBase64': ciphertextBase64,
      };
}

String _describeError(Object error) {
  final message = _jsStringProperty(error, 'message');
  final name = _jsStringProperty(error, 'name');
  if (message != null && message.isNotEmpty) {
    return name == null || name.isEmpty ? message : '$name: $message';
  }
  return error.toString();
}

String? _jsStringProperty(Object object, String property) {
  final jsObject = _asJSObject(object);
  if (jsObject == null || !jsObject.has(property)) {
    return null;
  }
  final value = jsObject[property];
  return value?.dartify()?.toString();
}

bool? _jsBoolProperty(Object object, String property) {
  final jsObject = _asJSObject(object);
  if (jsObject == null || !jsObject.has(property)) {
    return null;
  }
  final value = jsObject[property];
  return value?.dartify() as bool?;
}

String? _tryBase64UrlEncode(Object? value) {
  if (value == null) {
    return null;
  }
  try {
    return _base64Encode(_arrayBufferToBytes(value));
  } catch (_) {
    return null;
  }
}

Object? _jsObjectProperty(Object object, String property) {
  final jsObject = _asJSObject(object);
  if (jsObject == null || !jsObject.has(property)) {
    return null;
  }
  return jsObject[property];
}

Uint8List _arrayBufferToBytes(Object bufferOrView) {
  final jsValue = bufferOrView as JSAny?;
  if (jsValue.instanceOfString('ArrayBuffer')) {
    final buffer = jsValue as JSArrayBuffer;
    return Uint8List.fromList(Uint8List.view(buffer.toDart));
  }

  final view = bufferOrView as JSObject;
  final buffer = view['buffer'];
  if (buffer != null && buffer.instanceOfString('ArrayBuffer')) {
    final byteOffset = (view['byteOffset']!.dartify() as num).toInt();
    final byteLength = (view['byteLength']!.dartify() as num).toInt();
    return Uint8List.fromList(
      Uint8List.view((buffer as JSArrayBuffer).toDart, byteOffset, byteLength),
    );
  }

  throw BiometricStorageException('Expected JavaScript ArrayBuffer value.');
}

JSObject _jsifyObject(Map<String, Object?> values) {
  final object = JSObject();
  for (final entry in values.entries) {
    object[entry.key] = _dartToJS(entry.value);
  }
  return object;
}

JSArray<JSAny?> _jsifyArray(List<Object?> values) =>
    values.map(_dartToJS).toList().toJS;

JSAny? _dartToJS(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value.toJS;
  }
  if (value is bool) {
    return value.toJS;
  }
  if (value is int) {
    return value.toJS;
  }
  if (value is double) {
    return value.toJS;
  }
  if (value is Uint8List) {
    return value.toJS;
  }
  if (value is List) {
    return _jsifyArray(value.cast<Object?>());
  }
  if (value is Map) {
    return _jsifyObject(
      value.map<String, Object?>(
        (dynamic key, dynamic mapValue) =>
            MapEntry<String, Object?>(key as String, mapValue as Object?),
      ),
    );
  }

  throw UnsupportedError('Cannot convert ${value.runtimeType} to a JS value.');
}

JSObject? _asJSObject(Object object) {
  try {
    return object as JSObject;
  } catch (_) {
    return null;
  }
}

JSAny? _asJSAny(Object? object) {
  try {
    return object as JSAny;
  } catch (_) {
    return null;
  }
}

String _base64Encode(Uint8List value) =>
    base64UrlEncode(value).replaceAll('=', '');

Uint8List _decodeBase64UrlString(String value) {
  final normalized = value.padRight(
    value.length + ((4 - (value.length % 4)) % 4),
    '=',
  );
  return Uint8List.fromList(base64Url.decode(normalized));
}

Object? _normalizeJsonCompatibleValue(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  final jsValue = _asJSAny(value);
  if (jsValue != null) {
    final bytes = _tryBase64UrlEncode(jsValue);
    if (bytes != null) {
      return bytes;
    }
    return _normalizeJsonCompatibleValue(jsValue.dartify());
  }
  if (value is ByteBuffer) {
    return _base64Encode(Uint8List.view(value));
  }
  if (value is ByteData) {
    return _base64Encode(
      value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes),
    );
  }
  if (value is Uint8List) {
    return _base64Encode(value);
  }
  if (value is List) {
    return value
        .map<Object?>((Object? item) => _normalizeJsonCompatibleValue(item))
        .toList(growable: false);
  }
  if (value is Map) {
    return value.map<String, dynamic>(
      (dynamic key, dynamic mapValue) => MapEntry<String, dynamic>(
        key as String,
        _normalizeJsonCompatibleValue(mapValue),
      ),
    );
  }
  return value.toString();
}

List<String>? _stringListFromDart(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is List) {
    return value.map((Object? item) => item.toString()).toList(growable: false);
  }
  return null;
}
