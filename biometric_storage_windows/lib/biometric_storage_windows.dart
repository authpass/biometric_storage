import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:biometric_storage_platform_interface/biometric_storage_platform_interface.dart';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';
import 'package:win32/win32.dart';

final _logger = Logger('biometric_storage_windows');

class BiometricStorageWindows extends BiometricStoragePlatform {
  static const namePrefix = 'design.codeux.authpass.';

  static void registerWith() {
    BiometricStoragePlatform.instance = BiometricStorageWindows();
  }

  String _storageName(String name) => '$namePrefix$name';

  @override
  Future<CanAuthenticateResponse> canAuthenticate({
    StorageFileInitOptions? options,
  }) async =>
      CanAuthenticateResponse.errorHwUnavailable;

  @override
  Future<bool?> init(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
  }) async =>
      true;

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<bool?> delete(
    String name,
    PromptInfo promptInfo,
  ) async {
    final namePointer =
        PCWSTR(_storageName(name).toNativeUtf16(allocator: calloc));
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
    final credPointer = calloc<Pointer<CREDENTIAL>>();
    final namePointer =
        PCWSTR(_storageName(name).toNativeUtf16(allocator: calloc));
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
      CredFree(credPointer.value);
      return value;
    } finally {
      calloc.free(credPointer);
      calloc.free(namePointer);
    }
  }

  @override
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo, {
    bool forceBiometricAuthentication = false,
  }) async {
    final passwordBytes = Uint8List.fromList(utf8.encode(content));
    final blob = passwordBytes.isEmpty
        ? nullptr
        : passwordBytes.toNative(allocator: calloc);
    final namePointer =
        PWSTR(_storageName(name).toNativeUtf16(allocator: calloc));
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
        throw BiometricStorageException(
          'Error writing credential $name: ${result.error}',
        );
      }
    } finally {
      if (blob != nullptr) {
        calloc.free(blob);
      }
      calloc.free(credential);
      calloc.free(namePointer);
      calloc.free(userNamePointer);
    }
  }

  @override
  Future<void> dispose(String name, PromptInfo promptInfo) async {}
}
