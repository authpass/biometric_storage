part of 'biometric_storage.dart';

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
          AndroidPromptInfo._defaultValues}) async {
    return BiometricStorageFile(this, namePrefix + name, androidPromptInfo);
  }

  @override
  Future<bool> linuxCheckAppArmorError() {
    throw false;
  }

  @override
  Future<bool> _delete(String name, AndroidPromptInfo androidPromptInfo) async {
    final result = CredDelete(TEXT(name), CRED_TYPE_GENERIC, 0);
    if (result != TRUE) {
      final errorCode = GetLastError();
      if (errorCode == ERROR_NOT_FOUND) {
        _logger.fine('Unable to find credential of name $name');
      } else {
        _logger.warning('Error ($result): $errorCode');
      }
      return false;
    }
    return true;
  }

  @override
  Future<String> _read(String name, AndroidPromptInfo androidPromptInfo) async {
    final credPointer = allocate<Pointer<CREDENTIAL>>();
    try {
      final result = CredRead(TEXT(name), CRED_TYPE_GENERIC, 0, credPointer);
      if (result != TRUE) {
        final errorCode = GetLastError();
        if (errorCode == ERROR_NOT_FOUND) {
          _logger.fine('Unable to find credential of name $name');
        } else {
          _logger.warning('Error ($result): $errorCode');
        }
        return null;
      }
      final cred = credPointer.value.ref;
      final blob = cred.CredentialBlob.asTypedList(cred.CredentialBlobSize);
      return utf8.decode(blob);
    } finally {
      CredFree(credPointer.value);
      free(credPointer);
    }
  }

  @override
  Future<void> _write(
      String name, String content, AndroidPromptInfo androidPromptInfo) async {
    final examplePassword = utf8.encode(content) as Uint8List;
    final blob = examplePassword.allocatePointer();

    final credential = CREDENTIAL.allocate()
      ..Type = CRED_TYPE_GENERIC
      ..TargetName = TEXT(name)
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
      free(blob);
      free(credential.addressOf);
    }
  }
}
