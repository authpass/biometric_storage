package design.codeux.biometric_storage

import android.content.Context
import android.os.Build
import android.security.keystore.KeyProperties
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import com.squareup.moshi.JsonClass
import mu.KotlinLogging
import java.io.File
import java.io.IOException
import javax.crypto.Cipher

private val logger = KotlinLogging.logger {}

@JsonClass(generateAdapter = true)
data class InitOptions(
    val authenticationValidityDurationSeconds: Int = -1,
    val authenticationRequired: Boolean = true,
    val androidBiometricOnly: Boolean = true
)

class BiometricStorageFile(
    context: Context,
    private val baseName: String,
    val options: InitOptions
) {

    companion object {
        /**
         * Name of directory inside private storage where all encrypted files are stored.
         */
        private const val DIRECTORY_NAME = "biometric_storage"
        private const val FILE_SUFFIX = ".txt"
        private const val FILE_SUFFIX_V2 = ".v2.txt"
        private const val BACKUP_SUFFIX = "bak"
    }

    private val masterKeyName = "${baseName}_master_key"
    private val fileName = "$baseName$FILE_SUFFIX"
    private val fileNameV2 = "$baseName$FILE_SUFFIX_V2"
    private val file: File
    private val fileV2: File

    private val masterKey: MasterKey by lazy {
        MasterKey.Builder(context, masterKeyName)
            .setUserAuthenticationRequired(
                options.authenticationRequired, options.authenticationValidityDurationSeconds)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
    }

    private val cryptographyManager = CryptographyManager {
        setUserAuthenticationRequired(options.authenticationRequired)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (options.authenticationValidityDurationSeconds == -1) {
                setUserAuthenticationParameters(
                    0,
                    KeyProperties.AUTH_BIOMETRIC_STRONG
                )
            } else {
                setUserAuthenticationParameters(
                    options.authenticationValidityDurationSeconds,
                    KeyProperties.AUTH_DEVICE_CREDENTIAL or KeyProperties.AUTH_BIOMETRIC_STRONG
                )
            }
        } else {
            @Suppress("DEPRECATION")
            setUserAuthenticationValidityDurationSeconds(options.authenticationValidityDurationSeconds)
        }
    }

    init {
        val baseDir = File(context.filesDir, DIRECTORY_NAME)
        if (!baseDir.exists()) {
            baseDir.mkdirs()
        }
        file = File(baseDir, fileName)
        fileV2 = File(baseDir, fileNameV2)

        logger.trace { "Initialized $this with $options" }

        validateOptions()
    }

    private fun validateOptions() {
        if (options.authenticationValidityDurationSeconds == -1 && !options.androidBiometricOnly) {
            throw IllegalArgumentException("when authenticationValidityDurationSeconds is -1, androidBiometricOnly must be true")
        }
    }

    fun cipherForEncrypt() = cryptographyManager.getInitializedCipherForEncryption(masterKeyName)
    fun cipherForDecrypt(): Cipher? {
        if (fileV2.exists()) {
            return cryptographyManager.getInitializedCipherForDecryption(masterKeyName, fileV2)
        }
        logger.debug { "No file exists, no IV found. null cipher." }
        return null
    }


    private fun buildEncryptedFile(context: Context) =
        EncryptedFile.Builder(
            context,
            file,
            masterKey,
            EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB
        )
            .setKeysetAlias("__biometric_storage__${baseName}_encrypted_file_keyset__")
            .setKeysetPrefName("__biometric_storage__${baseName}_encrypted_file_pref__")
            .build()
    
    fun exists() = file.exists() or fileV2.exists()

    @Synchronized
    fun writeFile(cipher: Cipher?, content: String) {
        // cipher will be null if user does not need authentication or valid period is > -1
        val useCipher = cipher ?: cipherForEncrypt()
        try {
            val encrypted = cryptographyManager.encryptData(content, useCipher)
            fileV2.writeBytes(encrypted.encryptedPayload)
            logger.debug { "Successfully written ${encrypted.encryptedPayload.size} bytes." }

            if (file.exists()) {
                file.delete()
            }
            val backupFile = File(file.parent, "${file.name}$BACKUP_SUFFIX")
            if (backupFile.exists()) {
                backupFile.delete()
            }

            return
        } catch (ex: IOException) {
            // Error occurred opening file for writing.
            logger.error(ex) { "Error while writing encrypted file $file" }
            throw ex
        }
    }

    @Synchronized
    fun readFile(cipher: Cipher?, context: Context): String? {
        val useCipher = cipher ?: cipherForDecrypt()
        // if the file exists, there should *always* be a decryption key.
        if (useCipher != null && fileV2.exists()) {
            return try {
                val bytes = fileV2.readBytes()
                cryptographyManager.decryptData(bytes, useCipher)
            } catch (ex: IOException) {
                logger.error(ex) { "Error while writing encrypted file $fileV2" }
                null
            }
        }

        if (!file.exists()) {
            logger.debug { "File $file does not exist. returning null." }
            return null
        }

        if (options.authenticationRequired && options.authenticationValidityDurationSeconds < 0) {
            logger.warn { "Found old file, but authenticationValidityDurationSeconds == -1, " +
                    "ignoring file because previously -1 was not supported." }
            return null
        }

        return try {
            val encryptedFile = buildEncryptedFile(context)

            val bytes = encryptedFile.openFileInput().use { input ->
                input.readBytes()
            }
            val string = String(bytes)

            if (!options.authenticationRequired || options.authenticationValidityDurationSeconds > -1) {
                logger.info { "Got old file, try to rewrite it into new encryption format." }
                try {
                    writeFile(null, string)
                } catch (ex: Exception) {
                    logger.warn(ex) { "Error while (re)writing into new encryption file." }
                }
            }

            string
        } catch (ex: IOException) {
            // Error occurred opening file for writing.
            logger.error(ex) { "Error while writing encrypted file $file" }
            null
        }
    }

    @Synchronized
    fun deleteFile(): Boolean {
        cryptographyManager.deleteKey(masterKeyName)
        return fileV2.delete() or file.delete()
    }

    override fun toString(): String {
        return "BiometricStorageFile(masterKeyName='$masterKeyName', fileName='$fileName', file=$file)"
    }

    fun dispose() {
        logger.trace { "dispose" }
    }

}
