# biometric_storage

A Flutter plugin published to pub.dev: an encrypted key/value store, optionally
gated behind a biometric prompt. Android (KeyStore), iOS and macOS (Keychain +
LocalAuthentication), Linux (libsecret), Windows (wincred), Web (localStorage,
unencrypted — say so whenever it comes up).

The Dart surface is one class, `BiometricStorage`, in
[`lib/src/biometric_storage.dart`](lib/src/biometric_storage.dart). Everything
else is a platform implementation behind it.

## The one thing that is not obvious

**The Windows implementation is compiled on every platform that has
`dart.library.io`** — iOS, macOS, Android and Linux included. Two separate
mechanisms put it there, and removing either one does not help:

1. `lib/biometric_storage.dart` re-exports `src/biometric_storage_win32.dart`
   under `if (dart.library.io)`.
2. Flutter generates `.dart_tool/flutter_build/dart_plugin_registrant.dart` for
   *all* platforms at once, not per build target. On an iOS release build it
   still contains `import 'package:biometric_storage/biometric_storage.dart'`
   and a `Platform.isWindows` branch calling
   `Win32BiometricStoragePlugin.registerWith()`.

So a breaking change in `package:win32` breaks an **iOS** build. That is how
5.x ended up unusable: `win32` 6 removed `TEXT()`, and the error surfaced as a
failing `flutter test` on macOS.

Splitting Windows into a federated `biometric_storage_windows` package does
**not** fix this — the generated registrant would simply import that package
instead, on every platform. The defence is a compile, not a split:
`test/biometric_storage_test.dart` imports the public barrel rather than `src/`
precisely so that `flutter test` on any host compiles the win32 bindings. Do
not "tidy" that import.

Related: the `windows:` block in `pubspec.yaml` has no `dartFileName`, so the
registrant imports the barrel. `fileName:` is a **web-only** key — it sat under
`windows:` for years and was silently ignored.

## Layout

* `darwin/biometric_storage/Sources/biometric_storage/` — the iOS and macOS
  Swift sources, shared via `sharedDarwinSource: true` in `pubspec.yaml`.
  `BiometricStorageImpl.swift` is platform-agnostic; `BiometricStoragePlugin.swift`
  has the `#if os(iOS)` / `#if os(macOS)` split (the registrar's messenger is a
  method on iOS and a property on macOS).
* `darwin/biometric_storage/Package.swift` **and** `darwin/biometric_storage.podspec`
  describe the same sources. Both must be kept in step — CocoaPods stays
  supported until the registry goes read-only, and Flutter picks whichever the
  consuming app uses. `Package.swift` must keep its `FlutterFramework`
  dependency; without it Flutter warns on every build.
* `android/` — Kotlin, `design.codeux.biometric_storage`.
* `lib/src/biometric_storage_web.dart`, `linux/`, `lib/src/biometric_storage_win32.dart`.
* `example/` — the app the CI builds. Its own `flutter pub get` runs from
  `example/`, not the repository root.

## Commands

The whole test suite. Fast, and it is what catches a `package:win32` break.

```bash
flutter test
```

`--fatal-infos` is the point: without it the promotions in
`analysis_options.yaml` change nothing at the command line. It covers only the
package you stand in, so run it in `example/` too when that is what changed.

```bash
flutter analyze --fatal-infos
```

Run before committing.

```bash
dart format lib test example/lib
```

## Verifying

**A green analyze here is an answer about one resolution, not about consumers'.**
`flutter analyze` does flag an undefined win32 symbol in this package's own
sources — but it flags it against whatever `pubspec.yaml` resolves to, so while
the constraint said `win32 <6.0.0` it stayed green for a break that every app
resolving win32 6 would hit. What a version bump is actually verified by is a
build that finished, in an app that has the dependency in question.

**Gradle and Xcode are never covered by an analyze at all.** A toolchain or
androidx bump is proven by `flutter build` in `example/`, nothing less.

**Ask what would make this test red.** Green is information only if failure was
reachable. When you change something the win32 guard is supposed to catch,
reintroduce the break once and watch it fail before trusting the pass.

**A zero exit code is not evidence an edit landed.** Grep for the new state.

**Prove a plugin actually linked, rather than that the build was quiet.** A
plugin that fails to register produces a perfectly successful build. `nm` the
built binary for the plugin's symbols, or read the generated
`GeneratedPluginRegistrant.swift`.

**Resolution is proven in a consumer app, not here.** The interesting failures
are version conflicts with packages this repo does not depend on. Generate a
throwaway app in the scratchpad, point it at this checkout by path, add the
package that conflicts, and run `flutter pub get`.

## Android

**Never apply the Kotlin Gradle Plugin from `android/build.gradle`.** AGP 9
brings its own Kotlin support and Flutter warns that plugins applying KGP will
stop building; on AGP 8 Flutter's own Gradle plugin applies `kotlin-android` for
us. Either way it lands *after* this file is evaluated, so `kotlin { }` is not
available at the top level — configure the JVM target inside
`pluginManager.withPlugin('org.jetbrains.kotlin.android') { }`.

**`androidx.core` is capped by AGP, not by what is newest.** Each androidx AAR
declares a `minCompileSdk`, and AGP refuses a compileSdk above what it supports.
Read `META-INF/com/android/build/gradle/aar-metadata.properties` out of the AAR
before bumping, rather than discovering it from `checkDebugAarMetadata`.

**Keep the plugin's own AGP classpath behind the app template's.** A plugin that
declares AGP 9 forces every consumer onto Gradle 9. The example app is where the
newest toolchain gets exercised.

## Documentation

**Verify a requirement against the code before repeating it.** This package's
README drifted for years: it presented `FlutterFragmentActivity` and a
`Theme.AppCompat` theme as unconditional, when both only apply to storage that
actually shows a prompt — `withAuth` returns immediately when
`authenticationRequired` is false, and `androidx.biometric` only draws its own
AppCompat dialog below API 28.

**Write American English** — documentation, code comments, commit messages and
identifiers alike. The audience is pub.dev.

## Shell

**The shell never writes files.** No `cat > file`, no `sed -i`, no interpreter
heredoc — use Write and Edit. A scripted replacement fails *silently*:
`str.replace` and `sed` both return the input unchanged when the pattern misses,
then write it back and exit zero, where a structured edit raises. The one
carve-out is a mechanical change across five or more places; it still has to
assert the pattern matched, and be verified afterwards.

**Background anything slow** — a Gradle build, an Xcode build, `pod install`,
a first-run wrapper download. The harness re-invokes you when a backgrounded
command exits, so never pair it with a polling loop; that is the thing that
hangs.

**`timeout` is not on macOS by default.** `timeout 30 some-command` fails with
"command not found", which reads as though the command itself were missing. Use
the tool's own deadline flag.

**Temporary files go in the session scratchpad**, never `/tmp` and never the
checkout.

## Git

Commit subjects are lower-case declarative sentences, optionally prefixed with
the area they touch — `android: upgrade AGP and androidx dependencies`,
`macos/ios: use options when evaluating canAuthenticate.` No
conventional-commits prefix (the one `feat:` in the history is the exception,
not the rule), no ticket reference. The body says what was wrong, why this is
right, and how it was verified. End with:

```
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

`CHANGELOG.md` is part of the change, not a release chore — every user-visible
change gets its line in the same commit.

**Do not publish to pub.dev.** Releases are the owner's call.
