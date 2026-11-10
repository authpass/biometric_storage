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

  /// Names handed out by [getStorage] in this runtime, so that [forceInit] can
  /// mean what the API documents. Windows has no per-store native handle to
  /// hang this off, unlike the method-channel platforms.
  final _initialized = <String>{};

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
    // Keyed by the prefixed name, which is what every other method on this
    // class is handed — BiometricStorageFile carries the prefixed form, so
    // tracking the bare one here would leave dispose() unable to find it.
    final prefixedName = namePrefix + name;
    // forceInit was accepted and dropped here, so the documented "will throw if
    // the store was already created in this runtime" held on Android alone.
    if (!_initialized.add(prefixedName) && forceInit) {
      throw BiometricStorageException(
        "A storage file with the name '$name' was already initialized.",
        code: BiometricStorageExceptionCode.alreadyInitialized,
      );
    }
    return BiometricStorageFile(this, prefixedName, promptInfo);
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
        // Same distinction read() makes: `false` means there was nothing to
        // delete, so a store that is failing must not borrow that answer.
        if (result.error != ERROR_NOT_FOUND) {
          throw BiometricStorageException(
            'Error deleting credential $name: ${result.error}',
            code: BiometricStorageExceptionCode.storageFailure,
          );
        }
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
        // `null` is the documented answer to "no value stored". Reporting a
        // credential-store failure the same way left a caller unable to tell
        // an empty store from a broken one, so it read as data loss.
        if (result.error != ERROR_NOT_FOUND) {
          throw BiometricStorageException(
            'Error reading credential $name: ${result.error}',
            code: BiometricStorageExceptionCode.storageFailure,
          );
        }
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
          code: BiometricStorageExceptionCode.storageFailure,
        );
      }
    });
  }

  @override
  Future<bool> dispose(String name, PromptInfo promptInfo) async =>
      // [name] arrives prefixed, matching what getStorage recorded. There is
      // no native handle to release — the stored credential is deliberately
      // left alone — so forgetting the name is the whole of it.
      _initialized.remove(name);

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
