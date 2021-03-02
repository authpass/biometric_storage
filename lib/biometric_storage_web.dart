import 'dart:async';
// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'package:biometric_storage/src/biometric_storage.dart';

/// A web implementation of the BiometricStorage plugin.
class BiometricStoragePluginWeb extends BiometricStorage {
  BiometricStoragePluginWeb() : super.create();

  static const namePrefix = 'design.codeux.authpass.';

  static void registerWith(Registrar registrar) {
    BiometricStorage.instance = BiometricStoragePluginWeb();
  }

  @override
  Future<CanAuthenticateResponse> canAuthenticate() async =>
      CanAuthenticateResponse.errorHwUnavailable;

  @override
  Future<BiometricStorageFile> getStorage(String name,
      {StorageFileInitOptions? options,
      bool forceInit = false,
      AndroidPromptInfo androidPromptInfo =
          AndroidPromptInfo.defaultValues}) async {
    return BiometricStorageFile(this, namePrefix + name, androidPromptInfo);
  }

  @override
  Future<bool> delete(String name, AndroidPromptInfo androidPromptInfo) async {
    return html.window.localStorage.remove(name) != null;
  }

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<String?> read(String name, AndroidPromptInfo androidPromptInfo) async {
    return html.window.localStorage[name];
  }

  @override
  Future<void> write(
      String name, String content, AndroidPromptInfo androidPromptInfo) async {
    html.window.localStorage[name] = content;
  }
}
