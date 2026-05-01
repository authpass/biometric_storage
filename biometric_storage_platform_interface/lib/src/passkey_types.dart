import 'package:flutter/foundation.dart';

@immutable
class PasskeyAvailability {
  const PasskeyAvailability({
    required this.isSupported,
    required this.isAvailable,
    this.hasPlatformAuthenticator = false,
    this.hasConditionalUi = false,
    this.hasDiscoverableCredentials = false,
    this.hasPendingRegistrationOpportunity = false,
    this.supportsPrfStorage = false,
    this.isPrfStorageAvailable = false,
    this.metadata = const <String, dynamic>{},
  });

  const PasskeyAvailability.unsupported()
      : isSupported = false,
        isAvailable = false,
        hasPlatformAuthenticator = false,
        hasConditionalUi = false,
        hasDiscoverableCredentials = false,
        hasPendingRegistrationOpportunity = false,
        supportsPrfStorage = false,
        isPrfStorageAvailable = false,
        metadata = const <String, dynamic>{};

  final bool isSupported;
  final bool isAvailable;
  final bool hasPlatformAuthenticator;
  final bool hasConditionalUi;
  final bool hasDiscoverableCredentials;
  final bool hasPendingRegistrationOpportunity;
  final bool supportsPrfStorage;
  final bool isPrfStorageAvailable;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'isSupported': isSupported,
        'isAvailable': isAvailable,
        'hasPlatformAuthenticator': hasPlatformAuthenticator,
        'hasConditionalUi': hasConditionalUi,
        'hasDiscoverableCredentials': hasDiscoverableCredentials,
        'hasPendingRegistrationOpportunity': hasPendingRegistrationOpportunity,
        'supportsPrfStorage': supportsPrfStorage,
        'isPrfStorageAvailable': isPrfStorageAvailable,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory PasskeyAvailability.fromJson(Map<String, dynamic> json) {
    return PasskeyAvailability(
      isSupported: json['isSupported'] as bool? ?? false,
      isAvailable: json['isAvailable'] as bool? ?? false,
      hasPlatformAuthenticator:
          json['hasPlatformAuthenticator'] as bool? ?? false,
      hasConditionalUi: json['hasConditionalUi'] as bool? ?? false,
      hasDiscoverableCredentials:
          json['hasDiscoverableCredentials'] as bool? ?? false,
      hasPendingRegistrationOpportunity:
          json['hasPendingRegistrationOpportunity'] as bool? ?? false,
      supportsPrfStorage: json['supportsPrfStorage'] as bool? ?? false,
      isPrfStorageAvailable: json['isPrfStorageAvailable'] as bool? ?? false,
      metadata: _mapFrom(json['metadata']),
    );
  }
}

@immutable
class PublicKeyCredentialRpEntityJson {
  const PublicKeyCredentialRpEntityJson({
    required this.name,
    this.id,
    this.icon,
    this.additionalData = const <String, dynamic>{},
  });

  final String? id;
  final String name;
  final String? icon;
  final Map<String, dynamic> additionalData;

  factory PublicKeyCredentialRpEntityJson.fromJson(Map<String, dynamic> json) {
    return PublicKeyCredentialRpEntityJson(
      id: json['id'] as String?,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      additionalData: _additionalData(json, <String>{'id', 'name', 'icon'}),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'id': id,
        'name': name,
        if (icon != null) 'icon': icon,
        ...additionalData,
      };
}

@immutable
class PublicKeyCredentialUserEntityJson {
  const PublicKeyCredentialUserEntityJson({
    required this.id,
    required this.name,
    required this.displayName,
    this.icon,
    this.additionalData = const <String, dynamic>{},
  });

  final String id;
  final String name;
  final String displayName;
  final String? icon;
  final Map<String, dynamic> additionalData;

