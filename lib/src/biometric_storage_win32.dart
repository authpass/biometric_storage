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
  static void register() {
    BiometricStorage.instance = Win32BiometricStoragePlugin();
  }

  @override
  Future<CanAuthenticateResponse> canAuthenticate() async {
    return CanAuthenticateResponse.errorHwUnavailable;
  }

  @override
  Future<BiometricStorageFile> getStorage(String name,
      {StorageFileInitOptions options,
      bool forceInit = false,
      AndroidPromptInfo androidPromptInfo =
          AndroidPromptInfo.defaultValues}) async {
    return BiometricStorageFile(this, namePrefix + name, androidPromptInfo);
  }

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<bool> delete(String name, AndroidPromptInfo androidPromptInfo) async {
    final namePointer = TEXT(name);
    try {
      final result = CredDelete(namePointer, CRED_TYPE_GENERIC, 0);
      if (result != TRUE) {
        final errorCode = GetLastError();
        if (errorCode == ERROR_NOT_FOUND) {
          _logger.fine('Unable to find credential of name $name');
        } else {
          _logger.warning('Error ($result): $errorCode');
        }
        return false;
      }
    } finally {
      free(namePointer);
    }
    return true;
  }

  @override
  Future<String> read(String name, AndroidPromptInfo androidPromptInfo) async {
    _logger.finer('read($name)');
    final credPointer = allocate<Pointer<CREDENTIAL>>();
    final namePointer = TEXT(name);
    try {
      if (CredRead(namePointer, CRED_TYPE_GENERIC, 0, credPointer) != TRUE) {
        final errorCode = GetLastError();
        if (errorCode == ERROR_NOT_FOUND) {
          _logger.fine('Unable to find credential of name $name');
        } else {
          _logger.warning('Error: $errorCode ',
              WindowsException(HRESULT_FROM_WIN32(errorCode)));
        }
        return null;
      }
      final cred = credPointer.value.ref;
      final blob = cred.CredentialBlob.asTypedList(cred.CredentialBlobSize);

      _logger.fine('CredFree()');
      CredFree(credPointer.value);

      return utf8.decode(blob);
    } finally {
      _logger.fine('free(credPointer)');
      free(credPointer);
      _logger.fine('free(namePointer)');
      free(namePointer);
      _logger.fine('read($name) done.');
    }
  }

  @override
  Future<void> write(
      String name, String content, AndroidPromptInfo androidPromptInfo) async {
    _logger.fine('write()');
    final examplePassword = utf8.encode(content) as Uint8List;
    final blob = examplePassword.allocatePointer();
    final namePointer = TEXT(name);

    final credential = CREDENTIAL.allocate()
      ..Type = CRED_TYPE_GENERIC
      ..TargetName = namePointer
      ..Persist = CRED_PERSIST_LOCAL_MACHINE
      ..UserName = TEXT('flutter.biometric_storage')
      ..CredentialBlob = blob
      ..CredentialBlobSize = examplePassword.length;
    try {
      final result = CredWrite(credential.addressOf, 0);
      if (result != TRUE) {
        final errorCode = GetLastError();
        throw BiometricStorageException(
            'Error writing credential $name ($result): $errorCode');
      }
    } finally {
      _logger.fine('free');
      free(blob);
      free(credential.addressOf);
      free(namePointer);
      _logger.fine('free done');
    }
  }
}
