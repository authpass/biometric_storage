// ignore_for_file: deprecated_member_use

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RecordingBiometricStoragePlatform platform;

  setUp(() {
    platform = RecordingBiometricStoragePlatform();
    BiometricStoragePlatform.instance = platform;
  });

  group('StorageFileInitOptions', () {
    test('serializes configured durations and flags', () {
      final options = StorageFileInitOptions(
        androidAuthenticationValidityDuration: const Duration(seconds: 11),
        darwinTouchIDAuthenticationAllowableReuseDuration: const Duration(
          seconds: 22,
        ),
        darwinTouchIDAuthenticationForceReuseContextDuration: const Duration(
          seconds: 33,
        ),
        authenticationRequired: false,
        androidUseStrongBox: false,
        androidBiometricOnly: false,
        darwinBiometricOnly: false,
      );

      expect(options.toJson(), <String, dynamic>{
        'androidAuthenticationValidityDurationSeconds': 11,
        'darwinTouchIDAuthenticationAllowableReuseDurationSeconds': 22,
        'darwinTouchIDAuthenticationForceReuseContextDurationSeconds': 33,
        'authenticationRequired': false,
        'androidUseStrongBox': false,
        'androidBiometricOnly': false,
        'darwinBiometricOnly': false,
      });
    });

    test('supports deprecated authentication validity seconds fallback', () {
      final options = StorageFileInitOptions(
        authenticationValidityDurationSeconds: 7,
      );

      expect(options.toJson(), <String, dynamic>{
        'androidAuthenticationValidityDurationSeconds': 7,
        'darwinTouchIDAuthenticationAllowableReuseDurationSeconds': 7,
        'darwinTouchIDAuthenticationForceReuseContextDurationSeconds': null,
        'authenticationRequired': true,
        'androidUseStrongBox': true,
        'androidBiometricOnly': true,
        'darwinBiometricOnly': true,
      });
    });
  });

  test('delegates canAuthenticate and app armor checks', () async {
    platform.canAuthenticateResponse = CanAuthenticateResponse.success;
    platform.linuxCheckAppArmorErrorResponse = true;

    expect(
      await BiometricStorage().canAuthenticate(),
      CanAuthenticateResponse.success,
    );
    expect(await BiometricStorage().linuxCheckAppArmorError(), isTrue);
  });

  test('exposes support helpers for login fallback flows', () async {
    platform.canAuthenticateResponse = CanAuthenticateResponse.success;
    platform.passkeyAvailabilityResponse = const PasskeyAvailability(
      isSupported: true,
      isAvailable: true,
      hasPlatformAuthenticator: true,
      hasDiscoverableCredentials: true,
      supportsPrfStorage: true,
      isPrfStorageAvailable: true,
    );

    expect(await BiometricStorage().isSupported(), isTrue);
    expect(await BiometricStorage().canAuthenticateWithBiometrics(), isTrue);
    expect(await BiometricStorage().isPasskeySupported(), isTrue);
    expect(await BiometricStorage().isPasskeyAvailable(), isTrue);

    final capabilities = await BiometricStorage().getCapabilities();
    expect(capabilities.passkeys.isAvailable, isTrue);
    expect(capabilities.isBiometricStorageSupported, isTrue);
    expect(capabilities.isBiometricStorageAvailable, isTrue);
    expect(capabilities.prefersPasskeys, isTrue);
    expect(capabilities.supportedCapabilities.toSet(), <SecureAccessCapability>{
      SecureAccessCapability.biometricStorage,
      SecureAccessCapability.passkeyAuthentication,
      SecureAccessCapability.passkeyPrfStorage,
    });
    expect(capabilities.availableCapabilities.toSet(), <SecureAccessCapability>{
      SecureAccessCapability.biometricStorage,
      SecureAccessCapability.passkeyAuthentication,
      SecureAccessCapability.passkeyPrfStorage,
    });
    expect(
      await BiometricStorage().isCapabilitySupported(
        SecureAccessCapability.passkeyPrfStorage,
      ),
      isTrue,
    );
    expect(
      await BiometricStorage().isCapabilityAvailable(
        SecureAccessCapability.passkeyPrfStorage,
      ),
      isTrue,
    );

    platform.canAuthenticateResponse =
        CanAuthenticateResponse.errorNoBiometricEnrolled;
    platform.passkeyAvailabilityResponse = const PasskeyAvailability(
      isSupported: true,
      isAvailable: false,
      hasPlatformAuthenticator: true,
      hasPendingRegistrationOpportunity: true,
      supportsPrfStorage: true,
      isPrfStorageAvailable: false,
    );

    expect(await BiometricStorage().isSupported(), isTrue);
    expect(await BiometricStorage().canAuthenticateWithBiometrics(), isFalse);
    expect(await BiometricStorage().isPasskeySupported(), isTrue);
    expect(await BiometricStorage().isPasskeyAvailable(), isFalse);
    expect(
      platform.canAuthenticateResponse.shouldFallbackToRegularLogin,
      isTrue,
    );

    final limitedCapabilities = await BiometricStorage().getCapabilities();
    expect(
      limitedCapabilities.supportedCapabilities.toSet(),
      <SecureAccessCapability>{
        SecureAccessCapability.biometricStorage,
        SecureAccessCapability.passkeyAuthentication,
        SecureAccessCapability.passkeyPrfStorage,
      },
    );
    expect(limitedCapabilities.availableCapabilities.toSet(), isEmpty);

    platform.canAuthenticateResponse = CanAuthenticateResponse.unsupported;
    platform.passkeyAvailabilityResponse =
        const PasskeyAvailability.unsupported();

    expect(await BiometricStorage().isSupported(), isFalse);
    expect(await BiometricStorage().canAuthenticateWithBiometrics(), isFalse);
    expect(await BiometricStorage().isPasskeySupported(), isFalse);
    expect(await BiometricStorage().isPasskeyAvailable(), isFalse);
    expect(
      (await BiometricStorage().getSupportedCapabilities()).toSet(),
      isEmpty,
    );
    expect(
      (await BiometricStorage().getAvailableCapabilities()).toSet(),
      isEmpty,
    );
  });

  test('serializes prompt info and exception helpers', () {
    const androidPromptInfo = AndroidPromptInfo(
      title: 'Auth title',
      subtitle: 'Auth subtitle',
      description: 'Auth description',
      negativeButton: 'Nope',
      confirmationRequired: false,
    );
    const iosPromptInfo = IosPromptInfo(
      saveTitle: 'Save me',
      accessTitle: 'Access me',
    );
    const promptInfo = PromptInfo(
      androidPromptInfo: androidPromptInfo,
      iosPromptInfo: iosPromptInfo,
      macOsPromptInfo: iosPromptInfo,
    );

    expect(androidPromptInfo.toJson(), <String, dynamic>{
      'title': 'Auth title',
      'subtitle': 'Auth subtitle',
      'description': 'Auth description',
      'negativeButton': 'Nope',
      'confirmationRequired': false,
    });
    expect(iosPromptInfo.toJson(), <String, dynamic>{
      'saveTitle': 'Save me',
      'accessTitle': 'Access me',
    });
    expect(promptInfo.androidPromptInfo.title, 'Auth title');
    expect(
      BiometricStorageException('nope').toString(),
      'BiometricStorageException{message: nope}',
    );
    expect(
      AuthException(AuthExceptionCode.timeout, 'timed out').toString(),
      'AuthException{code: AuthExceptionCode.timeout, message: timed out}',
    );
    expect(
      mapCanAuthenticateResponse('Success'),
      CanAuthenticateResponse.success,
    );
    expect(
      () => mapCanAuthenticateResponse('NoSuchValue'),
      throwsA(isA<StateError>()),
    );
  });

  test('capability bitmask wrapper supports combinable checks', () {
    final capabilities = SecureAccessCapabilitySet(
      SecureAccessCapability.biometricStorage.bit |
          SecureAccessCapability.passkeyPrfStorage.bit,
    );

    expect(
      capabilities.contains(SecureAccessCapability.biometricStorage),
      isTrue,
    );
    expect(
      capabilities.contains(SecureAccessCapability.passkeyAuthentication),
      isFalse,
    );
    expect(
      capabilities.contains(SecureAccessCapability.passkeyPrfStorage),
      isTrue,
    );
    expect(capabilities.toJson()['mask'], isNot(0));
  });

  test(
    'keeps standards-based WebAuthn DTOs roundtrippable for server loops',
    () {
      final creationOptions = PublicKeyCredentialCreationOptionsJson.fromJson(
        <String, dynamic>{
          'challenge': 'server-challenge',
          'rp': <String, dynamic>{
            'id': 'example.com',
            'name': 'Example',
            'tenantHint': 'nextjs',
          },
          'user': <String, dynamic>{
            'id': 'base64url-user-id',
            'name': 'person@example.com',
            'displayName': 'Person Example',
            'customUserFlag': true,
          },
          'pubKeyCredParams': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'public-key', 'alg': -7},
          ],
          'timeout': 60000,
          'extensions': <String, dynamic>{
            'credProps': true,
            'prf': <String, dynamic>{
              'eval': <String, dynamic>{'first': 'salt'},
            },
          },
          'serverFramework': 'aspnetcore',
        },
      );

      expect(creationOptions.rp.additionalData['tenantHint'], 'nextjs');
      expect(creationOptions.user.additionalData['customUserFlag'], isTrue);
      expect(creationOptions.additionalData['serverFramework'], 'aspnetcore');
      expect(creationOptions.toJson()['serverFramework'], 'aspnetcore');

      final assertion = PublicKeyCredentialAssertionJson.fromJson(
        <String, dynamic>{
          'id': 'credential-id',
          'rawId': 'credential-raw-id',
          'type': 'public-key',
          'response': <String, dynamic>{
            'clientDataJSON': 'client-data',
            'authenticatorData': 'auth-data',
            'signature': 'signature',
            'userHandle': 'handle',
            'ecosystem': 'web',
          },
          'clientExtensionResults': <String, dynamic>{
            'prf': <String, dynamic>{'enabled': true},
          },
          'roundTripToken': 'keep-me',
        },
      );

      expect(assertion.response.additionalData['ecosystem'], 'web');
      expect(assertion.additionalData['roundTripToken'], 'keep-me');
      expect(assertion.toJson()['roundTripToken'], 'keep-me');
    },
  );

  test(
    'round-trips extended passkey availability and secure capability sets',
    () {
      final availability = PasskeyAvailability.fromJson(<String, dynamic>{
        'isSupported': true,
        'isAvailable': true,
        'hasPlatformAuthenticator': true,
        'hasConditionalUi': true,
        'hasDiscoverableCredentials': true,
        'hasPendingRegistrationOpportunity': true,
        'supportsPrfStorage': true,
        'isPrfStorageAvailable': true,
        'metadata': <String, dynamic>{'platform': 'web'},
      });

      expect(availability.toJson(), <String, dynamic>{
        'isSupported': true,
        'isAvailable': true,
        'hasPlatformAuthenticator': true,
        'hasConditionalUi': true,
        'hasDiscoverableCredentials': true,
        'hasPendingRegistrationOpportunity': true,
        'supportsPrfStorage': true,
        'isPrfStorageAvailable': true,
        'metadata': <String, dynamic>{'platform': 'web'},
      });
      expect(
        const PasskeyAvailability.unsupported().toJson(),
        <String, dynamic>{
          'isSupported': false,
          'isAvailable': false,
          'hasPlatformAuthenticator': false,
          'hasConditionalUi': false,
          'hasDiscoverableCredentials': false,
          'hasPendingRegistrationOpportunity': false,
          'supportsPrfStorage': false,
          'isPrfStorageAvailable': false,
        },
      );

      final fromValues =
          SecureAccessCapabilitySet.fromValues(<SecureAccessCapability>[
            SecureAccessCapability.passkeyAuthentication,
            SecureAccessCapability.passkeyPrfStorage,
          ]);
      expect(
        fromValues.contains(SecureAccessCapability.biometricStorage),
        isFalse,
      );
      expect(const SecureAccessCapabilitySet.none().toJson(), <String, dynamic>{
        'mask': 0,
        'values': <String>[],
      });
    },
  );

  test('round-trips full WebAuthn DTO graphs including optional fields', () {
    const rp = PublicKeyCredentialRpEntityJson(
      id: 'example.com',
      name: 'Example',
      icon: 'https://example.com/icon.png',
      additionalData: <String, dynamic>{'tenant': 'primary'},
    );
    const user = PublicKeyCredentialUserEntityJson(
      id: 'base64-user-id',
      name: 'person@example.com',
      displayName: 'Person Example',
      icon: 'https://example.com/user.png',
      additionalData: <String, dynamic>{'department': 'engineering'},
    );
    const parameter = PublicKeyCredentialParametersJson(
      type: 'public-key',
      alg: -7,
      additionalData: <String, dynamic>{'algName': 'ES256'},
    );
    const descriptor = PublicKeyCredentialDescriptorJson(
      id: 'credential-id',
      type: 'public-key',
      transports: <String>['internal', 'hybrid'],
      additionalData: <String, dynamic>{'device': 'phone'},
    );
    const selection = AuthenticatorSelectionCriteriaJson(
      authenticatorAttachment: 'platform',
      residentKey: 'required',
      requireResidentKey: true,
      userVerification: 'required',
      additionalData: <String, dynamic>{'uvMode': 'strict'},
    );
    const attestationResponse = AuthenticatorAttestationResponseJson(
      clientDataJSON: 'client-data',
      attestationObject: 'attestation-object',
      transports: <String>['internal'],
      publicKeyAlgorithm: -7,
      publicKey: 'public-key-bytes',
      authenticatorData: 'authenticator-data',
      additionalData: <String, dynamic>{'fmt': 'packed'},
    );
    const assertionResponse = AuthenticatorAssertionResponseJson(
      clientDataJSON: 'assert-client-data',
      authenticatorData: 'assert-auth-data',
      signature: 'assert-signature',
      userHandle: 'assert-user-handle',
      additionalData: <String, dynamic>{'counter': 1},
    );

    final creationOptions = PublicKeyCredentialCreationOptionsJson.fromJson(
      <String, dynamic>{
        'challenge': 'challenge-b64',
        'rp': rp.toJson(),
        'user': user.toJson(),
        'pubKeyCredParams': <Map<String, dynamic>>[parameter.toJson()],
        'timeout': '60000',
        'excludeCredentials': <Map<String, dynamic>>[descriptor.toJson()],
        'authenticatorSelection': selection.toJson(),
        'attestation': 'direct',
        'attestationFormats': <String>['packed'],
        'extensions': <String, dynamic>{'credProps': true},
        'hints': <String>['security-key'],
        'extraRoot': 'keep',
      },
    );
    final requestOptions = PublicKeyCredentialRequestOptionsJson.fromJson(
      <String, dynamic>{
        'challenge': 'request-challenge-b64',
        'timeout': 30000.0,
        'rpId': 'example.com',
        'allowCredentials': <Map<String, dynamic>>[descriptor.toJson()],
        'userVerification': 'preferred',
        'extensions': <String, dynamic>{'appid': false},
        'hints': <String>['client-device'],
        'extraRequestRoot': 'keep-too',
      },
    );
    final attestation = PublicKeyCredentialAttestationJson.fromJson(
      <String, dynamic>{
        'id': 'attestation-id',
        'rawId': 'attestation-raw-id',
        'type': 'public-key',
        'authenticatorAttachment': 'platform',
        'response': attestationResponse.toJson(),
        'clientExtensionResults': <String, dynamic>{'credProps': true},
        'topLevelHint': 'attestation-extra',
      },
    );
    final assertion = PublicKeyCredentialAssertionJson.fromJson(
      <String, dynamic>{
        'id': 'assertion-id',
        'rawId': 'assertion-raw-id',
        'type': 'public-key',
        'authenticatorAttachment': 'cross-platform',
        'response': assertionResponse.toJson(),
        'clientExtensionResults': <String, dynamic>{'appid': false},
        'topLevelHint': 'assertion-extra',
      },
    );

    expect(creationOptions.toJson()['extraRoot'], 'keep');
    expect(requestOptions.toJson()['extraRequestRoot'], 'keep-too');
    expect(attestation.toJson()['topLevelHint'], 'attestation-extra');
    expect(assertion.toJson()['topLevelHint'], 'assertion-extra');
    expect(attestation.response.toJson()['fmt'], 'packed');
    expect(assertion.response.toJson()['counter'], 1);
    expect(creationOptions.excludeCredentials!.single.transports, <String>[
      'internal',
      'hybrid',
    ]);
    expect(
      requestOptions.allowCredentials!.single.additionalData['device'],
      'phone',
    );
  });

  test('validates required nested WebAuthn DTO objects', () {
    final nullableExtensions = PublicKeyCredentialAssertionJson.fromJson(
      <String, dynamic>{
        'id': 'assertion-id',
        'rawId': 'assertion-raw-id',
        'response': <String, dynamic>{
          'clientDataJSON': 'client-data',
          'authenticatorData': 'auth-data',
          'signature': 'signature',
        },
        'clientExtensionResults': null,
      },
    );
    expect(nullableExtensions.clientExtensionResults, isNull);

    expect(
      () => PublicKeyCredentialCreationOptionsJson.fromJson(<String, dynamic>{
        'challenge': 'challenge',
        'rp': 'not-an-object',
        'user': <String, dynamic>{
          'id': 'user-id',
          'name': 'person@example.com',
          'displayName': 'Person',
        },
        'pubKeyCredParams': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'public-key', 'alg': -7},
        ],
      }),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'forwards passkey server options and returns server-postable results',
    () async {
      const registrationResponse = PublicKeyCredentialAttestationJson(
        id: 'credential-id',
        rawId: 'raw-credential-id',
        response: AuthenticatorAttestationResponseJson(
          clientDataJSON: 'client-data-json',
          attestationObject: 'attestation-object',
        ),
      );
      const authenticationResponse = PublicKeyCredentialAssertionJson(
        id: 'credential-id',
        rawId: 'raw-credential-id',
        response: AuthenticatorAssertionResponseJson(
          clientDataJSON: 'client-data-json',
          authenticatorData: 'authenticator-data',
          signature: 'signature',
        ),
      );
      platform.registerPasskeyResponse = registrationResponse;
      platform.authenticateWithPasskeyResponse = authenticationResponse;

      final registrationOptions =
          PublicKeyCredentialCreationOptionsJson.fromJson(<String, dynamic>{
            'challenge': 'server-create-challenge',
            'rp': <String, dynamic>{'name': 'Example'},
            'user': <String, dynamic>{
              'id': 'user-id',
              'name': 'person@example.com',
              'displayName': 'Person',
            },
            'pubKeyCredParams': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'public-key', 'alg': -7},
            ],
          });
      final authenticationOptions =
          PublicKeyCredentialRequestOptionsJson.fromJson(<String, dynamic>{
            'challenge': 'server-get-challenge',
            'rpId': 'example.com',
          });

      final registered = await BiometricStorage().registerPasskey(
        registrationOptions,
      );
      final authenticated = await BiometricStorage().authenticateWithPasskey(
        authenticationOptions,
      );

      expect(
        platform.registerPasskeyCalls.single.toJson(),
        registrationOptions.toJson(),
      );
      expect(
        platform.authenticateWithPasskeyCalls.single.toJson(),
        authenticationOptions.toJson(),
      );
      expect(registered.toJson(), registrationResponse.toJson());
      expect(authenticated.toJson(), authenticationResponse.toJson());
    },
  );

  test(
    'returns null instead of throwing when storage is unsupported',
    () async {
      platform.canAuthenticateResponse = CanAuthenticateResponse.unsupported;

      final storage = await BiometricStorage().getStorageIfSupported('secret');

      expect(storage, isNull);
      expect(platform.initCalls, isEmpty);
    },
  );

  test('getStorageIfSupported initializes storage when supported', () async {
    platform.canAuthenticateResponse = CanAuthenticateResponse.success;

    final storage = await BiometricStorage().getStorageIfSupported('secret');

    expect(storage, isNotNull);
    expect(storage!.name, 'secret');
    expect(platform.initCalls.single.name, 'secret');
  });

  test('initializes storage and forwards read write delete calls', () async {
    const promptInfo = PromptInfo(
      macOsPromptInfo: IosPromptInfo(
        saveTitle: 'Save title',
        accessTitle: 'Access title',
      ),
    );
    final options = StorageFileInitOptions(
      authenticationRequired: false,
      androidBiometricOnly: false,
      darwinBiometricOnly: false,
    );
    platform.readResponse = 'stored value';

    final storage = await BiometricStorage().getStorage(
      'secret-name',
      options: options,
      forceInit: true,
      promptInfo: promptInfo,
    );

    expect(storage.name, 'secret-name');
    expect(await storage.exists(), isTrue);
    expect(await storage.read(), 'stored value');
    await storage.write('next value');
    await storage.delete();

    expect(platform.initCalls.single.name, 'secret-name');
    expect(platform.initCalls.single.options?.toJson(), options.toJson());
    expect(platform.initCalls.single.forceInit, isTrue);

    expect(platform.readCalls.single.name, 'secret-name');
    expect(platform.readCalls.single.forceBiometricAuthentication, isFalse);
    expect(
      platform.readCalls.single.promptInfo.macOsPromptInfo.saveTitle,
      'Save title',
    );

    expect(platform.existsCalls.single.name, 'secret-name');

    expect(platform.writeCalls.single.name, 'secret-name');
    expect(platform.writeCalls.single.content, 'next value');
    expect(platform.writeCalls.single.forceBiometricAuthentication, isFalse);

    expect(platform.deleteCalls.single.name, 'secret-name');
  });

  test('allows overriding prompt info per operation', () async {
    const defaultPromptInfo = PromptInfo(
      macOsPromptInfo: IosPromptInfo(
        saveTitle: 'Default save',
        accessTitle: 'Default access',
      ),
    );
    const overridePromptInfo = PromptInfo(
      macOsPromptInfo: IosPromptInfo(
        saveTitle: 'Override save',
        accessTitle: 'Override access',
      ),
    );

    final storage = await BiometricStorage().getStorage(
      'overridden-secret',
      promptInfo: defaultPromptInfo,
    );

    await storage.read(promptInfo: overridePromptInfo);
    await storage.write('content', promptInfo: overridePromptInfo);
    await storage.delete(promptInfo: overridePromptInfo);

    expect(
      platform.readCalls.single.promptInfo.macOsPromptInfo.saveTitle,
      'Override save',
    );
    expect(
      platform.writeCalls.single.promptInfo.macOsPromptInfo.saveTitle,
      'Override save',
    );
    expect(
      platform.deleteCalls.single.promptInfo.macOsPromptInfo.saveTitle,
      'Override save',
    );
  });

  test('deleteAndDispose forwards delete then dispose', () async {
    final storage = await BiometricStorage().getStorage('dispose-secret');

    await storage.deleteAndDispose();

    expect(platform.deleteCalls.single.name, 'dispose-secret');
    expect(platform.disposeCalls.single.name, 'dispose-secret');
  });

  test('maps changed biometrics auth errors to AuthException', () async {
    final errorPlatform = ErrorTransformingBiometricStoragePlatform();

    await expectLater(
      errorPlatform.transformErrors(
        Future<String?>.error(
          PlatformException(
            code: 'AuthError:BiometricsChanged',
            message: 'Biometric set changed',
          ),
        ),
      ),
      throwsA(
        isA<AuthException>()
            .having(
              (exception) => exception.code,
              'code',
              AuthExceptionCode.biometricsChanged,
            )
            .having(
              (exception) => exception.message,
              'message',
              'Biometric set changed',
            ),
      ),
    );
  });
}