  factory PublicKeyCredentialUserEntityJson.fromJson(
    Map<String, dynamic> json,
  ) {
    return PublicKeyCredentialUserEntityJson(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['displayName'] as String,
      icon: json['icon'] as String?,
      additionalData: _additionalData(
        json,
        <String>{'id', 'name', 'displayName', 'icon'},
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'displayName': displayName,
        if (icon != null) 'icon': icon,
        ...additionalData,
      };
}

@immutable
class PublicKeyCredentialParametersJson {
  const PublicKeyCredentialParametersJson({
    required this.type,
    required this.alg,
    this.additionalData = const <String, dynamic>{},
  });

  final String type;
  final int alg;
  final Map<String, dynamic> additionalData;

  factory PublicKeyCredentialParametersJson.fromJson(
    Map<String, dynamic> json,
  ) {
    return PublicKeyCredentialParametersJson(
      type: json['type'] as String,
      alg: json['alg'] as int,
      additionalData: _additionalData(json, <String>{'type', 'alg'}),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'alg': alg,
        ...additionalData,
      };
}

@immutable
class PublicKeyCredentialDescriptorJson {
  const PublicKeyCredentialDescriptorJson({
    required this.id,
    this.type = 'public-key',
    this.transports,
    this.additionalData = const <String, dynamic>{},
  });

  final String id;
  final String type;
  final List<String>? transports;
  final Map<String, dynamic> additionalData;

  factory PublicKeyCredentialDescriptorJson.fromJson(
    Map<String, dynamic> json,
  ) {
    return PublicKeyCredentialDescriptorJson(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'public-key',
      transports: _stringListFrom(json['transports']),
      additionalData:
          _additionalData(json, <String>{'id', 'type', 'transports'}),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        if (transports != null) 'transports': transports,
        ...additionalData,
      };
}

@immutable
class AuthenticatorSelectionCriteriaJson {
  const AuthenticatorSelectionCriteriaJson({
    this.authenticatorAttachment,
    this.residentKey,
    this.requireResidentKey,
    this.userVerification,
    this.additionalData = const <String, dynamic>{},
  });

  final String? authenticatorAttachment;
  final String? residentKey;
  final bool? requireResidentKey;
  final String? userVerification;
  final Map<String, dynamic> additionalData;

  factory AuthenticatorSelectionCriteriaJson.fromJson(
    Map<String, dynamic> json,
  ) {
    return AuthenticatorSelectionCriteriaJson(
      authenticatorAttachment: json['authenticatorAttachment'] as String?,
      residentKey: json['residentKey'] as String?,
      requireResidentKey: json['requireResidentKey'] as bool?,
      userVerification: json['userVerification'] as String?,
      additionalData: _additionalData(
        json,
        <String>{
          'authenticatorAttachment',
          'residentKey',
          'requireResidentKey',
          'userVerification',
        },
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (authenticatorAttachment != null)
          'authenticatorAttachment': authenticatorAttachment,
        if (residentKey != null) 'residentKey': residentKey,
        if (requireResidentKey != null)
          'requireResidentKey': requireResidentKey,
        if (userVerification != null) 'userVerification': userVerification,
        ...additionalData,
      };
}

@immutable
class PublicKeyCredentialCreationOptionsJson {
  const PublicKeyCredentialCreationOptionsJson({
    required this.challenge,
    required this.rp,
    required this.user,
    required this.pubKeyCredParams,
    this.timeout,
    this.excludeCredentials,
    this.authenticatorSelection,
    this.attestation,
    this.attestationFormats,
    this.extensions,
    this.hints,
    this.additionalData = const <String, dynamic>{},
  });

  final String challenge;
  final PublicKeyCredentialRpEntityJson rp;
  final PublicKeyCredentialUserEntityJson user;
  final List<PublicKeyCredentialParametersJson> pubKeyCredParams;
  final int? timeout;
  final List<PublicKeyCredentialDescriptorJson>? excludeCredentials;
  final AuthenticatorSelectionCriteriaJson? authenticatorSelection;
  final String? attestation;
  final List<String>? attestationFormats;
  final Map<String, dynamic>? extensions;
  final List<String>? hints;
  final Map<String, dynamic> additionalData;

  factory PublicKeyCredentialCreationOptionsJson.fromJson(
    Map<String, dynamic> json,
  ) {
    return PublicKeyCredentialCreationOptionsJson(
      challenge: json['challenge'] as String,
      rp: PublicKeyCredentialRpEntityJson.fromJson(
        _requiredMap(json, 'rp'),
      ),
      user: PublicKeyCredentialUserEntityJson.fromJson(
        _requiredMap(json, 'user'),
      ),
      pubKeyCredParams: _mapListFrom(
        json['pubKeyCredParams'],
        PublicKeyCredentialParametersJson.fromJson,
      ),
      timeout: _intFrom(json['timeout']),
      excludeCredentials: _optionalMapListFrom(
        json['excludeCredentials'],
        PublicKeyCredentialDescriptorJson.fromJson,
      ),
      authenticatorSelection: json['authenticatorSelection'] == null
          ? null
          : AuthenticatorSelectionCriteriaJson.fromJson(
              _requiredMap(json, 'authenticatorSelection'),
            ),
      attestation: json['attestation'] as String?,
      attestationFormats: _stringListFrom(json['attestationFormats']),
      extensions: _mapFromNullable(json['extensions']),
      hints: _stringListFrom(json['hints']),
      additionalData: _additionalData(
        json,
        <String>{
          'challenge',
          'rp',
          'user',
          'pubKeyCredParams',
          'timeout',
          'excludeCredentials',
          'authenticatorSelection',
          'attestation',
          'attestationFormats',
          'extensions',
          'hints',
        },
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'challenge': challenge,
        'rp': rp.toJson(),
        'user': user.toJson(),
        'pubKeyCredParams':
            pubKeyCredParams.map((parameter) => parameter.toJson()).toList(),
        if (timeout != null) 'timeout': timeout,
        if (excludeCredentials != null)
          'excludeCredentials': excludeCredentials!
              .map((credential) => credential.toJson())
              .toList(),
        if (authenticatorSelection != null)
          'authenticatorSelection': authenticatorSelection!.toJson(),
        if (attestation != null) 'attestation': attestation,
        if (attestationFormats != null)
          'attestationFormats': attestationFormats,
        if (extensions != null) 'extensions': extensions,
        if (hints != null) 'hints': hints,
        ...additionalData,
      };
}

@immutable
class PublicKeyCredentialRequestOptionsJson {
  const PublicKeyCredentialRequestOptionsJson({
    required this.challenge,
    this.timeout,
    this.rpId,
    this.allowCredentials,
    this.userVerification,
    this.extensions,
    this.hints,
    this.additionalData = const <String, dynamic>{},
  });

  final String challenge;
  final int? timeout;
  final String? rpId;
  final List<PublicKeyCredentialDescriptorJson>? allowCredentials;
  final String? userVerification;
  final Map<String, dynamic>? extensions;
  final List<String>? hints;
  final Map<String, dynamic> additionalData;

  factory PublicKeyCredentialRequestOptionsJson.fromJson(
    Map<String, dynamic> json,
  ) {
    return PublicKeyCredentialRequestOptionsJson(
      challenge: json['challenge'] as String,
      timeout: _intFrom(json['timeout']),
      rpId: json['rpId'] as String?,
      allowCredentials: _optionalMapListFrom(
        json['allowCredentials'],
        PublicKeyCredentialDescriptorJson.fromJson,
      ),
      userVerification: json['userVerification'] as String?,
      extensions: _mapFromNullable(json['extensions']),
      hints: _stringListFrom(json['hints']),
      additionalData: _additionalData(
        json,
        <String>{
          'challenge',
          'timeout',
          'rpId',
          'allowCredentials',
          'userVerification',
          'extensions',
          'hints',
        },
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'challenge': challenge,
        if (timeout != null) 'timeout': timeout,
        if (rpId != null) 'rpId': rpId,
        if (allowCredentials != null)
          'allowCredentials': allowCredentials!
              .map((credential) => credential.toJson())
              .toList(),
        if (userVerification != null) 'userVerification': userVerification,
        if (extensions != null) 'extensions': extensions,
        if (hints != null) 'hints': hints,
        ...additionalData,
      };
}

@immutable
class AuthenticatorAttestationResponseJson {
  const AuthenticatorAttestationResponseJson({
    required this.clientDataJSON,
    required this.attestationObject,
    this.transports,
    this.publicKeyAlgorithm,
    this.publicKey,
    this.authenticatorData,
    this.additionalData = const <String, dynamic>{},
  });

  final String clientDataJSON;
  final String attestationObject;
  final List<String>? transports;
  final int? publicKeyAlgorithm;
  final String? publicKey;
  final String? authenticatorData;
  final Map<String, dynamic> additionalData;

  factory AuthenticatorAttestationResponseJson.fromJson(
    Map<String, dynamic> json,
  ) {
    return AuthenticatorAttestationResponseJson(
      clientDataJSON: json['clientDataJSON'] as String,
      attestationObject: json['attestationObject'] as String,
      transports: _stringListFrom(json['transports']),
      publicKeyAlgorithm: _intFrom(json['publicKeyAlgorithm']),
      publicKey: json['publicKey'] as String?,
      authenticatorData: json['authenticatorData'] as String?,
      additionalData: _additionalData(
        json,
        <String>{
          'clientDataJSON',
          'attestationObject',
          'transports',
          'publicKeyAlgorithm',
          'publicKey',
          'authenticatorData',
        },
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'clientDataJSON': clientDataJSON,
        'attestationObject': attestationObject,
        if (transports != null) 'transports': transports,
        if (publicKeyAlgorithm != null)
          'publicKeyAlgorithm': publicKeyAlgorithm,
        if (publicKey != null) 'publicKey': publicKey,
        if (authenticatorData != null) 'authenticatorData': authenticatorData,
        ...additionalData,
      };
}

@immutable
class AuthenticatorAssertionResponseJson {
  const AuthenticatorAssertionResponseJson({
    required this.clientDataJSON,
    required this.authenticatorData,
    required this.signature,
    this.userHandle,
    this.additionalData = const <String, dynamic>{},
  });

  final String clientDataJSON;
  final String authenticatorData;
  final String signature;
  final String? userHandle;
  final Map<String, dynamic> additionalData;

  factory AuthenticatorAssertionResponseJson.fromJson(
    Map<String, dynamic> json,
  ) {
    return AuthenticatorAssertionResponseJson(
      clientDataJSON: json['clientDataJSON'] as String,
      authenticatorData: json['authenticatorData'] as String,
      signature: json['signature'] as String,
      userHandle: json['userHandle'] as String?,
      additionalData: _additionalData(
        json,
        <String>{
          'clientDataJSON',
          'authenticatorData',
          'signature',
          'userHandle',
        },
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'clientDataJSON': clientDataJSON,
        'authenticatorData': authenticatorData,
        'signature': signature,
        if (userHandle != null) 'userHandle': userHandle,
        ...additionalData,
      };
}

@immutable
class PublicKeyCredentialAttestationJson {
  const PublicKeyCredentialAttestationJson({
    required this.id,
    required this.rawId,
    required this.response,
    this.type = 'public-key',
    this.authenticatorAttachment,
    this.clientExtensionResults,
    this.additionalData = const <String, dynamic>{},
  });

  final String id;
  final String rawId;
  final String type;
  final String? authenticatorAttachment;
  final AuthenticatorAttestationResponseJson response;
  final Map<String, dynamic>? clientExtensionResults;
  final Map<String, dynamic> additionalData;

  factory PublicKeyCredentialAttestationJson.fromJson(
    Map<String, dynamic> json,
  ) {
    return PublicKeyCredentialAttestationJson(
      id: json['id'] as String,
      rawId: json['rawId'] as String,
      type: json['type'] as String? ?? 'public-key',
      authenticatorAttachment: json['authenticatorAttachment'] as String?,
      response: AuthenticatorAttestationResponseJson.fromJson(
        _requiredMap(json, 'response'),
      ),
      clientExtensionResults: _mapFromNullable(json['clientExtensionResults']),
      additionalData: _additionalData(
        json,
        <String>{
          'id',
          'rawId',
          'type',
          'authenticatorAttachment',
          'response',
          'clientExtensionResults',
        },
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'rawId': rawId,
        'type': type,
        if (authenticatorAttachment != null)
          'authenticatorAttachment': authenticatorAttachment,
        'response': response.toJson(),
        if (clientExtensionResults != null)
          'clientExtensionResults': clientExtensionResults,
        ...additionalData,
      };
}

@immutable
class PublicKeyCredentialAssertionJson {
  const PublicKeyCredentialAssertionJson({
    required this.id,
    required this.rawId,
    required this.response,
    this.type = 'public-key',
    this.authenticatorAttachment,
    this.clientExtensionResults,
    this.additionalData = const <String, dynamic>{},
  });

  final String id;
  final String rawId;
  final String type;
  final String? authenticatorAttachment;
  final AuthenticatorAssertionResponseJson response;
  final Map<String, dynamic>? clientExtensionResults;
  final Map<String, dynamic> additionalData;

  factory PublicKeyCredentialAssertionJson.fromJson(
    Map<String, dynamic> json,
  ) {
    return PublicKeyCredentialAssertionJson(
      id: json['id'] as String,
      rawId: json['rawId'] as String,
      type: json['type'] as String? ?? 'public-key',
      authenticatorAttachment: json['authenticatorAttachment'] as String?,
      response: AuthenticatorAssertionResponseJson.fromJson(
        _requiredMap(json, 'response'),
      ),
      clientExtensionResults: _mapFromNullable(json['clientExtensionResults']),
      additionalData: _additionalData(
        json,
        <String>{
          'id',
          'rawId',
          'type',
          'authenticatorAttachment',
          'response',
          'clientExtensionResults',
        },
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'rawId': rawId,
        'type': type,
        if (authenticatorAttachment != null)
          'authenticatorAttachment': authenticatorAttachment,
        'response': response.toJson(),
        if (clientExtensionResults != null)
          'clientExtensionResults': clientExtensionResults,
        ...additionalData,
      };
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw StateError('Expected "$key" to be a JSON object.');
  }
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _additionalData(
  Map<String, dynamic> json,
  Set<String> knownKeys,
) {
  return Map<String, dynamic>.unmodifiable(
    Map<String, dynamic>.fromEntries(
      json.entries.where((entry) => !knownKeys.contains(entry.key)),
    ),
  );
}

Map<String, dynamic> _mapFrom(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(value);
  }
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      Map<String, dynamic>.from(value),
    );
  }
  return const <String, dynamic>{};
}

Map<String, dynamic>? _mapFromNullable(Object? value) {
  if (value == null) {
    return null;
  }
  return _mapFrom(value);
}

List<String>? _stringListFrom(Object? value) {
  if (value == null) {
    return null;
  }
  return (value as List<dynamic>)
      .map((item) => item as String)
      .toList(growable: false);
}

List<T> _mapListFrom<T>(
  Object? value,
  T Function(Map<String, dynamic> json) converter,
) {
  return (value as List<dynamic>)
      .map(
        (item) => converter(Map<String, dynamic>.from(item as Map)),
      )
      .toList(growable: false);
}

List<T>? _optionalMapListFrom<T>(
  Object? value,
  T Function(Map<String, dynamic> json) converter,
) {
  if (value == null) {
    return null;
  }
  return _mapListFrom(value, converter);
}

int? _intFrom(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.parse(value.toString());
}
