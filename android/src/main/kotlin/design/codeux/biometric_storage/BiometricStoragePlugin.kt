package design.codeux.biometric_storage

import android.app.Activity
import android.content.Context
import android.os.*
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.UserNotAuthenticatedException
import androidx.annotation.AnyThread
import androidx.annotation.UiThread
import androidx.annotation.WorkerThread
import androidx.biometric.*
import androidx.biometric.BiometricManager.Authenticators.*
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.*
import io.flutter.plugin.common.*
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.PrintWriter
import java.io.StringWriter
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.crypto.Cipher
import kotlin.time.Duration.Companion.seconds

private val logger = PluginLog

enum class CipherMode {
    Encrypt,
    Decrypt,
}

typealias ErrorCallback = (errorInfo: AuthenticationErrorInfo) -> Unit

class MethodCallException(
    val errorCode: String,
    val errorMessage: String?,
    val errorDetails: Any? = null
) : Exception(errorMessage ?: errorCode)

@Suppress("unused")
enum class CanAuthenticateResponse(val code: Int) {
    Success(BiometricManager.BIOMETRIC_SUCCESS),
    ErrorHwUnavailable(BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE),
    ErrorNoBiometricEnrolled(BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED),
    ErrorNoHardware(BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE),
    ErrorStatusUnknown(BiometricManager.BIOMETRIC_STATUS_UNKNOWN),
    ErrorPasscodeNotSet(-99),
    ;

    override fun toString(): String {
        return "CanAuthenticateResponse.${name}: $code"
    }
}

@Suppress("unused")
enum class AuthenticationError(vararg val code: Int) {
    Canceled(BiometricPrompt.ERROR_CANCELED),
    Timeout(BiometricPrompt.ERROR_TIMEOUT),
    UserCanceled(BiometricPrompt.ERROR_USER_CANCELED, BiometricPrompt.ERROR_NEGATIVE_BUTTON),

    /**
     * Too many failed attempts; biometry recovers on its own after a short
     * wait whose length Android does not specify.
     */
    Lockout(BiometricPrompt.ERROR_LOCKOUT),

    /** Lockout after continued failures. Only clears via device credential entry. */
    LockoutPermanent(BiometricPrompt.ERROR_LOCKOUT_PERMANENT),

    /**
     * The Keystore key backing this storage can no longer be used because the
     * device's enrolled biometrics changed since it was created.
     *
     * Not a [BiometricPrompt] error code — the sentinel keeps it out of
     * [forCode]'s reach, which only ever sees codes androidx hands over, all
     * of them non-negative. It is reported from a caught
     * [KeyPermanentlyInvalidatedException] before any prompt is shown, and
     * only for a read: a write recreates the key and carries on, having lost
     * nothing it was not replacing.
     */
    KeyInvalidated(-3),
    Unknown(-1),

    /** Authentication valid, but unknown */
    Failed(-2),
    ;

    companion object {
        fun forCode(code: Int) =
            entries.firstOrNull { it.code.contains(code) } ?: Unknown
    }
}

data class AuthenticationErrorInfo(
    val error: AuthenticationError,
    val message: CharSequence,
    val errorDetails: String? = null
) {
    constructor(
        error: AuthenticationError,
        message: CharSequence,
        e: Throwable
    ) : this(error, message, e.toCompleteString())
}

private fun Throwable.toCompleteString(): String {
    val out = StringWriter().let { out ->
        printStackTrace(PrintWriter(out))
        out.toString()
    }
    return "$this\n$out"
}

class BiometricStoragePlugin : FlutterPlugin, ActivityAware, MethodCallHandler {

    companion object {
        const val PARAM_NAME = "name"
        const val PARAM_WRITE_CONTENT = "content"
        const val PARAM_ANDROID_PROMPT_INFO = "androidPromptInfo"

    }

    private val executor: ExecutorService by lazy { Executors.newSingleThreadExecutor() }
    private val handler: Handler by lazy { Handler(Looper.getMainLooper()) }


    private var attachedActivity: FragmentActivity? = null

    private val storageFiles = mutableMapOf<String, BiometricStorageFile>()

    private val biometricManager by lazy { BiometricManager.from(applicationContext) }

