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

  static const _userName = 'flutter.biometric_storage';

  /// Registers this class as the default instance of [BiometricStorage].
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
  Future<bool> delete(String name, PromptInfo promptInfo) async {
    return using((arena) {
      final result = CredDelete(
        name.toPcwstr(allocator: arena),
        CRED_TYPE_GENERIC,
      );
      if (!result.value) {
        _logFailure('deleting', name, result.error);
        return false;
      }
      return true;
    });
  }

  @override
  Future<String?> read(String name, PromptInfo promptInfo) async {
    _logger.finer('read($name)');
    return using((arena) {
      final credentialPointer = arena<Pointer<CREDENTIAL>>();
      final result = CredRead(
        name.toPcwstr(allocator: arena),
        CRED_TYPE_GENERIC,
        credentialPointer,
      );
      if (!result.value) {
        _logFailure('reading', name, result.error);
        return null;
      }
      final credential = credentialPointer.value;
      try {
        // asTypedList is a view onto memory owned by the credential, so the
        // bytes have to be copied out before CredFree invalidates them.
        final blob = Uint8List.fromList(
          credential.ref.CredentialBlob.asTypedList(
            credential.ref.CredentialBlobSize,
          ),
        );
        return utf8.decode(blob);
      } finally {
        CredFree(credential);
      }
    });
  }

  @override
  Future<void> write(String name, String content, PromptInfo promptInfo) async {
    _logger.finer('write($name)');
    using((arena) {
      final blob = utf8.encode(content);
      // toNative rejects an empty list, but an empty value is a legitimate
      // thing to store: a zero-length blob needs a valid pointer all the same.
      final blobPointer = blob.isEmpty
          ? arena<Uint8>()
          : blob.toNative(allocator: arena);
      final credential = arena<CREDENTIAL>()
        ..ref.Type = CRED_TYPE_GENERIC
        ..ref.TargetName = name.toPwstr(allocator: arena)
        ..ref.Persist = CRED_PERSIST_LOCAL_MACHINE
        ..ref.UserName = _userName.toPwstr(allocator: arena)
        ..ref.CredentialBlob = blobPointer
        ..ref.CredentialBlobSize = blob.length;

      final result = CredWrite(credential, 0);
      if (!result.value) {
        throw BiometricStorageException(
          'Error writing credential $name: ${result.error} '
          '(${WindowsException(HRESULT_FROM_WIN32(result.error))})',
        );
      }
    });
  }

  void _logFailure(String action, String name, WIN32_ERROR error) {
    if (error == ERROR_NOT_FOUND) {
      _logger.fine('Unable to find credential of name $name');
    } else {
      _logger.warning(
        'Error $action credential $name: $error',
        WindowsException(HRESULT_FROM_WIN32(error)),
      );
    }
  }
}
