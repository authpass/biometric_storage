package design.codeux.biometric_storage

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyProperties
import io.github.oshai.kotlinlogging.KotlinLogging
import java.io.File
import java.io.IOException
import java.security.ProviderException
import javax.crypto.Cipher
import kotlin.text.Charsets.UTF_8
import kotlin.time.Duration

private val logger = KotlinLogging.logger {}

data class InitOptions(
    val androidAuthenticationValidityDuration: Duration? = null,
    val authenticationRequired: Boolean = true,
    val androidBiometricOnly: Boolean = true,
    val androidUseStrongBox: Boolean = true
)

class BiometricStorageFile(
    context: Context,
    baseName: String,
    val options: InitOptions
) {

    companion object {
        private const val DIRECTORY_NAME = "biometric_storage"
        private const val FILE_SUFFIX_V2 = ".v2.txt"
        private const val ENCODED_FILE_NAME_PREFIX = "_encoded_"
    }

    private val masterKeyName = "${baseName}_master_key"
    private val fileNameV2 = buildFileName(baseName)
    private val fileV2: File
    private val strongBoxSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
        options.androidUseStrongBox &&
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
    private var useStrongBoxBackedKeystore = strongBoxSupported

    private var cryptographyManager = createCryptographyManager()

    init {
        val baseDir = File(context.filesDir, DIRECTORY_NAME)
        if (!baseDir.exists()) {
            baseDir.mkdirs()
        }
        fileV2 = File(baseDir, fileNameV2)

        logger.trace { "Initialized $this with $options" }

        validateOptions()
    }

    private fun buildFileName(baseName: String): String {
        val fileComponent = sanitizeFileComponent(baseName)
        return "$fileComponent$FILE_SUFFIX_V2"
    }

    private fun sanitizeFileComponent(baseName: String): String {
        if (!baseName.contains('/') && !baseName.contains('\\')) {
            return baseName
        }

        val encoded = baseName.toByteArray(UTF_8).joinToString(separator = "") {
            "%02x".format(it)
        }
        return "$ENCODED_FILE_NAME_PREFIX$encoded"
    }

    private fun validateOptions() {
        if (options.androidAuthenticationValidityDuration == null && !options.androidBiometricOnly) {
            throw IllegalArgumentException("when androidAuthenticationValidityDuration is null, androidBiometricOnly must be true")
        }
    }

    private fun createCryptographyManager() = CryptographyManager {
        setUserAuthenticationRequired(options.authenticationRequired)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            setIsStrongBoxBacked(useStrongBoxBackedKeystore)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (options.androidAuthenticationValidityDuration == null) {
                setUserAuthenticationParameters(
                    0,
                    KeyProperties.AUTH_BIOMETRIC_STRONG
                )
            } else {
                setUserAuthenticationParameters(
                    options.androidAuthenticationValidityDuration.inWholeSeconds.toInt(),
                    KeyProperties.AUTH_DEVICE_CREDENTIAL or KeyProperties.AUTH_BIOMETRIC_STRONG
                )
            }
        } else {
            @Suppress("DEPRECATION")
            setUserAuthenticationValidityDurationSeconds(
                options.androidAuthenticationValidityDuration?.inWholeSeconds?.toInt() ?: -1
            )
        }
    }

    private inline fun <T> retryWithoutStrongBoxIfNeeded(operation: () -> T): T =
        retryWithoutStrongBoxIfNeeded(
            useStrongBoxBackedKeystore = useStrongBoxBackedKeystore,
            deleteKey = { cryptographyManager.deleteKey(masterKeyName) },
            disableStrongBox = {
                useStrongBoxBackedKeystore = false
                cryptographyManager = createCryptographyManager()
            },
            operation = operation,
        )

    fun cipherForEncrypt() = retryWithoutStrongBoxIfNeeded {
        cryptographyManager.getInitializedCipherForEncryption(masterKeyName)
    }

    fun cipherForDecrypt(): Cipher? {
        if (fileV2.exists()) {
            return retryWithoutStrongBoxIfNeeded {
                cryptographyManager.getInitializedCipherForDecryption(masterKeyName, fileV2)
            }
        }
        logger.debug { "No file exists, no IV found. null cipher." }
        return null
    }

    fun exists() = fileV2.exists()

    @Synchronized
    fun writeFile(cipher: Cipher?, content: String) {
        val useCipher = cipher ?: cipherForEncrypt()
        try {
            fileV2.parentFile?.mkdirs()
            val encrypted = cryptographyManager.encryptData(content, useCipher)
            fileV2.writeBytes(encrypted.encryptedPayload)
            logger.debug { "Successfully written ${encrypted.encryptedPayload.size} bytes." }
            return
        } catch (ex: IOException) {
            logger.error(ex) { "Error while writing encrypted file $fileV2" }
            throw ex
        }
    }

    @Synchronized
    fun readFile(cipher: Cipher?): String? {
        val useCipher = cipher ?: cipherForDecrypt()
        if (useCipher != null && fileV2.exists()) {
            return try {
                val bytes = fileV2.readBytes()
                logger.debug { "read ${bytes.size}" }
                cryptographyManager.decryptData(bytes, useCipher)
            } catch (ex: IOException) {
                logger.error(ex) { "Error while writing encrypted file $fileV2" }
                null
            }
        }

        logger.debug { "File $fileV2 does not exist. returning null." }
        return null
    }

    @Synchronized
    fun deleteFile(): Boolean {
        cryptographyManager.deleteKey(masterKeyName)
        return fileV2.delete()
    }

    override fun toString(): String {
        return "BiometricStorageFile(masterKeyName='$masterKeyName', fileName='$fileNameV2', file=$fileV2)"
    }

    fun dispose() {
        logger.trace { "dispose" }
    }
}

internal fun androidStorageFileName(baseName: String): String {
    if (!baseName.contains('/') && !baseName.contains('\\')) {
        return "$baseName.v2.txt"
    }

    val encoded = baseName.toByteArray(UTF_8).joinToString(separator = "") {
        "%02x".format(it)
    }
    return "_encoded_$encoded.v2.txt"
}

internal inline fun <T> retryWithoutStrongBoxIfNeeded(
    useStrongBoxBackedKeystore: Boolean,
    deleteKey: () -> Unit,
    disableStrongBox: () -> Unit,
    operation: () -> T,
): T {
    try {
        return operation()
    } catch (error: ProviderException) {
        if (!useStrongBoxBackedKeystore) {
            throw error
        }
        logger.warn(error) {
            "StrongBox-backed key generation failed. Retrying without StrongBox support."
        }
        deleteKey()
        disableStrongBox()
        return operation()
    }
}
