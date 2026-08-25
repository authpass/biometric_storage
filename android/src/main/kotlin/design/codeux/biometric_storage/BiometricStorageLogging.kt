package design.codeux.biometric_storage

import android.util.Log

/**
 * Controls what this plugin logs on Android, and where those logs go.
 *
 * Everything here is optional. Left alone, the plugin writes to
 * [android.util.Log] under the tag [TAG]: everything in a debug build, and in a
 * release build only what `Log.isLoggable` allows, which means nothing below
 * INFO until somebody asks for it:
 *
 *     adb shell setprop log.tag.BiometricStorage VERBOSE
 *
 * That default suits an app that reads logs off a device. It does not suit an
 * app that collects its own — hence [level] and [sink].
 *
 * Set these before the first call into the plugin, from `Application.onCreate`
 * or your `FlutterActivity`. Both are read on every log call, so a later change
 * takes effect, but records emitted before the change are already gone.
 */
object BiometricStorageLogging {

    /**
     * Where log records go when one is installed as [sink].
     *
     * `priority` is an [android.util.Log] constant — [Log.VERBOSE] through
     * [Log.ERROR] — so it maps onto most frameworks directly. `message` is
     * already built; `throwable` is passed separately rather than flattened
     * into the message, so an implementation can hand the real exception to
     * whatever it reports to.
     *
     * Called on whichever thread produced the record, which for this plugin is
     * the main thread or its background executor. An implementation must be
     * safe to call from either.
     */
    fun interface Sink {
        fun log(priority: Int, tag: String, message: String, throwable: Throwable?)
    }

    /**
     * The tag the plugin logs under, and the one `setprop` expects.
     *
     * One tag for the whole plugin rather than one per class. minSdk is 23, and
     * below API 24 [Log.isLoggable] throws `IllegalArgumentException` for a tag
     * over 23 characters — a name derived from the largest source file here
     * would be `BiometricStoragePluginKt`, which is 24. A truncated tag would
     * also leave nobody able to guess what to hand to `setprop`.
     */
    const val TAG = "BiometricStorage"

    /**
     * The lowest [android.util.Log] priority to emit, or `null` to decide
     * automatically.
     *
     * Automatic — the default — means everything in a debug build, and in a
     * release build whatever `Log.isLoggable` permits. Setting this to
     * [Log.VERBOSE] makes the plugin log everything regardless of build type,
     * which is what an app wants if it captures its own logs and does not want
     * to depend on a device property being set.
     */
    @JvmStatic
    @Volatile
    var level: Int? = null

    /**
     * Receives every record the plugin emits, instead of [android.util.Log].
     *
     * This is the hook for an app that already has a logging framework — slf4j,
     * Timber, a file appender, a crash reporter. Forwarding to slf4j, for
     * example:
     *
     *     BiometricStorageLogging.sink =
     *         BiometricStorageLogging.Sink { priority, tag, message, throwable ->
     *             val log = LoggerFactory.getLogger(tag)
     *             when (priority) {
     *                 Log.VERBOSE -> log.trace(message, throwable)
     *                 Log.DEBUG -> log.debug(message, throwable)
     *                 Log.INFO -> log.info(message, throwable)
     *                 Log.WARN -> log.warn(message, throwable)
     *                 else -> log.error(message, throwable)
     *             }
     *         }
     *
     * Installing a sink also turns every level on, unless [level] says
     * otherwise: a sink is an explicit statement that something wants these
     * records, and the automatic default describes the built-in logcat
     * destination rather than this one. Set [level] as well to filter here
     * instead of in the framework.
     */
    @JvmStatic
    @Volatile
    var sink: Sink? = null
}
