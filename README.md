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
* Windows: Uses [wincred.h to read/write into the credential store](https://docs.microsoft.com/en-us/windows/win32/api/wincred/).
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

##### Logging

The plugin writes to `android.util.Log` under the tag `BiometricStorage`. A
debug build logs everything; a release build logs nothing below INFO until you
ask for it:

```
adb shell setprop log.tag.BiometricStorage VERBOSE
```

That suits reading logs off a device. If your app collects its own — a file
appender, a crash reporter, slf4j, Timber — install a sink instead, from
`Application.onCreate` or your `FlutterActivity`, before the first call into
the plugin:

```kotlin
import android.util.Log
import design.codeux.biometric_storage.BiometricStorageLogging
import org.slf4j.LoggerFactory

BiometricStorageLogging.sink =
    BiometricStorageLogging.Sink { priority, tag, message, throwable ->
        val log = LoggerFactory.getLogger(tag)
        when (priority) {
            Log.VERBOSE -> log.trace(message, throwable)
            Log.DEBUG -> log.debug(message, throwable)
            Log.INFO -> log.info(message, throwable)
            Log.WARN -> log.warn(message, throwable)
            else -> log.error(message, throwable)
        }
    }
```

Installing a sink turns every level on, since it says something wants the
records. To decide the level yourself — including keeping verbose logging in a
release build without touching a device property — set it explicitly:

```kotlin
BiometricStorageLogging.level = Log.VERBOSE
```

`throwable` is passed separately rather than flattened into `message`, so you
can hand the real exception to whatever you report to. The sink is called on
whichever thread produced the record, so it must be safe to call from the main
thread and from a background executor.

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

**`IosPromptInfo.saveTitle` / `accessTitle` are invisible on Face ID devices.**
Face ID authenticates against a HUD that shows its glyph and the words "Face ID"
and nothing else, and the "not recognized" alert after a failure offers only
retry and cancel. The strings do reach the system — they are set as
`LAContext.localizedReason` — but iOS does not draw them. Touch ID devices and
macOS do show them, so they are still worth setting.

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

### What an authentication validity duration really means

`androidAuthenticationValidityDuration` opens a window during which the
keystore will use the key without another prompt. Three things about that
window are easy to get wrong, and all three are the platform's doing rather
than this plugin's:

* **It belongs to the user's last device authentication, not to your app.** Any
  unlock of the device renews it. A window you set to ten minutes can be
  renewed by the user unlocking their phone for something else entirely.
* **It cannot be closed early.** Android exposes no way to revoke an
  authentication. Nothing in this package — not `dispose()`, not a repeat
  `getStorage` — shortens a window that is already open.
* **It is fixed when the key is created.** A keystore key's authentication
  parameters are set at creation and nothing recreates a key that already
  exists, so passing a different duration later has no effect on a store that
  has been written. See `dispose()`'s documentation for what happens if you
  change it between a value and `null`.

So if what you need is an authentication that cannot be inherited from an
earlier one, do not set a duration. Use the pattern below.

### The envelope pattern

For: a prompt on every login, *and* the ability to rewrite the secret without
one. This is the standing answer to
[#129](https://github.com/authpass/biometric_storage/issues/129),
[#108](https://github.com/authpass/biometric_storage/issues/108) and
[#112](https://github.com/authpass/biometric_storage/issues/112), which all
arrive at a long validity duration and then run into the three points above.

Keep **two** stores instead of one:

* a **gate** that authenticates per use — `authenticationRequired: true`, no
  validity duration, no darwin reuse duration — holding a random data key;
* a **token** store with `authenticationRequired: false`, holding your secret
  encrypted by your app under that data key.

```dart
// Login: one prompt, for the gate.
final key = base64Decode((await gate.read())!);
final secret = await decrypt(await token.read(), key);   // your AEAD

// Rotate: no prompt at all — the key is already in memory.
await token.write(await encrypt(newSecret, key));

// Log out: forget the key. The next login must authenticate.
key.fillRange(0, key.length, 0);
```

What each half gives you, stated per platform rather than blended:

* **Android:** every gate read is a `BiometricPrompt` bound to a `CryptoObject`
  over a per-use key. The keystore enforces it, there is no window to leak, and
  a device unlock does not help an attacker.
* **iOS and macOS:** every gate read is a keychain access-control evaluation
  with a fresh `LAContext`.
* **The token store** is plain ciphertext on disk. Its confidentiality comes
  from the data key in the gate, so use an *authenticated* cipher (AES-GCM,
  ChaCha20-Poly1305) — the file is deliberately unprotected, and a
  non-authenticated cipher would leave it malleable.

Costs, honestly: your app owns one piece of cryptography, and the data key sits
in memory for the length of a session — which is where the plaintext secret
already sat. Migrating from a single store means reading the old secret,
writing both new stores, and only then deleting the old one, in that order, so
that a crash part-way leaves the old store intact.

A working implementation is in
[`example/lib/envelope_example.dart`](example/lib/envelope_example.dart), and
the integration suite exercises it against the real keystore, keychain and
libsecret. Note what that does not cover: under test the gate is
unauthenticated, because no CI runner can perform a biometric gesture, so the
prompt itself is the platform's behaviour rather than something this repository
proves.