    private lateinit var applicationContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.applicationContext = binding.applicationContext
        val channel = MethodChannel(binding.binaryMessenger, "biometric_storage")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        logger.trace { "onMethodCall(${call.method})" }
        try {
            fun <T> requiredArgument(name: String) =
                call.argument<T>(name) ?: throw MethodCallException(
                    "MissingArgument",
                    "Missing required argument '$name'"
                )

            // every method call requires the name of the stored file.
            val getName = { requiredArgument<String>(PARAM_NAME) }
            val getAndroidPromptInfo = {
                requiredArgument<Map<String, Any>>(PARAM_ANDROID_PROMPT_INFO).let {
                    AndroidPromptInfo(
                        title = it["title"] as String,
                        subtitle = it["subtitle"] as String?,
                        description = it["description"] as String?,
                        negativeButton = it["negativeButton"] as String,
                        confirmationRequired = it["confirmationRequired"] as Boolean,
                    )
                }
            }

            fun withStorage(cb: BiometricStorageFile.() -> Unit) {
                val name = getName()
                storageFiles[name]?.apply(cb) ?: run {
                    logger.warn { "User tried to access storage '$name', before initialization" }
                    // error(code, message, details) — the sentence used to be
                    // passed as the code, which is the field callers match on.
                    result.error(
                        "NotInitialized",
                        "Storage $name was not initialized.",
                        null
                    )
                    return
                }
            }

            val resultError: ErrorCallback = { errorInfo ->
                result.error(
                    "AuthError:${errorInfo.error}",
                    errorInfo.message.toString(),
                    errorInfo.errorDetails
                )
                logger.error { "AuthError: $errorInfo" }

            }

            // A failure on a store that never authenticates is not an
            // authentication error. While these ran inline, a throw reached the
            // catch at the bottom of onMethodCall and was reported as
            // "Unexpected Error"; keep that code now that they run on the
            // worker, so a caller's `on PlatformException` sees what it always
            // did rather than an AuthException from a store with no prompt.
            val resultUnexpected: (Throwable) -> Unit = { e ->
                result.error("Unexpected Error", e.message, e.toCompleteString())
            }

            @UiThread
            fun BiometricStorageFile.withAuth(
                mode: CipherMode,
                @WorkerThread cb: BiometricStorageFile.(cipher: Cipher?) -> Unit
            ) {
                if (!options.authenticationRequired) {
                    // Off the main thread, like the authenticated path: every
                    // keystore round trip here — a cipher, a key lookup, the
                    // decrypt — blocks whatever thread runs it, and on Android
                    // the main thread is the one that hands Flutter its vsync.
                    // On a StrongBox device each costs ~35 ms, and an app that
                    // reads a few items at once loses whole frames to it.
                    workerOrElse(resultUnexpected) { cb(null) }
                    return
                }

                fun cipherForMode() = when (mode) {
                    CipherMode.Encrypt -> cipherForEncrypt()
                    CipherMode.Decrypt -> cipherForDecrypt()
                }

                val cipher = if (options.androidAuthenticationValidityDuration != null) {
                    null
                } else try {
                    cipherForMode()
                } catch (e: KeyPermanentlyInvalidatedException) {
                    // Enrolled biometrics changed, so the key this store was
                    // written under is gone and the file under it can never be
                    // decrypted again. Clear both; a new key is minted on the
                    // next write.
                    logger.warn(e) { "Key was invalidated. removing previous storage." }
                    deleteFile()
                    when (mode) {
                        // A read has lost something, and silence here was the
                        // old behaviour's real cost: the caller saw the null
                        // that also means "nothing stored" and could not tell
                        // an empty store from one the OS had just emptied.
                        // That distinction decides whether an app asks the user
                        // to set their secret up again or reports a bug.
                        CipherMode.Decrypt -> {
                            resultError(
                                AuthenticationErrorInfo(
                                    AuthenticationError.KeyInvalidated,
                                    "Key was invalidated",
                                    e
                                )
                            )
                            return
                        }
                        // A write has lost nothing it was not about to replace.
                        // Failing it would make every caller handle an error
                        // whose only sane recovery is to write again, with the
                        // same content, against the fresh key — so do that here
                        // and let the write succeed. Minting the key is what
                        // cipherForEncrypt does, and the file is already gone,
                        // so there is nothing left to be invalidated: a second
                        // throw would be a real failure and propagates.
                        CipherMode.Encrypt -> cipherForMode()
                    }
                }

                if (cipher == null) {
                    // No CryptoObject to bind a prompt to, so the only way to
                    // learn whether the key's validity window is still open is
                    // to try: cipher.init throws UserNotAuthenticatedException
                    // once it has closed. That try is a keystore round trip
                    // like every other and runs on the worker; the prompt it
                    // may lead to is posted back to the main thread.
                    workerOrElse(resultUnexpected) {
                        try {
                            cb(null)
                        } catch (e: UserNotAuthenticatedException) {
                            logger.debug(e) { "User requires (re)authentication. showing prompt ..." }
                            ui(resultError) {
                                authenticate(null, getAndroidPromptInfo(), options, {
                                    cb(null)
                                }, onError = resultError)
                            }
                        }
                    }
                    return
                }

                val promptInfo = getAndroidPromptInfo()
                authenticate(cipher, promptInfo, options, {
                    cb(cipher)
                }, onError = resultError)
            }

            fun parseInitOptions() = call.argument<Map<String, Any>>("options")?.let {
                InitOptions(
                    androidAuthenticationValidityDuration = (it["androidAuthenticationValidityDurationSeconds"] as Int?)?.seconds,
                    authenticationRequired = it["authenticationRequired"] as Boolean,
                    androidBiometricOnly = it["androidBiometricOnly"] as Boolean,
                )
            } ?: InitOptions()

            when (call.method) {
                "canAuthenticate" -> result.success(canAuthenticate(parseInitOptions()).name)
                "init" -> {
                    val name = getName()
                    if (storageFiles.containsKey(name)) {
                        if (call.argument<Boolean>("forceInit") == true) {
                            throw MethodCallException(
                                "AlreadyInitialized",
                                "A storage file with the name '$name' was already initialized."
                            )
                        } else {
                            result.success(false)
                            return
                        }
                    }

                    val options = parseInitOptions()
//                    val options = moshi.adapter(InitOptions::class.java)
//                        .fromJsonValue(call.argument("options") ?: emptyMap<String, Any>())
//                        ?: InitOptions()
                    storageFiles[name] = BiometricStorageFile(applicationContext, name, options)
                    result.success(true)
                }

                // Reports whether there was an initialization to forget rather
                // than throwing when there was not, so that disposing twice is
                // safe and every platform answers alike. It used to raise
                // NoSuchStorage, which made Android the only backend where a
                // repeat dispose was an error. The stored content is left
                // alone: this reconfigures, it does not erase.
                "dispose" -> {
                    val existing = storageFiles.remove(getName())
                    existing?.dispose()
                    result.success(existing != null)
                }

                "read" -> withStorage {
                    // The pre-check is for the CryptoObject path, where it
                    // keeps an absent file from raising a prompt. Everywhere
                    // else the read happens on the worker, exists() included:
                    // deciding "no file" here would answer from the main
                    // thread's view while a write may still sit queued ahead
                    // of this read. readFile answers null for an absent file
                    // without touching the keystore, so the validity-window
                    // probe raises no prompt for one either.
                    if (options.authenticationRequired &&
                        options.androidAuthenticationValidityDuration == null &&
                        !exists()
                    ) {
                        result.success(null)
                    } else {
                        withAuth(CipherMode.Decrypt) {
                            val ret = readFile(
                                it,
                            )
                            ui(resultError) { result.success(ret) }
                        }
                    }
                }

                "delete" -> withStorage {
                    // deleteFile removes the key from the keystore too. exists()
                    // is asked on the worker so a delete queued behind a write
                    // sees the file that write produced.
                    // A file set aside as unreadable goes too, even when nothing
                    // has been written since; the answer is still whether a
                    // stored value was deleted, which deleteFile reports.
                    workerOrElse(resultUnexpected) {
                        val deleted = (exists() || hasLeftovers()) && deleteFile()
                        ui(resultError) { result.success(deleted) }
                    }
                }

                "write" -> withStorage {
                    // Read on the main thread, so a missing argument reaches
                    // the catch below as MissingArgument, before any prompt.
                    val content = requiredArgument<String>(PARAM_WRITE_CONTENT)
                    withAuth(CipherMode.Encrypt) {
                        writeFile(it, content)
                        ui(resultError) { result.success(true) }
                    }
                }

                else -> result.notImplemented()
            }
        } catch (e: MethodCallException) {
            logger.error(e) { "Error while processing method call ${call.method}" }
            result.error(e.errorCode, e.errorMessage, e.errorDetails)
        } catch (e: Exception) {
            logger.error(e) { "Error while processing method call '${call.method}'" }
            result.error("Unexpected Error", e.message, e.toCompleteString())
        }
    }

    @AnyThread
    private inline fun ui(
        @UiThread crossinline onError: ErrorCallback,
        @UiThread crossinline cb: () -> Unit
    ) = handler.post {
        try {
            cb()
        } catch (e: Throwable) {
            logger.error(e) { "Error while calling UI callback. This must not happen." }
            onError(
                AuthenticationErrorInfo(
                    AuthenticationError.Unknown,
                    "Unexpected authentication error. ${e.localizedMessage}",
                    e
                )
            )
        }
    }

    /**
     * Runs [cb] on the worker executor. A throw is logged and handed to
     * [onThrow] on the main thread, so the pending result is answered exactly
     * once whichever way the callback ends.
     */
    private inline fun workerOrElse(
        @UiThread crossinline onThrow: (Throwable) -> Unit,
        @WorkerThread crossinline cb: () -> Unit
    ) = executor.submit {
        try {
            cb()
        } catch (e: Throwable) {
            logger.error(e) { "Error while calling worker callback. This must not happen." }
            handler.post { onThrow(e) }
        }
    }

    /** [workerOrElse] for the authenticated path, where a throw is an authentication error. */
    private inline fun worker(
        @UiThread crossinline onError: ErrorCallback,
        @WorkerThread crossinline cb: () -> Unit
    ) = workerOrElse({ e ->
        onError(
            AuthenticationErrorInfo(
                AuthenticationError.Unknown,
                "Unexpected authentication error. ${e.localizedMessage}",
                e
            )
        )
    }, cb)

    private fun canAuthenticate(initOptions: InitOptions): CanAuthenticateResponse {
        if (!initOptions.authenticationRequired) {
            // doesn't really make sense...
            logger.warn { "called `canAuthenticate` with initOptions.authenticationRequired == false. $initOptions" }
            return CanAuthenticateResponse.Success
        }
        val response = biometricManager.canAuthenticate(
            if (initOptions.androidBiometricOnly) {
                BIOMETRIC_STRONG
            } else {
                DEVICE_CREDENTIAL or BIOMETRIC_STRONG
            }
        )
        return CanAuthenticateResponse.entries.firstOrNull { it.code == response }
            ?: run {
                // androidx.biometric keeps adding status codes — Android 16 added
                // BIOMETRIC_ERROR_NOT_ENABLED_FOR_APPS (21), for example. Reporting
                // an unmapped one as "status unknown" is what that value is for;
                // throwing here took the whole call down.
                // https://github.com/authpass/biometric_storage/issues/148
                logger.warn {
                    "Unmapped canAuthenticate response code $response " +
                            "(known: ${CanAuthenticateResponse.entries})"
                }
                CanAuthenticateResponse.ErrorStatusUnknown
            }
    }

    @UiThread
    private fun authenticate(
        cipher: Cipher?,
        promptInfo: AndroidPromptInfo,
        options: InitOptions,
        @WorkerThread onSuccess: (cipher: Cipher?) -> Unit,
        onError: ErrorCallback
    ) {
        logger.trace { "authenticate()" }
        val activity = attachedActivity ?: return run {
            logger.error { "We are not attached to an activity." }
            onError(
                AuthenticationErrorInfo(
                    AuthenticationError.Failed,
                    "Plugin not attached to any activity."
                )
            )
        }
        // Being attached is not the same as being able to show a dialog.
        // androidx's BiometricPrompt refuses to start after onSaveInstanceState
        // and — this is the part that hurts — returns without invoking any
        // callback, logging "Unable to start authentication. Called after
        // onSaveInstanceState()". The pending Flutter result would then never
        // complete: not an error the caller can catch, a permanent silent hang.
        // Reachable whenever the app is backgrounded, independently of whether
        // the activity reference itself is stale.
        if (activity.isFinishing ||
            activity.isDestroyed ||
            activity.supportFragmentManager.isStateSaved
        ) {
            return run {
                logger.error {
                    "Activity cannot host a prompt right now " +
                            "(finishing=${activity.isFinishing} " +
                            "destroyed=${activity.isDestroyed} " +
                            "stateSaved=${activity.supportFragmentManager.isStateSaved})."
                }
                onError(
                    AuthenticationErrorInfo(
                        AuthenticationError.Failed,
                        "Activity is not in a state where an authentication " +
                                "prompt can be shown."
                    )
                )
            }
        }
        val prompt =
            BiometricPrompt(activity, executor, object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    logger.trace { "onAuthenticationError($errorCode, $errString)" }
                    ui(onError) {
                        onError(
                            AuthenticationErrorInfo(
                                AuthenticationError.forCode(
                                    errorCode
                                ), errString
                            )
                        )
                    }
                }

                @WorkerThread
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    logger.trace { "onAuthenticationSucceeded($result)" }
                    worker(onError) { onSuccess(result.cryptoObject?.cipher) }
                }

                override fun onAuthenticationFailed() {
                    logger.trace { "onAuthenticationFailed()" }
                    // this just means the user was not recognised, but the O/S will handle feedback so we don't have to
                }
            })

        val promptBuilder = BiometricPrompt.PromptInfo.Builder()
            .setTitle(promptInfo.title)
            .setSubtitle(promptInfo.subtitle)
            .setDescription(promptInfo.description)
            .setConfirmationRequired(promptInfo.confirmationRequired)

        val biometricOnly =
            options.androidBiometricOnly || Build.VERSION.SDK_INT < Build.VERSION_CODES.R

        if (biometricOnly) {
            if (!options.androidBiometricOnly) {
                logger.debug {
                    "androidBiometricOnly was false, but prior " +
                            "to ${Build.VERSION_CODES.R} this was not supported. ignoring."
                }
            }
            promptBuilder
                .setAllowedAuthenticators(BIOMETRIC_STRONG)
                .setNegativeButtonText(promptInfo.negativeButton)
        } else {
            promptBuilder.setAllowedAuthenticators(DEVICE_CREDENTIAL or BIOMETRIC_STRONG)
        }

        if (cipher == null || options.androidAuthenticationValidityDuration != null) {
            // if androidAuthenticationValidityDuration is not null we can't use a CryptoObject
            logger.debug { "Authenticating without cipher. ${options.androidAuthenticationValidityDuration}" }
            prompt.authenticate(promptBuilder.build())
        } else {
            prompt.authenticate(promptBuilder.build(), BiometricPrompt.CryptoObject(cipher))
        }
    }

    override fun onDetachedFromActivity() {
        logger.trace { "onDetachedFromActivity" }
        attachedActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        logger.debug { "Reattached to activity after a configuration change." }
        updateAttachedActivity(binding.activity)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        logger.debug { "Attached to new activity." }
        updateAttachedActivity(binding.activity)
    }

    private fun updateAttachedActivity(activity: Activity) {
        if (activity !is FragmentActivity) {
            logger.error { "Got attached to activity which is not a FragmentActivity: $activity" }
            return
        }
        attachedActivity = activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        logger.trace { "onDetachedFromActivityForConfigChanges" }
        // ActivityAware's contract: "By the end of this method, the Activity ...
        // is no longer valid. Any references ... should be cleared." Holding on
        // to it meant every authenticated read or write after a rotation handed
        // BiometricPrompt a destroyed FragmentActivity.
        attachedActivity = null
    }
}

data class AndroidPromptInfo(
    val title: String,
    val subtitle: String?,
    val description: String?,
    val negativeButton: String,
    val confirmationRequired: Boolean
)
