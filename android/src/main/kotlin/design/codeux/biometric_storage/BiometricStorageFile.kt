package design.codeux.biometric_storage

import android.content.Context
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import com.squareup.moshi.JsonClass
import mu.KotlinLogging
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

private val logger = KotlinLogging.logger {}

@JsonClass(generateAdapter = true)
data class InitOptions(
    val authenticationValidityDurationSeconds: Int = 30,
    val authenticationRequired: Boolean = true
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
        private const val BACKUP_SUFFIX = "bak"
    }

    private val masterKeyName = "${baseName}_master_key"
    private val fileName = "$baseName$FILE_SUFFIX"
    private val file: File

    private val masterKey: MasterKey

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

        logger.trace { "Initialized $this with $options" }
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
    
    fun exists() = file.exists()

    @Synchronized
    fun writeFile(context: Context, content: String) {
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
    fun readFile(context: Context): String? {
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
        if (!file.exists()) {
            return false
        }
        return file.delete()
    }

    override fun toString(): String {
        return "BiometricStorageFile(masterKeyName='$masterKeyName', fileName='$fileName', file=$file)"
    }

    fun dispose() {
        logger.trace { "dispose" }
    }

}
