/// The web counterpart of [platform_os_io.dart], which exists so that
/// `lib/src/biometric_storage.dart` need not import `dart:io` unconditionally.
/// That import is what made the package report as WebAssembly-incompatible.
///
/// Returns a value rather than throwing. Every caller is inside
/// `MethodChannelBiometricStorage`, which the web build never instantiates —
/// `BiometricStoragePluginWeb.registerWith` replaces the instance — so this
/// should be unreachable. If some path does reach it, `'web'` degrades the way
/// the callers already expect: `canAuthenticate` reports the platform as
/// unsupported, the AppArmor check reports no error, and the prompt-info switch
/// throws the same `StateError` it throws for any platform without a method
/// channel. Throwing here would instead turn an unreachable branch into a crash.
String get operatingSystem => 'web';
