import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';
import 'package:win32/win32.dart';

import './biometric_storage.dart';

final _logger = Logger('biometric_storage_win32');

class Win32BiometricStoragePlugin extends BiometricStorage {
  Win32BiometricStoragePlugin() : super.create();

  static const namePrefix = 'design.codeux.authpass.';

  /// Registers this class as the default instance of [PathProviderPlatform]
  static void registerWith() {
    BiometricStorage.instance = Win32BiometricStoragePlugin();
  }

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async {
    return CanAuthenticateResponse.errorHwUnavailable;
  }

  @override
  Future<BiometricStorageFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  }) async {
    return BiometricStorageFile(this, namePrefix + name, promptInfo);
  }

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<bool> delete(
    String name,
    PromptInfo promptInfo,
  ) async {
    final namePointer = PCWSTR(name.toNativeUtf16(allocator: calloc));
    try {
      final result = CredDelete(namePointer, CRED_TYPE_GENERIC);
      if (!result.value) {
        final errorCode = result.error;
        if (errorCode == ERROR_NOT_FOUND) {
          _logger.fine('Unable to find credential of name $name');
        } else {
          _logger.warning('Error deleting credential $name: $errorCode');
        }
        return false;
      }
    } finally {
      calloc.free(namePointer);
    }
    return true;
  }

  @override
  Future<String?> read(
    String name,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) async {
    _logger.finer('read($name)');
    final credPointer = calloc<Pointer<CREDENTIAL>>();
    final namePointer = PCWSTR(name.toNativeUtf16(allocator: calloc));
    try {
      final result = CredRead(namePointer, CRED_TYPE_GENERIC, credPointer);
      if (!result.value) {
        final errorCode = result.error;
        if (errorCode == ERROR_NOT_FOUND) {
          _logger.fine('Unable to find credential of name $name');
        } else {
          _logger.warning('Error reading credential $name: $errorCode');
        }
        return null;
      }

      final cred = credPointer.value.ref;
      if (cred.CredentialBlobSize == 0) {
        return '';
      }

      final blob = Uint8List.fromList(
        cred.CredentialBlob.asTypedList(cred.CredentialBlobSize),
      );

      final value = utf8.decode(blob);

      _logger.fine('CredFree()');
      CredFree(credPointer.value);

      return value;
    } finally {
      _logger.fine('free(credPointer)');
      calloc.free(credPointer);
      _logger.fine('free(namePointer)');
      calloc.free(namePointer);
      _logger.fine('read($name) done.');
    }
  }

  @override
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) async {
    _logger.fine('write()');
    final passwordBytes = Uint8List.fromList(utf8.encode(content));
    final blob = passwordBytes.isEmpty
        ? nullptr
        : passwordBytes.toNative(allocator: calloc);
    final namePointer = PWSTR(name.toNativeUtf16(allocator: calloc));
    final userNamePointer = PWSTR(
      'flutter.biometric_storage'.toNativeUtf16(allocator: calloc),
    );

    final credential = calloc<CREDENTIAL>()
      ..ref.Type = CRED_TYPE_GENERIC
      ..ref.TargetName = namePointer
      ..ref.Persist = CRED_PERSIST_LOCAL_MACHINE
      ..ref.UserName = userNamePointer
      ..ref.CredentialBlob = blob
      ..ref.CredentialBlobSize = passwordBytes.length;
    try {
      final result = CredWrite(credential, 0);
      if (!result.value) {
        final errorCode = result.error;
        throw BiometricStorageException(
            'Error writing credential $name: $errorCode');
      }
    } finally {
      _logger.fine('free');
      if (blob != nullptr) {
        calloc.free(blob);
      }
      calloc.free(credential);
      calloc.free(namePointer);
      calloc.free(userNamePointer);
      _logger.fine('free done');
    }
  }
}