class ErrorTransformingBiometricStoragePlatform
    extends MethodChannelBiometricStoragePlatform {
  @override
  Map<String, dynamic> buildPromptInfoArguments(PromptInfo promptInfo) =>
      <String, dynamic>{};

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) => throw UnimplementedError();

  @override
  Future<bool?> delete(String name, PromptInfo promptInfo) =>
      throw UnimplementedError();

  @override
  Future<void> dispose(String name, PromptInfo promptInfo) =>
      throw UnimplementedError();

  @override
  Future<bool?> init(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
  }) => throw UnimplementedError();

  @override
  Future<bool> linuxCheckAppArmorError() => throw UnimplementedError();

  @override
  Future<String?> read(
    String name,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) => throw UnimplementedError();

  @override
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) => throw UnimplementedError();
}

class RecordingBiometricStoragePlatform extends BiometricStoragePlatform {
  CanAuthenticateResponse canAuthenticateResponse =
      CanAuthenticateResponse.unsupported;
  PasskeyAvailability passkeyAvailabilityResponse =
      const PasskeyAvailability.unsupported();
  bool linuxCheckAppArmorErrorResponse = false;
  bool? isSupportedResponse;
  bool existsResponse = true;
  String? readResponse;
  PublicKeyCredentialAttestationJson registerPasskeyResponse =
      const PublicKeyCredentialAttestationJson(
        id: 'default-register-id',
        rawId: 'default-register-raw-id',
        response: AuthenticatorAttestationResponseJson(
          clientDataJSON: 'default-client-data',
          attestationObject: 'default-attestation-object',
        ),
      );
  PublicKeyCredentialAssertionJson authenticateWithPasskeyResponse =
      const PublicKeyCredentialAssertionJson(
        id: 'default-auth-id',
        rawId: 'default-auth-raw-id',
        response: AuthenticatorAssertionResponseJson(
          clientDataJSON: 'default-client-data',
          authenticatorData: 'default-authenticator-data',
          signature: 'default-signature',
        ),
      );

