# No idea why this is required here, and is not automatically applied to protobuf dependency.
# (to test: use release mode on a device and write to e.g. unauthenticated storage)
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
  <fields>;
}
# Required for androidx.security 1.0.0-rc02
# https://github.com/google/tink/issues/361
-keepclassmembers class * extends com.google.crypto.tink.shaded.protobuf.GeneratedMessageLite {
  <fields>;
}
