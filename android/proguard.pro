# Consumer rules: these travel inside the AAR and R8 applies them to the
# consuming app automatically, so an app that adds this plugin never has to
# discover them.
#
# kotlin-logging names every backend it is able to bind to, so R8 walks
# references to logback and slf4j whether or not either is on the classpath.
# When neither is — the normal case, since this plugin ships no provider — R8
# reports them as missing classes and refuses to complete:
#
#   Missing class ch.qos.logback.classic.Logger (referenced from: ...)
#   Execution failed for task ':app:minifyReleaseWithR8'
#
# That only happens in a release build. `flutter run`, `flutter test` and an
# emulator check all build debug or profile, where minification never runs, so
# the first thing that hits it is an attempt to ship to Play.
#
# -dontwarn rather than -keep: -keep would ask R8 to preserve classes that do
# not exist. The references are never reached at runtime either — they are
# alternative backends kotlin-logging chooses between, and with none present it
# falls back to a no-op.
-dontwarn ch.qos.logback.**
-dontwarn org.slf4j.**
-dontwarn io.github.oshai.kotlinlogging.logback.**
-dontwarn io.github.oshai.kotlinlogging.slf4j.**
