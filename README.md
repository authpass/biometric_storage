# biometric_storage

[![Pub](https://img.shields.io/pub/v/biometric_storage?color=green)](https://pub.dev/packages/biometric_storage/)

Encrypted file store, **optionally** secured by biometric lock 
for Android, iOS, MacOS and partial support for Linux, Windows and Web. 

Meant as a way to store small data in a hardware encrypted fashion. E.g. to 
store passwords, secret keys, etc. but not massive amounts
of data.

* Android: Uses androidx with KeyStore.
* iOS and MacOS: LocalAuthentication with KeyChain.
* Linux: Stores values in Keyring using libsecret. (No biometric authentication support).
* Windows: Uses [wincreds.h to store into read/write into credential store](https://docs.microsoft.com/en-us/windows/win32/api/wincred/).
* Web: **Warning** Uses unauthenticated, **unencrypted** storage in localStorage.
  If you have a better idea for secure storage on web platform, [please open an Issue](https://github.com/authpass/biometric_storage/issues).

Check out [AuthPass Password Manager](https://authpass.app/) for a app which 
makes heavy use of this plugin.

## Getting Started

### Installation

#### Android

Always required:

* API Level >= 23 (`android/app/build.gradle` `minSdkVersion 23`)

**Required only if you actually prompt for authentication**, that is, if any
storage uses the default `authenticationRequired: true`. Storage created with
`authenticationRequired: false` never shows a `BiometricPrompt`, so neither of
the following applies to it:

* **MainActivity must extend `FlutterFragmentActivity`.** `BiometricPrompt`
  needs a `FragmentActivity` to host its dialog. If the plugin is attached to a
  plain `FlutterActivity` it logs an error and every authenticated read or write
  fails with `AuthError:Failed` — unauthenticated storage keeps working.

* **The activity theme must descend from `Theme.AppCompat`** — but only for
  devices where `androidx.biometric` falls back to drawing its own fingerprint
  dialog, which it builds with `androidx.appcompat.app.AlertDialog`. That
  fallback is used **below API 28**, on API 28 devices without a fingerprint
  sensor, and on a short manufacturer allow-list where a crypto object forces
  it. From API 28 onwards the system `BiometricPrompt` is used and the theme
  does not matter.

  If you do need it:

  **android/app/src/main/AndroidManifest.xml**:
  ```xml
  <activity
      android:name=".MainActivity"
      android:launchMode="singleTop"
      android:theme="@style/LaunchTheme">
      [...]
      <meta-data
            android:name="io.flutter.embedding.android.NormalTheme"
            android:resource="@style/NormalTheme"
            />
  </activity>
  ```

  **android/app/src/main/res/values/styles.xml**:
  ```xml
  <resources>
    <style name="LaunchTheme" parent="Theme.AppCompat.NoActionBar">
      ...
    </style>
    <style name="NormalTheme" parent="Theme.AppCompat.NoActionBar">
      ...
    </style>
  </resources>
  ```

##### Resources

* https://developer.android.com/topic/security/data
* https://developer.android.com/topic/security/best-practices

#### iOS

https://developer.apple.com/documentation/localauthentication/logging_a_user_into_your_app_with_face_id_or_touch_id

* include the NSFaceIDUsageDescription key in your app’s Info.plist file
* Deployment target >= iOS 13 (below whatever Flutter itself requires, so in
  practice this never binds).

**Known Issue**: since iOS 15 the simulator seem to no longer support local authentication:
    https://developer.apple.com/forums/thread/685773

#### Mac OS

* include the NSFaceIDUsageDescription key in your app’s Info.plist file
* enable keychain sharing and signing. (not sure why this is required. but without it
    You will probably see an error like: 
    > SecurityError, Error while writing data: -34018: A required entitlement isn't present.
* Deployment target >= macOS 10.15.

#### Swift Package Manager (iOS and Mac OS)

The iOS and macOS implementations ship both a `Package.swift` and a podspec, so
they work with either dependency manager. Adding this plugin to an app that has
[migrated to Swift Package Manager](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)
does **not** bring CocoaPods back — no `Podfile` is generated.

### Usage

> You basically only need 4 methods.

1. Check whether biometric authentication is supported by the device

```dart
  final response = await BiometricStorage().canAuthenticate()
  if (response != CanAuthenticateResponse.success) {
    // panic..
  }
```

2. Create the access object

```dart
  final storageFile = await BiometricStorage().getStorage('mystorage');
```

3. Read data

```dart
  final data = await storageFile.read();
```

4. Write data

```dart
  final myNewData = 'Hello World';
  await storageFile.write(myNewData);
```

> Storing without a biometric prompt — for a value a background task has to be
> able to refresh, for example — is `authenticationRequired: false`. The value is
> still encrypted at rest; it is simply not gated behind an authentication.
>
> ```dart
>   final storageFile = await BiometricStorage().getStorage(
>     'mystorage',
>     options: StorageFileInitOptions(authenticationRequired: false),
>   );
> ```

See also the API documentation: https://pub.dev/documentation/biometric_storage/latest/biometric_storage/BiometricStorageFile-class.html#instance-methods
