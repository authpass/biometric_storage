## 6.0.0-dev.10

* android: `delete()` now removes the keystore key even when there is nothing
  stored. It ran `deleteFile()` only for a store that had a file, and the key
  is minted in `cipherForEncrypt` *before* the prompt — so a first write the
  user cancelled left a key with no file, which `delete()` then skipped. The
  key is what carries a store's authentication parameters, and those are fixed
  at creation, so a key left behind silently kept them in force for every later
  write. It also made "call `delete()` first" an unreliable remedy for the
  documentation item below.

  The native reply now answers whether there was a stored value, asked before
  the removal rather than taken from it, and that is a small change in two
  cases: a store holding only a set-aside or partial file, and one whose file
  delete fails, both of which used to report `false` and now report `true`.
  `BiometricStorageFile.delete()` is `Future<void>`, so no app sees either
  answer; `MethodChannelBiometricStorage.delete` returns it.
* Document what `dispose()` does **not** reconfigure. 6.0.0-dev.9 offered
  "changing an authentication validity duration" as its motivating example, and
  on Android that is the one case it cannot do: a keystore key's authentication
  parameters are fixed when the key is created, and nothing recreates a key
  that already exists, so neither `androidAuthenticationValidityDuration` nor
  `authenticationRequired` in the options a later `getStorage` receives has any
  effect on a store whose key has been created — and a cancelled first write
  has created one.

  Changing the duration between a value and `null` is worse than ineffective,
  because the plugin then takes the path the key was not minted for. `null` to
  a value fails every read and write. The other direction fails whenever the
  window has closed and succeeds while it happens to be open, so the store
  misbehaves intermittently. Turning `authenticationRequired` from `false` to
  `true` is its own version: a prompt appears over a key that requires no
  authentication, and so gates nothing.

  On iOS and macOS only the two reuse durations reconfigure, because they are
  the only options that are pure in-memory state — disposing drops the cached
  `LAContext`, ending a `darwinTouchIDAuthenticationForceReuseContextDuration`
  in progress. `authenticationRequired`, `darwinBiometricOnly` and
  `darwinKeychainAccessGroup` all travel in the keychain query, so none of them
  is reconfigured either: changing the access group, which is part of an item's
  primary key, makes the item unfindable and the store reads as empty, and
  changing the other two is expected to surface as a failed read or write. dev.9
  said "a fresh `StorageFileInitOptions`" without any of these qualifications.

  No behavior changed in these paths; dev.9 behaved this way too and said
  otherwise.

  Reproduced on an emulator rather than argued from the code, by
  `example/integration_test_manual/android_keystore_test.dart`, which needs an
  enrolled fingerprint and something answering the prompts and so is skipped
  off Android. What it exercises is `read()` after a reconfiguration: both
  failing directions surface as `PlatformException(Unexpected Error)`, and —
  the outcome that mattered — neither returns `null`. A `null` would have meant
  `readFile` moved the file aside as unreadable, which is data loss wearing the
  face of an empty store; it does not. The window-open case returns the value,
  which is what makes that direction intermittent rather than broken.

  Writes are not covered by that run, and neither is reading the original value
  back after restoring the original options; both follow from the same code
  paths, but they follow by reading rather than by observation.

  Whether `init` should detect the mismatch — comparing
  `KeyInfo.getUserAuthenticationValidityDurationSeconds()` against the options
  it was handed — and raise a named error instead of `Unexpected Error` is a
  separate change.
* README: the **envelope pattern**, for an authentication the OS cannot carry
  over from a previous one. A validity window cannot be closed early — Android
  exposes no way to revoke an authentication, and an unlock by PIN, pattern,
  password or strong biometric renews it — so the answer is not to open one: a
  per-use store holds a random data key, and a second store with
  `authenticationRequired: false` holds the secret encrypted under it. Every
  login is then a keystore- or keychain-enforced prompt with no window, while
  rotating the secret needs only the key already in memory and raises no prompt
  at all. This is the standing answer to #129, #108 and #112.

  **It is a trade, not a free win, and the README says so.** The gate key is
  biometric-only, so a new enrollment — or removing the last one — invalidates it and
  the sealed secret becomes undecryptable — a failure the windowed store it
  replaces mostly does not have, since a key that also allows the device
  credential survives enrollment changes. Fine for a refresh token, wrong for a
  secret that cannot be regenerated. The pattern is also Android and darwin
  only: on web both stores are unencrypted `localStorage`, which puts the data
  key beside the ciphertext it protects.

  `example/lib/envelope_example.dart` implements it, binding the store name in
  as associated data, and the integration suite exercises it against the real
  keystore, keychain and libsecret — including that a tampered token is
  refused, and that a blob sealed for one store will not open as another, which
  are what hold up the README's instruction to use an authenticated cipher.
  Only the Linux run is in CI. Not covered at all: under test the gate is
  unauthenticated, because no CI runner can perform a biometric gesture, so the
  prompt itself is the platform's behavior rather than something this
  repository proves.

