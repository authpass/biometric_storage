package design.codeux.biometric_storage

import android.app.Activity
import android.content.Context
import android.os.*
import androidx.biometric.*
import androidx.fragment.app.FragmentActivity
import com.squareup.moshi.JsonClass
import com.squareup.moshi.Moshi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.*
import io.flutter.plugin.common.*
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar
import mu.KotlinLogging
import java.io.PrintWriter
import java.io.StringWriter
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

private val logger = KotlinLogging.logger {}

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
}

@Suppress("unused")
enum class AuthenticationError(val code: Int) {
    Canceled(BiometricPrompt.ERROR_CANCELED),
    Timeout(BiometricPrompt.ERROR_TIMEOUT),
    UserCanceled(BiometricPrompt.ERROR_USER_CANCELED),
    Unknown(-1),
    /** Authentication valid, but unknown */
    Failed(-2),
    ;

    companion object {
        fun forCode(code: Int) =
            values().firstOrNull { it.code == code } ?: Unknown
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

        // deprecated, used for v1 plugin api.
        @Suppress("unused")
        @JvmStatic
        fun registerWith(registrar: Registrar) {
            BiometricStoragePlugin().apply {
                initialize(
                    registrar.messenger(),
                    registrar.context()
                )
                updateAttachedActivity(registrar.activity())
            }
        }

        const val PARAM_NAME = "name"
        const val PARAM_WRITE_CONTENT = "content"
        const val PARAM_ANDROID_PROMPT_INFO = "androidPromptInfo"

        val moshi = Moshi.Builder()
            // ... add your own JsonAdapters and factories ...
            .build() as Moshi

        val executor : ExecutorService = Executors.newSingleThreadExecutor()
        private val handler: Handler = Handler(Looper.getMainLooper())
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

    fun initialize(messenger: BinaryMessenger, context: Context) {
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
                    moshi.adapter(AndroidPromptInfo::class.java).fromJsonValue(it) ?: throw MethodCallException(
                        "BadArgument",
                        "'$PARAM_ANDROID_PROMPT_INFO' is not well formed"
                    )
                }
            }

            fun withStorage(cb: BiometricStorageFile.() -> Unit) {
                val name = getName()
                storageFiles[name]?.apply(cb) ?: return {
                    logger.warn { "User tried to access storage '$name', before initialization" }
                    result.error("Storage $name was not initialized.", null, null)
                }()
            }
            fun BiometricStorageFile.withAuth(cb: BiometricStorageFile.() -> Unit) {
                if (!options.authenticationRequired) {
                    return cb()
                }
                val promptInfo = getAndroidPromptInfo()
                authenticate(promptInfo, {
                    cb()
                }) { info ->
                    result.error("AuthError:${info.error}", info.message.toString(), info.errorDetails)
                    logger.error("AuthError: $info")
                }
            }

            when (call.method) {
                "canAuthenticate" -> result.success(canAuthenticate().toString())
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

                    val options = moshi.adapter<InitOptions>(InitOptions::class.java)
                        .fromJsonValue(call.argument("options") ?: emptyMap<String, Any>())
                        ?: InitOptions()
                    storageFiles[name] = BiometricStorageFile(applicationContext, name, options)
                    result.success(true)
                }
                "dispose" -> storageFiles.remove(getName())?.apply {
                    dispose()
                    result.success(true)
                } ?: throw MethodCallException("NoSuchStorage", "Tried to dispose non existing storage.", null)
                "read" -> withStorage { if (exists()) { withAuth { result.success(readFile(applicationContext)) } } else { result.success(null) } }
                "delete" -> withStorage { if (exists()) { withAuth { result.success(deleteFile()) } } else { result.success(false) } }
                "write" -> withStorage { withAuth {
                    writeFile(applicationContext, requiredArgument(PARAM_WRITE_CONTENT))
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

    private inline fun ui(crossinline onError: ErrorCallback, crossinline cb: () -> Unit) = handler.post {
        try {
            cb()
        } catch (e: Throwable) {
            logger.error(e) { "Error while calling UI callback. This must not happen." }
            onError(AuthenticationErrorInfo(AuthenticationError.Unknown, "Unexpected authentication error. ${e.localizedMessage}", e))
        }
    }

    private fun canAuthenticate(): CanAuthenticateResponse {
        val response = biometricManager.canAuthenticate()
        return CanAuthenticateResponse.values().firstOrNull { it.code == response }
            ?: throw Exception("Unknown response code {$response} (available: ${CanAuthenticateResponse.values()}")
    }

    private fun authenticate(promptInfo: AndroidPromptInfo, onSuccess: () -> Unit, onError: ErrorCallback) {
        logger.trace("authenticate()")
        val activity = attachedActivity ?: return run {
            logger.error { "We are not attached to an activity." }
            onError(AuthenticationErrorInfo(AuthenticationError.Failed, "Plugin not attached to any activity."))
        }
        val prompt = BiometricPrompt(activity, executor, object: BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                logger.trace("onAuthenticationError($errorCode, $errString)")
                ui(onError) { onError(AuthenticationErrorInfo(AuthenticationError.forCode(errorCode), errString)) }
            }

            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                logger.trace("onAuthenticationSucceeded($result)")
                ui(onError) { onSuccess() }
            }

            override fun onAuthenticationFailed() {
                logger.trace("onAuthenticationFailed()")
                // this can happen multiple times, so we don't want to communicate an error.
//                ui(onError) { onError(AuthenticationErrorInfo(AuthenticationError.Failed, "biometric is valid but not recognized")) }
            }
        })
        prompt.authenticate(BiometricPrompt.PromptInfo.Builder()
            .setTitle(promptInfo.title)
            .setSubtitle(promptInfo.subtitle)
            .setDescription(promptInfo.description)
            .setNegativeButtonText(promptInfo.negativeButton)
            .setConfirmationRequired(promptInfo.confirmationRequired)
            .build())
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

@JsonClass(generateAdapter = true)
data class AndroidPromptInfo(
    val title: String,
    val subtitle: String?,
    val description: String?,
    val negativeButton: String,
    val confirmationRequired: Boolean
)
