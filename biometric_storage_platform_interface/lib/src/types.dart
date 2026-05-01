import 'package:flutter/foundation.dart';

import 'passkey_types.dart';

/// Reason for not supporting authentication.
/// **As long as this is NOT [unsupported] you can still use the secure
/// storage without biometric storage** (By setting
/// [StorageFileInitOptions.authenticationRequired] to `false`).
enum CanAuthenticateResponse {
  success,
  errorHwUnavailable,
  errorNoBiometricEnrolled,
  errorNoHardware,

  /// Passcode is not set (iOS/MacOS) or no user credentials (on macos).
  errorPasscodeNotSet,

  /// Used on android if the status is unknown.
  /// https://developer.android.com/reference/androidx/biometric/BiometricManager#BIOMETRIC_STATUS_UNKNOWN
  statusUnknown,

  /// Plugin does not support platform. This should no longer be the case.
  unsupported,
}

extension CanAuthenticateResponseX on CanAuthenticateResponse {
  /// Whether this platform can use the package surface without throwing for
  /// lack of platform support.
  bool get isStorageSupported => this != CanAuthenticateResponse.unsupported;

  /// Whether biometric authentication can be attempted right now.
  bool get canAuthenticateWithBiometrics =>
      this == CanAuthenticateResponse.success ||
      this == CanAuthenticateResponse.statusUnknown;

  /// Whether the caller should fall back to regular login for now.
  bool get shouldFallbackToRegularLogin => !canAuthenticateWithBiometrics;
}

const canAuthenticateMapping = <String, CanAuthenticateResponse>{
  'Success': CanAuthenticateResponse.success,
  'ErrorHwUnavailable': CanAuthenticateResponse.errorHwUnavailable,
  'ErrorNoBiometricEnrolled': CanAuthenticateResponse.errorNoBiometricEnrolled,
  'ErrorNoHardware': CanAuthenticateResponse.errorNoHardware,
  'ErrorPasscodeNotSet': CanAuthenticateResponse.errorPasscodeNotSet,
  'ErrorUnknown': CanAuthenticateResponse.unsupported,
  'ErrorStatusUnknown': CanAuthenticateResponse.statusUnknown,
};

enum AuthExceptionCode {
  /// User taps the cancel/negative button or presses `back`.
  userCanceled,

  /// Authentication prompt is canceled due to another reason
  /// (like when biometric sensor becamse unavailable like when
  /// user switches between apps, logsout, etc).
  canceled,

  /// The protected key material is no longer accessible because the enrolled
  /// biometric set changed or biometric access was revoked.
  biometricsChanged,

  unknown,
  timeout,
  linuxAppArmorDenied,
}

const authErrorCodeMapping = <String, AuthExceptionCode>{
  'AuthError:UserCanceled': AuthExceptionCode.userCanceled,
  'AuthError:Canceled': AuthExceptionCode.canceled,
  'AuthError:BiometricsChanged': AuthExceptionCode.biometricsChanged,
  'AuthError:Timeout': AuthExceptionCode.timeout,
};

class BiometricStorageException implements Exception {
  BiometricStorageException(this.message);

  final String message;

  @override
  String toString() => 'BiometricStorageException{message: $message}';
}

/// Exceptions during authentication operations.
/// See [AuthExceptionCode] for details.
class AuthException implements Exception {
  AuthException(this.code, this.message);

  final AuthExceptionCode code;
  final String message;

  @override
  String toString() => 'AuthException{code: $code, message: $message}';
}

class StorageFileInitOptions {
  StorageFileInitOptions({
    Duration? androidAuthenticationValidityDuration,
    Duration? darwinTouchIDAuthenticationAllowableReuseDuration,
    this.darwinTouchIDAuthenticationForceReuseContextDuration,
    @Deprecated(
      'use use androidAuthenticationValidityDuration, '
      'iosTouchIDAuthenticationAllowableReuseDuration or '
      'iosTouchIDAuthenticationForceReuseContextDuration instead',
    )
    int authenticationValidityDurationSeconds = -1,
    this.authenticationRequired = true,
    this.androidUseStrongBox = true,
    this.androidBiometricOnly = true,
    this.darwinBiometricOnly = true,
  })  : androidAuthenticationValidityDuration =
            androidAuthenticationValidityDuration ??
                (authenticationValidityDurationSeconds <= 0
                    ? null
                    : Duration(seconds: authenticationValidityDurationSeconds)),
        darwinTouchIDAuthenticationAllowableReuseDuration =
            darwinTouchIDAuthenticationAllowableReuseDuration ??
                (authenticationValidityDurationSeconds <= 0
                    ? null
                    : Duration(seconds: authenticationValidityDurationSeconds));

