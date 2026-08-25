import 'dart:io' as io;

/// The host operating system, in the spelling `dart:io` uses:
/// `android`, `ios`, `macos`, `linux`, `windows`, `fuchsia`.
///
/// Deliberately `dart:io`'s own value rather than Flutter's
/// `defaultTargetPlatform`. The question this answers is "what OS is on the
/// other side of the method channel", and `defaultTargetPlatform` answers a
/// different one — it reports the platform Flutter is *emulating*, and an app
/// that sets `debugDefaultTargetPlatformOverride` would make us send iOS
/// arguments to an Android plugin.
///
/// See [platform_os_web.dart] for the counterpart the web build gets.
String get operatingSystem => io.Platform.operatingSystem;
