package design.codeux.biometric_storage

import android.content.Context
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import com.squareup.moshi.JsonClass
import mu.KotlinLogging
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import javax.crypto.Cipher

private val logger = KotlinLogging.logger {}

@JsonClass(generateAdapter = true)
data class InitOptions(
    val authenticationValidityDurationSeconds: Int = 30,
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

    private val masterKey: MasterKey

    private val cryptographyManager = CryptographyManager {
        setUserAuthenticationRequired(options.authenticationRequired)
        setUserAuthenticationValidityDurationSeconds(options.authenticationValidityDurationSeconds)
    }

    init {
        masterKey = MasterKey.Builder(context, masterKeyName)
            .setUserAuthenticationRequired(
                options.authenticationRequired, options.authenticationValidityDurationSeconds)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        val baseDir = File(context.filesDir, DIRECTORY_NAME)
        if (!baseDir.exists()) {
            baseDir.mkdirs()
        }
        file = File(baseDir, fileName)
        fileV2 = File(baseDir, fileNameV2)

        logger.trace { "Initialized $this with $options" }
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
    fun writeFile(cipher: Cipher?, context: Context, content: String) {
        if (cipher != null) {
            try {
                val encrypted = cryptographyManager.encryptData(content, cipher)
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


        val encryptedFile = buildEncryptedFile(context)

        val bytes = content.toByteArray()

        // Write to a file.
        try {
            if (file.exists()) {
                val backupFile = File(file.parent, "${file.name}$BACKUP_SUFFIX")
                if (backupFile.exists()) {
                    backupFile.delete()
                }
                file.renameTo(backupFile)
            }
            val outputStream: FileOutputStream = encryptedFile.openFileOutput()
            outputStream.use { out ->
                out.write(bytes)
                out.flush()
            }
            logger.debug { "Successfully written ${bytes.size} bytes." }
        } catch (ex: IOException) {
            // Error occurred opening file for writing.
            logger.error(ex) { "Error while writing encrypted file $file" }
        }
    }

    @Synchronized
    fun readFile(cipher: Cipher?, context: Context): String? {
        if (cipher != null) {
            if (fileV2.exists()) {
                return try {
                    val bytes = fileV2.readBytes()
                    cryptographyManager.decryptData(bytes, cipher)
                } catch (ex: IOException) {
                    logger.error(ex) { "Error while writing encrypted file $fileV2" }
                    null
                }
            }
        }
        if (!file.exists()) {
            logger.debug { "File $file does not exist. returning null." }
            return null
        }
        return try {
            val encryptedFile = buildEncryptedFile(context)

            val bytes = encryptedFile.openFileInput().use { input ->
                input.readBytes()
            }
            String(bytes)
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
