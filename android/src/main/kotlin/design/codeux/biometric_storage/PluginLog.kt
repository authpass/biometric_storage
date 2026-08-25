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
 * every time and then throw it away. That still holds with a
 * [BiometricStorageLogging.Sink] installed,
 * which is why the level is decided here rather than left to the framework on
 * the other side of it.
 *
 * This is the internal half. [BiometricStorageLogging] is what a consuming app
 * sees, and is where the level and the destination are configured.
 */
internal object PluginLog {

    /** @see BiometricStorageLogging.TAG */
    const val TAG = BiometricStorageLogging.TAG

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
        write(level, message(), t)
    }

    /**
     * An explicit [BiometricStorageLogging.level] wins. Otherwise a sink is
     * taken as a statement that something wants every record, since the
     * automatic default below describes logcat rather than somebody else's
     * framework.
     *
     * That default exists because [Log.isLoggable] answers `false` below INFO
     * unless a `log.tag` property says otherwise, which would leave `trace` and
     * `debug` — most of the call sites here — silent. Silent by default is the
     * behaviour this class was written to fix, so a debug build logs
     * everything and a release build stays quiet until somebody asks.
     */
    @PublishedApi
    internal fun isLoggable(level: Int): Boolean {
        BiometricStorageLogging.level?.let {
            return level >= it
        }
        if (BiometricStorageLogging.sink != null) {
            return true
        }
        return BuildConfig.DEBUG || Log.isLoggable(TAG, level)
    }

    /**
     * Read [BiometricStorageLogging.sink] once: it is volatile, and reading it
     * again after [isLoggable] could see a different value if another thread
     * installed or cleared it in between. Falling back to logcat is better than
     * dropping the record.
     */
    @PublishedApi
    internal fun write(level: Int, text: String, t: Throwable?) {
        BiometricStorageLogging.sink?.let {
            it.log(level, TAG, text, t)
            return
        }
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
}
