# No idea why this is required here, and is not automatically applied to protobuf dependency.
# (to test: use release mode on a device and write to e.g. unauthenticated storage)
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
  <fields>;
}
