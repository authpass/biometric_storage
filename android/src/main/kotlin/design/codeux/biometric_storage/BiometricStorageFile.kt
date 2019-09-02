package design.codeux.biometric_storage

import android.content.Context
import android.security.keystore.*
import androidx.security.crypto.*
import mu.KotlinLogging
import java.io.*

private val logger = KotlinLogging.logger {}

data class InitOptions(
    val authenticationValidityDurationSeconds: Int = 30
)

class BiometricStorageFile(
    context: Context,
    baseName: String,
    options: InitOptions
) {

    companion object {
        /**
         * Name of directory inside private storage where all encrypted files are stored.
         */
        private const val DIRECTORY_NAME = "biometric_storage"
        private const val FILE_SUFFIX = ".txt"
        private const val BACKUP_SUFFIX = "bak"
        private const val KEY_SIZE = 256
    }

    private val masterKeyName = "${baseName}_master_key"
    private val fileName = "$baseName$FILE_SUFFIX"
    private val file: File

    private val masterKeyAlias: String

    init {
        val paramSpec = createAES256GCMKeyGenParameterSpec(masterKeyName)
            .setUserAuthenticationRequired(true)
//            .setUserAuthenticationValidityDurationSeconds(3600)
            .setUserAuthenticationValidityDurationSeconds(options.authenticationValidityDurationSeconds)
            .build()
        masterKeyAlias = MasterKeys.getOrCreate(paramSpec)

        val baseDir = File(context.filesDir, DIRECTORY_NAME)
        if (!baseDir.exists()) {
            baseDir.mkdirs()
        }
        file = File(baseDir, fileName)

        logger.trace { "Initialized $this with $options" }
    }


    private fun buildEncryptedFile(context: Context) =
        EncryptedFile.Builder(
            file,
            context,
            masterKeyAlias,
            EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB
        ).build()

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
        val encryptedFile = buildEncryptedFile(context)

        val bytes = encryptedFile.openFileInput().use { input ->
            input.readBytes()
        }
        return String(bytes)
    }

    // Copied from androidx.security.crypto.MasterKeys (1.0.0-alpha02)

    private fun createAES256GCMKeyGenParameterSpec(
        keyAlias: String
    ): KeyGenParameterSpec.Builder {
        return KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(KEY_SIZE)
    }

    override fun toString(): String {
        return "BiometricStorageFile(masterKeyName='$masterKeyName', fileName='$fileName', file=$file, masterKeyAlias='$masterKeyAlias')"
    }

}