## 6.0.0-dev.9

* `BiometricStorageFile.dispose()` forgets a store's initialization without
  touching its content, so the next `getStorage` applies a fresh
  `StorageFileInitOptions`. Until now the options for a name were resolved once
  and then ignored for the lifetime of the process, so a store could not be
  reconfigured at runtime — changing, say, an authentication validity duration
  meant restarting the app. Thanks to @luckyrat, who identified the gap and
  proposed an API for it in #138 (see also #75 and #137); this implements the
  standalone `dispose()` rather than that PR's delete-coupled form, so
  reconfiguring no longer costs you the stored value. Call `delete()` first if
  you want both.

  Returns `true` when there was an initialization to forget and `false` when
  there was not, so disposing twice is safe. Android previously raised
  `NoSuchStorage` on a repeat, the only backend where that was an error.

  The method was reachable natively before this, and did not work: Linux had no
  handler at all, so the call reached Dart as a `MissingPluginException`, and
  iOS/macOS answered `true` from a no-op that never cleared the entry — so
  re-initializing silently kept the original configuration while reporting
  success at every step. Both are fixed, and the store's content is deliberately
  left alone on every platform.

  A disposed `BiometricStorageFile` now refuses `read`, `write` and `delete`
  with a `StateError` — not `dispose` itself, which stays idempotent. The
  backends do not agree on their own: Android and iOS/macOS resolve those calls
  against a registry and fail once the entry is gone, while Linux, Windows and
  web answer from the name alone and would carry on working. The guard sits in
  Dart so the answer is the same everywhere, rather than being a mistake you
  make on one platform and discover on another.

* **Breaking for platform implementations only.** `dispose` is a new member on
  the `BiometricStorage` platform interface, so a third-party implementation
  that extends it must add one. No change for callers of the package.

## 6.0.0-dev.8

