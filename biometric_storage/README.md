# biometric_storage

[![Pub](https://img.shields.io/pub/v/biometric_storage?color=green)](https://pub.dev/packages/biometric_storage/)

Encrypted file store, **optionally** secured by biometric lock
for Android, iOS, MacOS and partial support for Linux, Windows and Web.

Meant as a way to store small data in a hardware encrypted fashion. E.g. to
store passwords, secret keys, etc. but not massive amounts
of data.

- Android: Uses androidx with KeyStore.
- iOS and MacOS: LocalAuthentication with KeyChain.
- Linux: Stores values in Keyring using libsecret. (No biometric authentication support).
- Windows: Uses [wincreds.h to store into read/write into credential store](https://docs.microsoft.com/en-us/windows/win32/api/wincred/).
- Web: Uses `flutter_secure_storage` in the federated web implementation.

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

1. Check whether biometric authentication is supported by the device

```dart
final response = await BiometricStorage().canAuthenticate();
if (response != CanAuthenticateResponse.success) {
  // panic..
}
```

1. Create the access object

```dart
final store = await BiometricStorage().getStorage('mystorage');
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

See also the API documentation:
<https://pub.dev/documentation/biometric_storage/latest/biometric_storage/BiometricStorageFile-class.html#instance-methods>
