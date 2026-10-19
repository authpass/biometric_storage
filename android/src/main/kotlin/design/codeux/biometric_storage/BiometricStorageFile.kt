package design.codeux.biometric_storage

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyProperties
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import kotlin.time.Duration

private val logger = PluginLog

data class InitOptions(
    val androidAuthenticationValidityDuration: Duration? = null,
    val authenticationRequired: Boolean = true,
    val androidBiometricOnly: Boolean = true
)

class BiometricStorageFile(
    context: Context,
    baseName: String,
    val options: InitOptions
) {

    companion object {
        /**
         * Name of directory inside private storage where all encrypted files are stored.
         */
        private const val DIRECTORY_NAME = "biometric_storage"
        private const val FILE_SUFFIX_V2 = ".v2.txt"

        /** A write in progress, renamed over the file once it is complete. */
        private const val SUFFIX_PARTIAL = ".partial"

        /**
         * Where a file goes when it cannot be decrypted: moved aside, not deleted, so a
         * wrong verdict costs a rename rather than the data. One per store; a later one
         * replaces it.
         */
        private const val SUFFIX_UNREADABLE = ".unreadable"

        /** 12 bytes of IV and 16 of tag; a file shorter than this holds no ciphertext. */
        private const val MIN_FILE_LENGTH = 12 + 16
    }

    private val masterKeyName = "${baseName}_master_key"
    private val fileNameV2 = "$baseName$FILE_SUFFIX_V2"
    private val fileV2: File
    private val partialFile: File
    private val unreadableFile: File

    private val cryptographyManager = CryptographyManager {
        setUserAuthenticationRequired(options.authenticationRequired)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val useStrongBox = context.packageManager.hasSystemFeature(
                PackageManager.FEATURE_STRONGBOX_KEYSTORE
            )
            setIsStrongBoxBacked(useStrongBox)
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

    init {
        val baseDir = File(context.filesDir, DIRECTORY_NAME)
        if (!baseDir.exists()) {
            baseDir.mkdirs()
        }
        fileV2 = File(baseDir, fileNameV2)
        partialFile = File(baseDir, fileNameV2 + SUFFIX_PARTIAL)
        unreadableFile = File(baseDir, fileNameV2 + SUFFIX_UNREADABLE)

        logger.trace { "Initialized $this with $options" }

        validateOptions()
    }

    private fun validateOptions() {
        if (options.androidAuthenticationValidityDuration == null && !options.androidBiometricOnly) {
            throw IllegalArgumentException("when androidAuthenticationValidityDuration is null, androidBiometricOnly must be true")
        }
    }

    fun cipherForEncrypt() = cryptographyManager.getInitializedCipherForEncryption(masterKeyName)
    /**
     * Null when there is nothing to decrypt: no file, a file too short to hold an IV
     * and a tag, or a file whose key the keystore positively says is gone. Only
     * [readFile] decides what to do about the last two; this runs on the main thread
     * for a CryptoObject store and must not touch the file.
     */
    fun cipherForDecrypt(): Cipher? {
        if (!fileV2.exists()) {
            logger.debug { "No file exists, no IV found. null cipher." }
            return null
        }
        if (fileV2.length() < MIN_FILE_LENGTH) {
            return null
        }
        return cryptographyManager.getInitializedCipherForDecryption(masterKeyName, fileV2)
    }

    fun exists() = fileV2.exists()

    @Synchronized
    fun writeFile(cipher: Cipher?, content: String) {
        // cipher will be null if user does not need authentication or valid period is > -1
        val useCipher = cipher ?: cipherForEncrypt()
        try {
            val encrypted = cryptographyManager.encryptData(content, useCipher)
            // Beside the file, synced, then renamed over it: a process killed or
            // a device losing power mid-write leaves the old file or the new one,
            // never half of either. Without the sync the rename can land before
            // the data does, and a power loss then leaves an empty file under
            // the real name.
            FileOutputStream(partialFile).use { out ->
                out.write(encrypted.encryptedPayload)
                out.fd.sync()
            }
            if (!partialFile.renameTo(fileV2)) {
                throw IOException("Could not move $partialFile over $fileV2")
            }
            logger.debug { "Successfully written ${encrypted.encryptedPayload.size} bytes." }

            return
        } catch (ex: IOException) {
            // Whatever is in the partial file is not a complete write.
            partialFile.delete()
            logger.error(ex) { "Error while writing encrypted file $fileV2" }
            throw ex
        }
    }

    /**
     * The file cannot be read and never will be, so a read answers "nothing stored"
     * and the next write starts clean — but the bytes are moved aside rather than
     * deleted. If the verdict was wrong (a keystore that answered "no key" while
     * restarting, say) the data is still on disk, and a bug report can see it.
     */
    private fun setAside(why: String) {
        logger.warn { "$fileV2 $why; moving it to $unreadableFile and treating it as absent." }
        unreadableFile.delete()
        if (!fileV2.renameTo(unreadableFile)) {
            throw IOException("Could not move $fileV2 aside to $unreadableFile")
        }
    }

    @Synchronized
    fun readFile(cipher: Cipher?): String? {
        if (!fileV2.exists()) {
            logger.debug { "File $fileV2 does not exist. returning null." }
            return null
        }
        if (fileV2.length() < MIN_FILE_LENGTH) {
            // Nothing a cipher could be asked about: an empty file after a power
            // loss, or a write torn before writes went through a partial file.
            setAside("is ${fileV2.length()} bytes, too short to hold an IV and a tag")
            return null
        }
        val useCipher = cipher ?: cipherForDecrypt()
        if (useCipher == null) {
            // The file outlived its key — restored from a backup onto another
            // device, which carries files and never keystore keys, or the key
            // was removed. Nothing can ever decrypt it. This is only reached on
            // the keystore's positive "no such key"; a keystore that could not
            // answer threw out of cipherForDecrypt and the file is untouched.
            setAside("has no key in the keystore")
            return null
        }
        return try {
            val bytes = fileV2.readBytes()
            logger.debug { "read ${bytes.size}" }
            cryptographyManager.decryptData(bytes, useCipher)
        } catch (ex: AEADBadTagException) {
            // The key is there but the file was not written with it: a key
            // minted over a restored file by an earlier version, or corrupt
            // bytes. KeyMint reports only a failed tag check this way; a
            // missing authorization or any other failure at doFinal surfaces
            // as IllegalBlockSizeException and is not caught here.
            logger.warn(ex) { "$fileV2 does not decrypt with its key" }
            setAside("does not decrypt with its key")
            null
        } catch (ex: IOException) {
            logger.error(ex) { "Error while reading encrypted file $fileV2" }
            null
        }
    }

    @Synchronized
    fun deleteFile(): Boolean {
        cryptographyManager.deleteKey(masterKeyName)
        partialFile.delete()
        unreadableFile.delete()
        return fileV2.delete()
    }

    override fun toString(): String {
        return "BiometricStorageFile(masterKeyName='$masterKeyName', fileName='$fileNameV2', file=$fileV2)"
    }

    fun dispose() {
        logger.trace { "dispose" }
    }

}