Four conditions a caller has to tell apart, and until now could not. Thanks
@olehmarch-bro for the implementation (#158).

* `AuthExceptionCode.lockout` and `.lockoutPermanent`. A biometric lockout is
  recoverable — by waiting, or by entering the device credential — but Android
  reported both `ERROR_LOCKOUT` and `ERROR_LOCKOUT_PERMANENT` as
  `AuthExceptionCode.unknown`, which is the code an app has no response to but
  "something went wrong". This is the split 6.0.0-dev.4 promised when it
  documented `AuthExceptionCode` as an open enum.
* iOS/macOS report a biometric lockout as `.lockoutPermanent` too. The Keychain
  gives no status of its own for it, so the plugin asks LocalAuthentication
  (`canEvaluatePolicy`, synchronous and without UI) once a call has failed, and
  then also sees a lockout that the failing attempt is what caused. Apple has a
  single lockout state and it never clears by waiting, so it maps to the
  permanent member; a store with `darwinBiometricOnly: false` never reports it,
  since its items stay reachable through the passcode.
* **Breaking**: android reports `AuthExceptionCode.keyInvalidated` from `read()`
  when enrolled biometrics changed and took the store's key with them.
  Previously the plugin deleted the dead key and file and read on, returning
  `null` — the same answer as an empty store, so an app could not tell a secret
  the user never set from one the OS had just destroyed. Those two want
  different handling, and the second is the one worth telling the user about.
  A caller that treats `null` as "nothing stored" now has an exception to catch
  on that path. It arrives once per invalidation: the dead key and file are
  removed before it is raised, so the read after it returns `null` like any
  other read of an empty store.

  `write()` is unchanged and still recovers silently: a write has lost nothing
  it was not about to replace, and failing it would hand every caller an error
  whose only sensible recovery is to write the same content again.

  Certain when reported, and only reported where it is certain. Android raises
  `KeyPermanentlyInvalidatedException`, which is unambiguous, for a store that
  authenticates per use. A store with `androidAuthenticationValidityDuration`
  holds a key bound to the device credential as well, which an enrollment
  change does not invalidate.
* **Breaking**: iOS/macOS translate the Keychain's `errSecAuthFailed` into
  `AuthException(AuthExceptionCode.authFailed)` instead of leaving it as
  `PlatformException(SecurityError, …)`. This is what #128 asked for: matching
  the English in `-25293: The user name or passphrase you entered is not
  correct` was the only way to recognise a failed authentication. Catch
  `AuthException` where you caught a `PlatformException` for it.

  `authFailed`, deliberately, and not `keyInvalidated`. The honest answer on
  this platform is that the plugin does not know which it has: Apple reports a
  user who looked away (#80), a device whose sensor it will not use (#101), and
  an access control that can never be satisfied again (#128) as the same
  `errSecAuthFailed`. Reporting all of it as invalidation would tell an app its
  data was gone every time a prompt was failed — and an app that believes it
  deletes a secret it could still have read. Ask the user to authenticate
  again; that answer is right for all three.

## 6.0.0-dev.7

* android: a stored file that can no longer be decrypted — its keystore key
  is gone, as after a backup restored onto another device, or the file is
  corrupt or empty — reads as absent and is moved aside to `.unreadable`,
  instead of failing every read. Reading never creates a key.
* android: writes are synced and renamed into place, so a killed process or a
  power loss cannot leave a corrupt file.

## 6.0.0-dev.6

* android: storage with `authenticationRequired: false` reads, writes and
  deletes on the plugin's worker thread instead of the main thread, where its
  keystore calls dropped Flutter frames.
* android: a store with `androidAuthenticationValidityDuration` also reads and
  writes on the worker thread while its validity window is open.

## 6.0.0-dev.5

* android: fix `minifyReleaseWithR8` failing in every app that ships a release
  build. The plugin depended on `kotlin-logging`, which names every backend it
  can bind to, so R8 walked references to `ch.qos.logback.*` classes that were
  genuinely absent and refused to complete:

      Missing class ch.qos.logback.classic.Logger (referenced from: ...)
      Execution failed for task ':app:minifyReleaseWithR8'

  Minification runs in release and nowhere else, so nothing anyone does while
  developing reaches it — `flutter run`, `flutter test` and an emulator check
  all build debug or profile. The first thing to hit it is an attempt to ship
  to Play, which is the worst possible moment. Present in 6.0.0-dev.4.

  Fixed by removing the dependencies, so nothing needs suppressing. If you
  added `-dontwarn ch.qos.logback.**` to your own `proguard-rules.pro` to get
  6.0.0-dev.4 to build, you can drop it.
* android: the plugin's logging now actually produces output. `slf4j-api` and
  `kotlin-logging` are both facades and neither had a provider, so SLF4J
  reported `No SLF4J providers were found` once and discarded every call after
  that. Unless a consuming app happened to ship a binding of its own, this
  package has logged nothing at all on Android. It now writes to
  `android.util.Log` under the tag `BiometricStorage`, and both dependencies
  are dropped.

  Debug builds log everything. Release builds stay silent until asked:

      adb shell setprop log.tag.BiometricStorage VERBOSE
* android: `BiometricStorageLogging` lets an app choose the level and the
  destination. `level` overrides the default above — set it to `Log.VERBOSE` to
  keep verbose logging in a release build without depending on a device
  property. `sink` hands every record to your own logging framework instead of
  `android.util.Log`, with the `Throwable` passed separately rather than
  flattened into the message, so you can report the real exception:

      BiometricStorageLogging.sink =
          BiometricStorageLogging.Sink { priority, tag, message, throwable ->
              // forward to slf4j, Timber, a file appender, a crash reporter
          }

  Installing a sink turns every level on unless `level` says otherwise. Both
  are optional and the default is unchanged. See the README for the full
  slf4j example.
## 6.0.0-dev.4

* `BiometricStorageException` carries a `code`. It previously held only a
  message, so telling "you called `getStorage` twice" from "the credential store
  failed" meant matching English text — and 6.0.0-dev.2 took the number of
  places it is raised from one to six. `BiometricStorageExceptionCode` is
  `alreadyInitialized`, `storageFailure` or `unknown`, and every site that
  raises `BiometricStorageException` classifies itself, including the
  `AlreadyInitialized` the method-channel platforms raise. Additive: the
  positional constructor is unchanged and defaults to `unknown`, so existing
  `catch` blocks keep working. Switch over it with a `default` — members may be
  added in a minor release.

  Note the boundary: `storageFailure` today reaches only Windows. A failing
  keychain, keystore or libsecret still surfaces as a raw `PlatformException`
  (`SecurityError`, `Unexpected Error` and `Security Access Error` among
  others), because those are not translated. So a single cross-platform "the store failed" branch is
  not yet writable; that is a later change.
* `AuthExceptionCode` is documented as an open enum, matching the above. No
  behaviour change — but it means the members that Android currently collapses
  into `unknown`, lockout among them, can be split out in a minor release rather
  than waiting for 7.0.

## 6.0.0-dev.3

* linux: fix a memory leak on every method call.
  `fl_method_success_response_new` takes its own reference to the `FlValue`
  rather than adopting the caller's, so the inline
  `fl_method_success_response_new(fl_value_new_*(…))` form leaked one value per
  call. Present since the Linux implementation landed in 3.0.0. The worst of the six is
  `read()`, which leaked a **plaintext-secret-bearing allocation on every
  successful read** — so a long-running app both grew without bound and kept
  copies of every secret it had read alive in the process.
* **Breaking**: linux honours `forceInit`, closing the gap 6.0.0-dev.2 documented.
  It throws `AlreadyInitialized`, which the Dart layer already translates to
  `BiometricStorageException`, so the exception is the same one every other
  platform raises. A repeat `getStorage()` without the flag now reports `false`
  rather than `true` — libsecret keeps no handle, so the names handed out during
  a run are tracked by the plugin instance and reset when it is disposed.

## 6.0.0-dev.2

Six pre-existing bugs, all found while reviewing 6.0.0-dev.1 and none introduced
by it.

* android: an authentication requested while the activity cannot host a dialog
  no longer hangs forever. `androidx.biometric` refuses to start after
  `onSaveInstanceState` — logging `Unable to start authentication` — and returns
  without invoking any callback, so the pending Flutter result never completed.
  The state is checked up front and reported as
  `AuthException(AuthExceptionCode.unknown)` instead. Reachable whenever the app
  is backgrounded, independently of the configuration-change bug below.
* android: the plugin kept using a destroyed `Activity` after a configuration
  change. `onReattachedToActivityForConfigChanges` and
  `onDetachedFromActivityForConfigChanges` were both empty, so after a rotation
  every authenticated read or write handed `BiometricPrompt` a dead
  `FragmentActivity`. `ActivityAware` documents that the old reference must be
  cleared and the new binding adopted; now both happen.
* android: a storage-not-initialized error delivered its message as the
  `PlatformException.code` — the field callers match on. The code is now
  `NotInitialized`.
* iOS/macOS: `init` replied twice when an argument was missing or mistyped, so
  the caller saw the error and then a success. The success reply now only
  happens on the success path.
* **Breaking**: iOS/macOS `canAuthenticate()` reports an unrecognised `LAError`
  as `CanAuthenticateResponse.statusUnknown` rather than `unsupported`, matching
  Android. `unsupported` means "the plugin does not support this platform", so a
  recoverable `biometryLockout` was telling callers to give up entirely. Callers
  that treat `statusUnknown` as usable will now attempt authentication where
  they previously did not.
* **Breaking**: iOS/macOS, a repeat `getStorage()` for a name that is already
  open no longer rebuilds the store. It used to replace it outright, which threw
  away the cached `LAContext` — so any
  `darwinTouchIDAuthenticationForceReuseContextDuration` in progress — and
  quietly adopted whatever options the second call passed. The first call now
  wins, as on Android. If you relied on re-initializing to change options, give
  each set of options its own store name, or restart — there is no API to close
  a store, so none can be reopened differently within a run. Passing different
  options to a repeat call was never reported back to Dart, and now definitively
  does nothing.
* **Breaking**: `forceInit` now does what it documents on Windows, web, iOS and
  macOS. It was implemented on Android only; the others accepted the flag and
  dropped it. It throws `BiometricStorageException` on every platform — the
  `PlatformException(code: 'AlreadyInitialized')` that the method-channel
  platforms raise is translated, so one catch clause covers all of them.
  **Linux still ignores the flag**: its `init` keeps no per-store state at all,
  so implementing it there is a separate change.
* **Breaking**: windows `read()` and `delete()` throw `BiometricStorageException`
  when the credential store fails, instead of returning `null` and `false`.
  Those values still mean "no value stored" and "there was nothing to delete" —
  previously they doubled as the answer for a failing store, so a failure read
  as data loss.
* iOS/macOS: `canAuthenticate()` names `biometryLockout` explicitly rather than
  letting it fall through the unmapped-code path, and the nil-error branch
  reports `statusUnknown` too rather than `unsupported`.

## 6.0.0-dev.1

**Breaking**: requires Dart 3.10 / Flutter 3.44 or newer.

* Support `package:win32` 6.x, and drop 5.x and older. Every 5.x release of this
  plugin pinned `win32 >=2.0.0 <6.0.0`, which made it unresolvable alongside
  `package_info_plus >=10.1.0` and anything else on win32 6. The Windows
  implementation is compiled on every `dart.library.io` platform, so win32 6
  removing `TEXT()` also broke iOS and macOS builds — the test suite now imports
  the public barrel so `flutter test` compiles the win32 bindings on any host.
* windows: writing an empty value no longer throws.
* windows: fix a use-after-free in `read()`. `CredentialBlob.asTypedList()` is a
  view onto memory owned by the credential, and it was decoded *after* `CredFree`
  had released it. The bytes are now copied out first. Present since 1.1.0,
  where a9e3944 moved the `CredFree` call in between the two.
* windows: the bindings now have runtime coverage, not just compile coverage —
  `test/biometric_storage_win32_test.dart` exercises write/read/delete against
  the real credential store, and runs on the Windows CI job.
* iOS/macOS: Swift Package Manager support. Adding this plugin to an app that has
  migrated to SwiftPM no longer regenerates a `Podfile`. CocoaPods keeps working;
  both a `Package.swift` and a podspec are shipped.
* iOS/macOS: the Swift sources moved to `darwin/` and are shared through
  `sharedDarwinSource`, replacing the symlink from `ios/Classes`. The macOS
  plugin class is now `BiometricStoragePlugin` (was
  `BiometricStorageMacOSPlugin`) and the Objective-C shim on iOS is gone. Neither
  is referenced from Dart, so this is only visible in a hand-written registrant.
* android: AGP 8.13, Kotlin 2.2, compileSdk 36, `androidx.biometric`
  1.4.0-alpha05, `core-ktx` 1.18.0, `fragment-ktx` 1.9.0, slf4j 2.0.18 and
  kotlin-logging 8. The plugin no longer applies the Kotlin Gradle Plugin itself
  — AGP 9 warns about that and future Flutter releases reject it.
* android: `canAuthenticate()` no longer throws on a status code the plugin does
  not know about — Android 16 added `BIOMETRIC_ERROR_NOT_ENABLED_FOR_APPS` (21)
  and every call blew up. Unmapped codes are reported as
  `CanAuthenticateResponse.statusUnknown` and logged.
  https://github.com/authpass/biometric_storage/issues/148
* android: the plugin no longer calls `jvmToolchain`, which failed to resolve in
  some consumer builds. https://github.com/authpass/biometric_storage/issues/107
* Document the Android `FlutterFragmentActivity` and `Theme.AppCompat`
  requirements as what they actually are: both only apply to storage that shows
  an authentication prompt, and the theme only where `androidx.biometric` falls
  back to its own dialog, which is below API 28 rather than below API 29.
* web: the package is now WebAssembly-ready. `lib/src/biometric_storage.dart`
  imported `dart:io` unconditionally for `Platform`, which marked the whole
  package wasm-incompatible; the host OS now comes through a conditional import,
  with `dart:io` still doing the work everywhere it exists. No behaviour change
  on any platform. https://github.com/authpass/biometric_storage/issues/145
* iOS/macOS: the prompt strings (`IosPromptInfo.saveTitle` / `accessTitle`) now
  travel on the `LAContext` as `localizedReason` instead of through
  `kSecUseOperationPrompt`, deprecated since iOS 14 / macOS 11. Same prompts, no
  deprecation warnings on build.

## 5.2.0-dev.1

* iOS/macOS: `StorageFileInitOptions.darwinKeychainAccessGroup` to store items
  in a shared keychain access group (`kSecAttrAccessGroup`), so an app
  extension can read them. Note that the access group is part of an item's
  identity — existing items are not migrated automatically.

## 5.1.1-dev.2

* Improve `canAuthenticate` to include `InitOptions` to decide for which authenticaiton type to check.

## 5.1.0

* Fix typo in Flutter to iOS reuse duration parameter name @jefmathiot #125

## 5.1.0-rc.5

* upgrade dependency to web 1.0

## 5.1.0-rc.4

* enable building on jdk 17 and up https://github.com/authpass/biometric_storage/issues/117 thanks @connyduck

## 5.1.0-rc.3

* Split Split authenticationValidityDurationSeconds between android and iOS
  * `darwinTouchIDAuthenticationForceReuseContextDuration`: Basically the equivalent to `androidAuthenticationValidityDuration`
  * `darwinTouchIDAuthenticationAllowableReuseDuration`
* android: return correct code if no biometric is enrolled #115 @ThomasLamprecht
* web: migrate from dart:html to package:web (for wasm support).

## 5.0.1

* Add option for iOS/MacOS to allow non-biometric authentication (`darwinBiometricOnly`) #101
  * Improve [canAuthenticate] to differentiate between no available biometry and no available 
    user code.
* Bump dart sdk requirement to `3.2`.

## 5.0.0+4

* Add topics to pubspec.yaml

## 5.0.0+3

* Android: Upgrade AGP, fix building with AGP 8
* Android: Depend on slf4j-api.

## 5.0.0+1

* MacOS: fix building on MacOS

## 5.0.0

* Allow overriding of `promptInfo` during `read`/`write` thanks @luckyrat
* Android: (POTENTIALLY BREAKING): Completely removed deprecated old file backend 
  based on `androidx.security`. This was deprecated since version 3.0.0 and users 
  should have been migrated on every read or write. (this is only internally, does not change
  anything of the API).
* Update dependencies.

## 4.1.3

* iOS/MacOS: Reuse LAContext to make `touchIDAuthenticationAllowableReuseDuration` work.
    thanks @radvansky-tomas

## 4.1.2

* Android: Move File I/O and encryption to background thread. (Previously used UI Thread)
     https://github.com/authpass/biometric_storage/pull/64   

## 4.1.1

* Fix building on all platforms, add github actions to test building.

## 4.1.0

* Android: Remove Moshi dependency altogether. #53

## 4.0.1

* Update to Moshi 1.13 for Kotlin 1.6.0 compatibility. #53 

## 4.0.0

* Fixed compile errors with Flutter >= 2.8.0 (Compatible with Flutter 2.5). #47 fix #42

## 3.0.1

* Android: Validate options on `int`
  When `authenticationValidityDurationSeconds == -1`, then `androidBiometricOnly` must be `true`
* Android: if `authenticationValidityDurationSeconds` is `> 0` only show authentication prompt when
  necessary. (It will simply try to use the key, and show the auth prompt only when a
  `UserNotAuthenticatedException` is thrown).
* Android: When biometric key is invalidated (e.g. because biometric security is changed on the 
  device), we simply delete the old key and data! (KeyPermanentlyInvalidatedException)

## 3.0.0

* Stable Release 🥳
* **Please check below for breaking changes in the `-rc` releases.

## 3.0.0-rc.12

* Android: Fix a few bugs with `authenticationValidityDurationSeconds` == -1
* iOS/MacOS: Don't set timeout for `authenticationValidityDurationSeconds` == -1
* iOS/MacOS: Don't raise an error on `delete` if item was not found.
* Android: Fix user cancel code. 
  (Previously an `unknown` exception was thrown instead of `userCanceled`)
* Android: Ignore `androidBiometricOnly` prior to Android R (30).
* Introduce `AuthExceptionCode.canceled`

## 3.0.0-rc.7

* **Breaking Change**: `authenticationValidityDurationSeconds` is now `-1` by default, which was
  not supported before hand. If you need backward compatibility, make sure to override this value
  to the previous value of `10`.
* **Breaking Change**: No more support for Android v1 Plugin registration.
* **Breaking Change**: No longer using androidx.security, but instead handle encryption
  directly. Temporarily there is a fallback to read old content. This requires either reencrypting
  everything, or old data will no longer be readable.
  
  1. This should fix a lot of errors.
  2. This now finally also allows using `authenticationValidityDurationSeconds` = -1.
  3. `BIOMETRIC_WEAK` is no longer used, only `BIOMETRIC_STRONG`.
* Don't ask for authentication for delete.

## 3.0.0-rc.5

* **Breaking Change**: due to the introduction of iOS prompt info there is now a wrapper object
  `PromptInfo` which contains `AndroidPromptInfo` and `IosPromptInfo`.
* Android: Add support for local (non-biometric) storage (#28, thanks @killalad)
* Android: Update all gradle dependencies, removed gradle-wrapper from plugin folder.
* iOS: Add support for customizing prompt strings.
* MacOS: Add support for customizing prompt strings.

## 2.0.3

* Android
  * compatibility with kotlin 1.5.20
  * Remove jcenter() references.
  * androidx.core:core:1.3.2 to 1.6.0
  * moshi from 1.11.0 to 1.12.0 (this is the kotlin 1.5.20 compatibility problem)

## 2.0.2

* Android upgrade dependencies:
  * androidx.security:security-crypto from 1.1.0-alpha02 to 1.1.0-alpha03
  * androidx.biometric:biometric from 1.1.0-beta01 to 1.2.0-alpha03
  * Update README to clarify minSdkVersion and kotlin version

## 2.0.1

* Handle android `BIOMETRIC_STATUS_UNKNOWN` response on older devices
  (Android 9/API 28(?))

## 2.0.0

* Null safety stable release.

## 2.0.0-nullsafety.1

* Null safety migration.

## 1.1.0+1

* upgrade android moshi dependency.

## 1.1.0

* Upgrade to latest Android dependencies (gradle plugin, androidx.*, gradle plugin)
  * [androidx.security:security-crypto](https://developer.android.com/jetpack/androidx/releases/security) 1.0.0-rc02 to 1.1.0-alpha02
  * [androidx.biometric:biometric](https://developer.android.com/jetpack/androidx/releases/biometric) 1.0.1 to 1.1.0-beta01

## 1.0.1+5

* Workaround to not load win32 when compiling for web.

## 1.0.1+4

* Fix windows plugin config.

## 1.0.1+1

* Support for web support: **Warning**: Unencrypted - stores into local storage on web!
* Updated README to add details about windows.

## 1.0.0

* Windows: Initial support for windows. only unauthenticated storage in Credential Manager.

## 0.4.1

* Linux: Improve snap compatibility by detecting AppArmor error to prompt users to connect
         to password-manager-service.

## 0.4.0

* Linux: Initial support for Linux - only unauthenticated storage in Keyring.

## 0.3.4+6

* Android: androidx.security 1.0.0-rc02 needs another proguard rule.
  https://github.com/google/tink/issues/361

## 0.3.4+5

* Android: Upgrade to androidx.security 1.0.0-rc02 which should fix protobuf incompatibilities
  #6 https://developer.android.com/jetpack/androidx/releases/security#security-crypto-1.0.0-rc02

## 0.3.4+4

* Android: fix PromptInfo deserialization with minification.
* Android: add proguard setting to fix protobuf exceptions.

## 0.3.4+2

* Android: updated dependencies to androidx.security, biometric, gradle tools.

## 0.3.4+1

* Android: on error send stack trace to flutter. also fixed a couple of warnings.

## 0.3.4

* Android: allow customization of the PromptInfo (labels, buttons, etc).
  @patrickhammond

## 0.3.3

* ios: added swift 5 dependency to podspec to fix compile errors
       https://github.com/authpass/biometric_storage/issues/3

## 0.3.2

* android: fingerprint failures don't cancel the dialog, so don't trigger error callback. #2
  (fixes crash)

## 0.3.1

* Use android v2 plugin API.

## 0.3.0-beta.2

* Use new plugin format for Mac OS format. Not compatible with flutter 1.9.x

## 0.2.2+2

* Use legacy plugin platforms structure to be compatible with flutter stable.

## 0.2.2+1

* fixed home page link, updated example README. 

## 0.2.2

* Android: Use codegen instead of reflection for json serialization.
  (Fixes bug that options aren't assed in correctly due to minification)

## 0.2.1

* Android: Fix for having multiple files with different configurations.
* Correctly handle UserCanceled events.
* Define correct default values on dart side (10 seconds validity timeout).

## 0.2.0

* MacOS Support

## 0.1.0

* iOS Support
* Support for non-authenticated storage (ie. secure/encrypted storage, 
  without extra biometric authenticatiton prompts)
* delete()'ing files.

## 0.0.1 - Initial release

* Android Support.