  final List<InitCall> initCalls = <InitCall>[];
  final List<ExistsCall> existsCalls = <ExistsCall>[];
  final List<ReadCall> readCalls = <ReadCall>[];
  final List<WriteCall> writeCalls = <WriteCall>[];
  final List<DeleteCall> deleteCalls = <DeleteCall>[];
  final List<DisposeCall> disposeCalls = <DisposeCall>[];
  final List<PublicKeyCredentialCreationOptionsJson> registerPasskeyCalls =
      <PublicKeyCredentialCreationOptionsJson>[];
  final List<PublicKeyCredentialRequestOptionsJson>
  authenticateWithPasskeyCalls = <PublicKeyCredentialRequestOptionsJson>[];

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async => canAuthenticateResponse;

  @override
  Future<PasskeyAvailability> getPasskeyAvailability() async =>
      passkeyAvailabilityResponse;

  @override
  Future<PublicKeyCredentialAttestationJson> registerPasskey(
    PublicKeyCredentialCreationOptionsJson options,
  ) async {
    registerPasskeyCalls.add(options);
    return registerPasskeyResponse;
  }

  @override
  Future<PublicKeyCredentialAssertionJson> authenticateWithPasskey(
    PublicKeyCredentialRequestOptionsJson options,
  ) async {
    authenticateWithPasskeyCalls.add(options);
    return authenticateWithPasskeyResponse;
  }

