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
