package design.codeux.biometric_storage

import android.app.Activity
import android.content.Context
import android.os.*
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.UserNotAuthenticatedException
import androidx.biometric.*
import androidx.biometric.BiometricManager.Authenticators.*
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.*
import io.flutter.plugin.common.*
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import mu.KotlinLogging
import java.io.PrintWriter
import java.io.StringWriter
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.crypto.Cipher

private val logger = KotlinLogging.logger {}

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
    Unknown(-1),
    /** Authentication valid, but unknown */
    Failed(-2),
    ;

    companion object {
        fun forCode(code: Int) =
            values().firstOrNull { it.code.contains(code) } ?: Unknown
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

    private var attachedActivity: FragmentActivity? = null

    private val storageFiles = mutableMapOf<String, BiometricStorageFile>()

    private val biometricManager by lazy { BiometricManager.from(applicationContext) }

    private lateinit var applicationContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        initialize(binding.binaryMessenger, binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    }

    private fun initialize(messenger: BinaryMessenger, context: Context) {
        this.applicationContext = context
        val channel = MethodChannel(messenger, "biometric_storage")
        channel.setMethodCallHandler(this)
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
                    result.error("Storage $name was not initialized.", null, null)
                    return
                }
            }
            fun BiometricStorageFile.withAuth(
                mode: CipherMode,
                cb: BiometricStorageFile.(cipher: Cipher?) -> Unit
            ) {
                if (!options.authenticationRequired) {
                    return cb(null)
                }

                fun cipherForMode() = when (mode) {
                    CipherMode.Encrypt -> cipherForEncrypt()
                    CipherMode.Decrypt -> cipherForDecrypt()
                }

                val cipher = if (options.authenticationValidityDurationSeconds > -1) {
                    null
                } else try {
                    cipherForMode()
                } catch (e: KeyPermanentlyInvalidatedException) {
                    // TODO should we communicate this to the caller?
                    logger.warn(e) { "Key was invalidated. removing previous storage and recreating." }
                    deleteFile()
                    // if deleting fails, simply throw the second time around.
                    cipherForMode()
                }

                if (cipher == null) {
                    // if we have no cipher, just try the callback and see if the
                    // user requires authentication.
                    try {
                        return cb(null)
                    } catch (e: UserNotAuthenticatedException) {
                        logger.debug(e) { "User requires (re)authentication. showing prompt ..."}
                    }
                }

                val promptInfo = getAndroidPromptInfo()
                authenticate(cipher, promptInfo, options, {
                    cb(cipher)
                }) { info ->
                    result.error("AuthError:${info.error}", info.message.toString(), info.errorDetails)
                    logger.error("AuthError: $info")
                }
            }

            when (call.method) {
                "canAuthenticate" -> result.success(canAuthenticate().name)
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

                    val options = call.argument<Map<String, Any>>("options")?.let { it ->
                        InitOptions(
                                authenticationValidityDurationSeconds = it["authenticationValidityDurationSeconds"] as Int,
                                authenticationRequired = it["authenticationRequired"] as Boolean,
                                androidBiometricOnly = it["androidBiometricOnly"] as Boolean,
                        )
                    } ?: InitOptions()
//                    val options = moshi.adapter(InitOptions::class.java)
//                        .fromJsonValue(call.argument("options") ?: emptyMap<String, Any>())
//                        ?: InitOptions()
                    storageFiles[name] = BiometricStorageFile(applicationContext, name, options)
                    result.success(true)
                }
                "dispose" -> storageFiles.remove(getName())?.apply {
                    dispose()
                    result.success(true)
                } ?: throw MethodCallException("NoSuchStorage", "Tried to dispose non existing storage.", null)
                "read" -> withStorage { if (exists()) { withAuth(CipherMode.Decrypt) { result.success(readFile(it, applicationContext)) } } else { result.success(null) } }
                "delete" -> withStorage { if (exists()) { result.success(deleteFile()) } else { result.success(false) } }
                "write" -> withStorage { withAuth(CipherMode.Encrypt) {
                    writeFile(it, requiredArgument(PARAM_WRITE_CONTENT))
                    result.success(true)
                } }
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

    private inline fun ui(crossinline onError: ErrorCallback, crossinline cb: () -> Unit) {
        try {
            cb()
        } catch (e: Throwable) {
            logger.error(e) { "Error while calling UI callback. This must not happen." }
            onError(AuthenticationErrorInfo(AuthenticationError.Unknown, "Unexpected authentication error. ${e.localizedMessage}", e))
        }
    }

    private fun canAuthenticate(): CanAuthenticateResponse {
        val response = biometricManager.canAuthenticate(
            BIOMETRIC_STRONG or BIOMETRIC_WEAK
        )
        return CanAuthenticateResponse.values().firstOrNull { it.code == response }
                ?: throw Exception("Unknown response code {$response} (available: ${
                    CanAuthenticateResponse
                        .values()
                        .contentToString()
                }")
    }

    private fun authenticate(
        cipher: Cipher?,
        promptInfo: AndroidPromptInfo,
        options: InitOptions,
        onSuccess: (cipher: Cipher?) -> Unit,
        onError: ErrorCallback
    ) {
        logger.trace("authenticate()")
        val activity = attachedActivity ?: return run {
            logger.error { "We are not attached to an activity." }
            onError(AuthenticationErrorInfo(AuthenticationError.Failed, "Plugin not attached to any activity."))
        }
        val prompt = BiometricPrompt(activity, Executors.newSingleThreadExecutor(), object: BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                logger.trace("onAuthenticationError($errorCode, $errString)")
                ui(onError) { onError(AuthenticationErrorInfo(AuthenticationError.forCode(errorCode), errString)) }
            }

            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                logger.trace("onAuthenticationSucceeded($result)")
                ui(onError) { onSuccess(result.cryptoObject?.cipher) }
            }

            override fun onAuthenticationFailed() {
                logger.trace("onAuthenticationFailed()")
                // this can happen multiple times, so we don't want to communicate an error.
//                ui(onError) { onError(AuthenticationErrorInfo(AuthenticationError.Failed, "biometric is valid but not recognized")) }
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
                logger.debug { "androidBiometricOnly was false, but prior " +
                        "to ${Build.VERSION_CODES.R} this was not supported. ignoring." }
            }
            promptBuilder
                .setAllowedAuthenticators(BIOMETRIC_STRONG)
                .setNegativeButtonText(promptInfo.negativeButton)
        } else {
            promptBuilder.setAllowedAuthenticators(DEVICE_CREDENTIAL or BIOMETRIC_STRONG)
        }

        if (cipher == null || options.authenticationValidityDurationSeconds >= 0) {
            // if authenticationValidityDurationSeconds is not -1 we can't use a CryptoObject
            logger.debug { "Authenticating without cipher. ${options.authenticationValidityDurationSeconds}" }
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
    }
}

data class AndroidPromptInfo(
    val title: String,
    val subtitle: String?,
    val description: String?,
    val negativeButton: String,
    val confirmationRequired: Boolean
)