  @override
  Future<bool> isSupported({StorageFileInitOptions? options}) async =>
      isSupportedResponse ?? (await super.isSupported(options: options));

  @override
  Future<bool?> init(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
  }) async {
    initCalls.add(InitCall(name, options, forceInit));
    return true;
  }

  @override
  Future<bool> linuxCheckAppArmorError() async =>
      linuxCheckAppArmorErrorResponse;

  @override
  Future<bool> exists(String name, PromptInfo promptInfo) async {
    existsCalls.add(ExistsCall(name, promptInfo));
    return existsResponse;
  }

  @override
  Future<String?> read(
    String name,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) async {
    readCalls.add(ReadCall(name, promptInfo, forceBiometricAuthentication));
    return readResponse;
  }

  @override
  Future<bool?> delete(String name, PromptInfo promptInfo) async {
    deleteCalls.add(DeleteCall(name, promptInfo));
    return true;
  }

  @override
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) async {
    writeCalls.add(
      WriteCall(name, content, promptInfo, forceBiometricAuthentication),
    );
  }

  @override
  Future<void> dispose(String name, PromptInfo promptInfo) async {
    disposeCalls.add(DisposeCall(name, promptInfo));
  }
}

class InitCall {
  InitCall(this.name, this.options, this.forceInit);
  final String name;
  final StorageFileInitOptions? options;
  final bool forceInit;
}

class ReadCall {
  ReadCall(this.name, this.promptInfo, this.forceBiometricAuthentication);
  final String name;
  final PromptInfo promptInfo;
  final bool forceBiometricAuthentication;
}

class ExistsCall {
  ExistsCall(this.name, this.promptInfo);
  final String name;
  final PromptInfo promptInfo;
}

class WriteCall {
  WriteCall(
    this.name,
    this.content,
    this.promptInfo,
    this.forceBiometricAuthentication,
  );
  final String name;
  final String content;
  final PromptInfo promptInfo;
  final bool forceBiometricAuthentication;
}

class DeleteCall {
  DeleteCall(this.name, this.promptInfo);
  final String name;
  final PromptInfo promptInfo;
}

class DisposeCall {
  DisposeCall(this.name, this.promptInfo);
  final String name;
  final PromptInfo promptInfo;
}
