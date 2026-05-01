# biometric_storage

[![Pub](https://img.shields.io/pub/v/biometric_storage?color=green)](https://pub.dev/packages/biometric_storage/)

Encrypted file store, **optionally** secured by biometric lock
for Android, iOS, MacOS and partial support for Linux and Windows.

Meant as a way to store small data in a hardware encrypted fashion. E.g. to
store passwords, secret keys, etc. but not massive amounts
of data.

- Android: Uses androidx with KeyStore.
- iOS and MacOS: LocalAuthentication with KeyChain.
- Linux: Stores values in Keyring using libsecret. (No biometric authentication support).
- Windows: Uses [wincreds.h to store into read/write into credential store](https://docs.microsoft.com/en-us/windows/win32/api/wincred/).
- Web: Uses WebAuthn PRF when the browser can prove support for both PRF and a user-verifying platform authenticator at runtime. Unsupported browsers cleanly report `unsupported` instead of falling back to weaker storage.

## Web support and security

This package is intended to unlock secrets on-device using platform security primitives such as Android Keystore and Apple Keychain, optionally gated by biometrics.

On the web, the federated implementation is intentionally stricter than a plain `localStorage` wrapper:

- it requires a secure context (`https:` or equivalent localhost secure context)
- it requires WebAuthn support
- it requires runtime-advertised support for the PRF extension
- it requires a user-verifying platform authenticator (Touch ID, Face ID, Android device unlock, etc.)
- it stores only encrypted ciphertext plus WebAuthn credential metadata in browser storage

If the browser cannot honestly prove those capabilities — for example, many Windows/browser combinations today still do not expose PRF — `isSupported()` returns `false` and `canAuthenticate()` returns `unsupported`.

### What this means in practice

- Web support is capability-gated, not assumed.
- A storage handle can still be created without prompting the user.
- The first `write()` creates the WebAuthn credential when the user opts in.
- A later `read()` prompts the platform authenticator only if a stored credential already exists.

### Recommended approach for web

For web applications, prefer:

- server-backed session tokens with short lifetimes
- passkeys / WebAuthn for authentication
- keeping the most sensitive bearer secrets off the browser when possible

If you need a browser login flow, this package can participate when PRF is available. When it is not, the intended fallback remains your regular web login/session design.

Check out [AuthPass Password Manager](https://authpass.app/) for a app which
makes heavy use of this plugin.

## Getting Started

### Installation

#### Android

- Requirements:
  - Android: API Level >= 23 (`minSdkVersion 23`)
  - Make sure to use a current Kotlin version in your app
  - `MainActivity` must extend `FlutterFragmentActivity`
  - The main activity theme must use an AppCompat theme on older Android versions

##### Resources

- <https://developer.android.com/topic/security/data>
- <https://developer.android.com/topic/security/best-practices>

#### iOS

<https://developer.apple.com/documentation/localauthentication/logging_a_user_into_your_app_with_face_id_or_touch_id>

- Include the `NSFaceIDUsageDescription` key in your app’s `Info.plist`
- Supports all iOS versions supported by Flutter

**Known Issue**: Since iOS 15, the simulator no longer seems to support local authentication:
<https://developer.apple.com/forums/thread/685773>

#### macOS

- Include the `NSFaceIDUsageDescription` key in your app’s `Info.plist`
- Enable keychain sharing and signing
- Supports all macOS versions supported by Flutter

### Usage

> You basically only need 4 methods.

1. Check whether the package is supported on this platform

```dart
final storage = BiometricStorage();
if (!await storage.isSupported()) {
  // Skip biometrics entirely and fall back to regular login.
  return;
}
```

1. Check whether biometric authentication is available right now

```dart
final response = await storage.canAuthenticate();
if (response.shouldFallbackToRegularLogin) {
  // Show regular login. You can still inspect response to see if the user
  // needs to enroll biometrics, enable a passcode, etc.
  return;
}
```

If you only need a bool for startup auth, you can use:

```dart
final canAutoPrompt = await storage.canAuthenticateWithBiometrics();
```

1. Create the access object

```dart
final store = await storage.getStorageIfSupported('mystorage');
if (store == null) {
  // Unsupported platform: skip without throwing.
  return;
}
```

1. Read data

```dart
final data = await store.read();
```

1. Write data

```dart
const myNewData = 'Hello World';
await store.write(myNewData);
```

### Suggested login flow

For the UX described above:

- On app start:
  - call `isSupported()`
  - if `false`, go straight to regular login
  - if `true`, call `canAuthenticate()` or `canAuthenticateWithBiometrics()`
  - if biometrics are available, read from the protected store and let the
    platform prompt automatically
  - otherwise, fall back to regular login without error
- After regular login success:
  - if `isSupported()` is `true`, show a “Use biometrics next time” toggle
  - when enabled, write the login token / small secret to a biometric-backed
    store for next launch

See also the API documentation:
<https://pub.dev/documentation/biometric_storage/latest/biometric_storage/BiometricStorageFile-class.html#instance-methods>
