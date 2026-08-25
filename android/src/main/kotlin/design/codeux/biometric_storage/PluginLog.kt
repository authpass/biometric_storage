package design.codeux.biometric_storage

import android.util.Log

/**
 * The plugin's logging, on top of [android.util.Log].
 *
 * This deliberately replaces `kotlin-logging` and `slf4j-api`. Both are
 * facades, and this package shipped neither with a provider, so every call was
 * discarded — SLF4J 2.x with no provider reports `No SLF4J providers were
 * found` once and then no-ops. Worse, `kotlin-logging` names every backend it
 * can bind to, which left R8 walking references to `ch.qos.logback.*` classes
 * that were genuinely absent and failing `minifyReleaseWithR8` in every
 * consumer's release build.
 *
 * The call shape is kept identical to `kotlin-logging` so the call sites did
 * not have to change: `logger.debug { "..." }` and `logger.error(e) { "..." }`.
 *
 * The members are `inline`, and that is the point of the wrapper rather than
 * calling [Log] directly: the lambda is only invoked once the level has been
 * found to be enabled, so `logger.debug { "expensive $x" }` builds no string
 * when debug logging is off. A bare `Log.d(TAG, "expensive $x")` would build it
 * every time and then throw it away.
 */
internal object PluginLog {

    /**
     * One tag for the whole plugin, so a single command turns everything on:
     *
     *     adb shell setprop log.tag.BiometricStorage VERBOSE
     *
     * Not derived from the class or file name. `minSdk` is 23, and below API 24
     * [Log.isLoggable] throws `IllegalArgumentException` for a tag longer than
     * 23 characters — the derived name for the largest source file here would
     * be `BiometricStoragePluginKt`, which is 24. Truncating to fit would also
     * leave nobody able to guess what to pass to `setprop`.
     */
    const val TAG = "BiometricStorage"

    inline fun trace(t: Throwable? = null, message: () -> String) =
        log(Log.VERBOSE, t, message)

    inline fun debug(t: Throwable? = null, message: () -> String) =
        log(Log.DEBUG, t, message)

    inline fun info(t: Throwable? = null, message: () -> String) =
        log(Log.INFO, t, message)

    inline fun warn(t: Throwable? = null, message: () -> String) =
        log(Log.WARN, t, message)

    inline fun error(t: Throwable? = null, message: () -> String) =
        log(Log.ERROR, t, message)

    @PublishedApi
    internal inline fun log(level: Int, t: Throwable?, message: () -> String) {
        if (!isLoggable(level)) {
            return
        }
        val text = message()
        Log.println(
            level,
            TAG,
            if (t == null) {
                text
            } else {
                "$text\n${Log.getStackTraceString(t)}"
            }
        )
    }

    /**
     * [Log.isLoggable] answers `false` below INFO unless a `log.tag` property
     * says otherwise, which would leave `trace` and `debug` — most of the call
     * sites here — silent by default. Silent by default is the behaviour being
     * fixed, so a debug build logs everything, matching what the example app's
     * `logback.xml` used to configure. A release build stays quiet until
     * somebody asks for output with `setprop`.
     */
    @PublishedApi
    internal fun isLoggable(level: Int) =
        BuildConfig.DEBUG || Log.isLoggable(TAG, level)
}