  final Duration? androidAuthenticationValidityDuration;
  final Duration? darwinTouchIDAuthenticationAllowableReuseDuration;
  final Duration? darwinTouchIDAuthenticationForceReuseContextDuration;
  final bool authenticationRequired;
  final bool androidBiometricOnly;
  final bool darwinBiometricOnly;
  final bool androidUseStrongBox;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'androidAuthenticationValidityDurationSeconds':
            androidAuthenticationValidityDuration?.inSeconds,
        'darwinTouchIDAuthenticationAllowableReuseDurationSeconds':
            darwinTouchIDAuthenticationAllowableReuseDuration?.inSeconds,
        'darwinTouchIDAuthenticationForceReuseContextDurationSeconds':
            darwinTouchIDAuthenticationForceReuseContextDuration?.inSeconds,
        'authenticationRequired': authenticationRequired,
        'androidBiometricOnly': androidBiometricOnly,
        'darwinBiometricOnly': darwinBiometricOnly,
        'androidUseStrongBox': androidUseStrongBox,
      };
}

class AndroidPromptInfo {
  const AndroidPromptInfo({
    this.title = 'Authenticate to unlock data',
    this.subtitle,
    this.description,
    this.negativeButton = 'Cancel',
    this.confirmationRequired = true,
  });

  final String title;
  final String? subtitle;
  final String? description;
  final String negativeButton;
  final bool confirmationRequired;

  static const defaultValues = AndroidPromptInfo();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'negativeButton': negativeButton,
        'confirmationRequired': confirmationRequired,
      };
}

class IosPromptInfo {
  const IosPromptInfo({
    this.saveTitle = 'Unlock to save data',
    this.accessTitle = 'Unlock to access data',
  });

  final String saveTitle;
  final String accessTitle;

  static const defaultValues = IosPromptInfo();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'saveTitle': saveTitle,
        'accessTitle': accessTitle,
      };
}

class PromptInfo {
  const PromptInfo({
    this.androidPromptInfo = AndroidPromptInfo.defaultValues,
    this.iosPromptInfo = IosPromptInfo.defaultValues,
    this.macOsPromptInfo = IosPromptInfo.defaultValues,
  });

  static const defaultValues = PromptInfo();

  final AndroidPromptInfo androidPromptInfo;
  final IosPromptInfo iosPromptInfo;
  final IosPromptInfo macOsPromptInfo;
}

@protected
CanAuthenticateResponse mapCanAuthenticateResponse(String? response) {
  final ret = canAuthenticateMapping[response];
  if (ret == null) {
    throw StateError('Invalid response from native platform. {$response}');
  }
  return ret;
}

enum SecureAccessCapability {
  biometricStorage(1 << 0),
  passkeyAuthentication(1 << 1),
  passkeyPrfStorage(1 << 2);

  const SecureAccessCapability(this.bit);

  final int bit;
}

class SecureAccessCapabilitySet {
  const SecureAccessCapabilitySet(this.mask);

  const SecureAccessCapabilitySet.none() : mask = 0;

  factory SecureAccessCapabilitySet.fromValues(
    Iterable<SecureAccessCapability> capabilities,
  ) {
    var resolvedMask = 0;
    for (final capability in capabilities) {
      resolvedMask |= capability.bit;
    }
    return SecureAccessCapabilitySet(resolvedMask);
  }

  final int mask;

  bool contains(SecureAccessCapability capability) =>
      (mask & capability.bit) == capability.bit;

  Set<SecureAccessCapability> toSet() =>
      SecureAccessCapability.values.where(contains).toSet();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mask': mask,
        'values': toSet().map((capability) => capability.name).toList(),
      };
}

class BiometricStorageCapabilities {
  const BiometricStorageCapabilities({
    required this.passkeys,
    required this.biometricStorage,
  });

  final PasskeyAvailability passkeys;
  final CanAuthenticateResponse biometricStorage;

  SecureAccessCapabilitySet get supportedCapabilities =>
      SecureAccessCapabilitySet.fromValues(_supportedCapabilities());

  SecureAccessCapabilitySet get availableCapabilities =>
      SecureAccessCapabilitySet.fromValues(_availableCapabilities());

  bool isCapabilitySupported(SecureAccessCapability capability) =>
      supportedCapabilities.contains(capability);

  bool isCapabilityAvailable(SecureAccessCapability capability) =>
      availableCapabilities.contains(capability);

  bool get isBiometricStorageSupported => biometricStorage.isStorageSupported;

  bool get isBiometricStorageAvailable =>
      biometricStorage.canAuthenticateWithBiometrics;

  bool get prefersPasskeys => passkeys.isAvailable;

  Iterable<SecureAccessCapability> _supportedCapabilities() sync* {
    if (biometricStorage.isStorageSupported) {
      yield SecureAccessCapability.biometricStorage;
    }
    if (passkeys.isSupported) {
      yield SecureAccessCapability.passkeyAuthentication;
    }
    if (passkeys.supportsPrfStorage) {
      yield SecureAccessCapability.passkeyPrfStorage;
    }
  }

  Iterable<SecureAccessCapability> _availableCapabilities() sync* {
    if (biometricStorage.canAuthenticateWithBiometrics) {
      yield SecureAccessCapability.biometricStorage;
    }
    if (passkeys.isAvailable) {
      yield SecureAccessCapability.passkeyAuthentication;
    }
    if (passkeys.isPrfStorageAvailable) {
      yield SecureAccessCapability.passkeyPrfStorage;
    }
  }
}
