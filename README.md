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
* Requirements:
  * Android: API Level >= 23 (android/app/build.gradle `minSdkVersion 23`)
  * Make sure to use the latest kotlin version: 
    * `android/build.gradle`: `ext.kotlin_version = '1.4.31'`
  * MainActivity must extend FlutterFragmentActivity
  * Theme for the main activity must use `Theme.AppCompat` thme.
    (Otherwise there will be crases on Android < 29)
    For example: 
    
    **AndroidManifest.xml**:
    ```xml
    <activity
    android:name=".MainActivity"
    android:launchMode="singleTop"
    android:theme="@style/LaunchTheme"
    ```

    **xml/styles.xml**:
    ```xml
        <style name="LaunchTheme" parent="Theme.AppCompat.NoActionBar">
        <!-- Show a splash screen on the activity. Automatically removed when
             Flutter draws its first frame -->
        <item name="android:windowBackground">@drawable/launch_background</item>

        <item name="android:windowNoTitle">true</item>
        <item name="android:windowActionBar">false</item>
        <item name="android:windowFullscreen">true</item>
        <item name="android:windowContentOverlay">@null</item>
    </style>
    ```

##### Resources

* https://developer.android.com/topic/security/data
* https://developer.android.com/topic/security/best-practices

#### iOS

https://developer.apple.com/documentation/localauthentication/logging_a_user_into_your_app_with_face_id_or_touch_id

* include the NSFaceIDUsageDescription key in your app’s Info.plist file
* Requires at least iOS 9

#### Mac OS

* include the NSFaceIDUsageDescription key in your app’s Info.plist file
* enable keychain sharing and signing. (not sure why this is required. but without it
    You will probably see an error like: 
    > SecurityError, Error while writing data: -34018: A required entitlement isn't present.
* Requires at least Mac OS 10.12

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
  final store = BiometricStorage().getStorage('mystorage');
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

See also the API documentation: https://pub.dev/documentation/biometric_storage/latest/biometric_storage/BiometricStorageFile-class.html#instance-methods
