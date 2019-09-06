# biometric_storage

[![Pub](https://img.shields.io/pub/v/biometric_storage?color=green)](https://pub.dev/packages/biometric_storage/versions/0.1.0)

Encrypted file store secured by biometric lock. Meant as a way to store small data in a
hardware encrypted fashion. E.g. to store passwords, secret keys, etc. but not massive amounts
of data.

On android uses androidx uses KeyStore and on iOS LocalAuthentication with KeyChain.

## Getting Started

### Android
* Requirements:
  * Android: API Level >= 23
  * MainActivity must extend FlutterFragmentActivity

### iOS

https://developer.apple.com/documentation/localauthentication/logging_a_user_into_your_app_with_face_id_or_touch_id

* include the NSFaceIDUsageDescription key in your app’s Info.plist file
* Requires at least iOS 9

## Resources

* https://developer.android.com/topic/security/data
* https://developer.android.com/topic/security/best-practices

