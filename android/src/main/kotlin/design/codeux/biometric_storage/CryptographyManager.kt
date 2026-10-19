// based on https://github.com/isaidamier/blogs.biometrics.cryptoBlog/blob/cryptoObject/app/src/main/java/com/example/android/biometricauth/CryptographyManager.kt

/*
 * Copyright (C) 2020 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License
 */

package design.codeux.biometric_storage

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.io.IOException
import java.nio.charset.Charset
import java.security.KeyStore
import java.security.KeyStoreException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private val logger = PluginLog

interface CryptographyManager {

    /**
     * This method first gets or generates an instance of SecretKey and then initializes the Cipher
     * with the key. The secret key uses [ENCRYPT_MODE][Cipher.ENCRYPT_MODE] is used.
     */
    fun getInitializedCipherForEncryption(keyName: String): Cipher

    /**
     * A [Cipher] in [DECRYPT_MODE][Cipher.DECRYPT_MODE] for the existing key, or null when
     * the keystore positively reports that there is no such key. Decryption never creates a
     * key: a key minted here could not decrypt anything, and would make the file fail the
     * tag check for good. A keystore that could not answer throws, as it always did.
     */
    fun getInitializedCipherForDecryption(keyName: String, initializationVector: ByteArray): Cipher?
    fun getInitializedCipherForDecryption(keyName: String, encryptedDataFile: File): Cipher?

    /**
     * The Cipher created with [getInitializedCipherForEncryption] is used here
     */
    fun encryptData(plaintext: String, cipher: Cipher): EncryptedData

    /**
     * The Cipher created with [getInitializedCipherForDecryption] is used here
     */
    fun decryptData(ciphertext: ByteArray, cipher: Cipher): String

}

fun CryptographyManager(configure: KeyGenParameterSpec.Builder.() -> Unit): CryptographyManagerImpl = CryptographyManagerImpl(configure)

@Suppress("ArrayInDataClass")
data class EncryptedData(val encryptedPayload: ByteArray)

class CryptographyManagerImpl(
    private val configure: KeyGenParameterSpec.Builder.() -> Unit
) :
    CryptographyManager {

    companion object {

        private const val KEY_SIZE: Int = 256

        /**
         * Prefix for the key name, to distinguish it from previously written key.
         * kind of namespacing it.
         */
        private const val KEY_PREFIX = "_CM_"
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val ENCRYPTION_BLOCK_MODE = KeyProperties.BLOCK_MODE_GCM
        private const val ENCRYPTION_PADDING = KeyProperties.ENCRYPTION_PADDING_NONE
        private const val ENCRYPTION_ALGORITHM = KeyProperties.KEY_ALGORITHM_AES

        private const val IV_SIZE_IN_BYTES = 12
        private const val TAG_SIZE_IN_BYTES = 16

    }

    override fun getInitializedCipherForEncryption(keyName: String): Cipher {
        val cipher = getCipher()
        val secretKey = getOrCreateSecretKey(keyName)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        return cipher
    }

    override fun getInitializedCipherForDecryption(
        keyName: String,
        initializationVector: ByteArray
    ): Cipher? {
        val secretKey = getSecretKey(keyName) ?: return null
        val cipher = getCipher()
        cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(TAG_SIZE_IN_BYTES * 8, initializationVector))
        return cipher
    }
    override fun getInitializedCipherForDecryption(
        keyName: String,
        encryptedDataFile: File,
    ): Cipher? {
        val iv = ByteArray(IV_SIZE_IN_BYTES)
        val count = encryptedDataFile.inputStream().use { it.read(iv) }
        if (count != IV_SIZE_IN_BYTES) {
            throw IOException("$encryptedDataFile is too short to hold an IV ($count bytes)")
        }
        return getInitializedCipherForDecryption(keyName, iv)
    }

    override fun encryptData(plaintext: String, cipher: Cipher): EncryptedData {
        val input = plaintext.toByteArray(Charsets.UTF_8)
        val ciphertext = ByteArray(IV_SIZE_IN_BYTES + input.size + TAG_SIZE_IN_BYTES)
        val bytesWritten = cipher.doFinal(input, 0, input.size, ciphertext, IV_SIZE_IN_BYTES)
        cipher.iv.copyInto(ciphertext)
        assert(bytesWritten == input.size + TAG_SIZE_IN_BYTES)
        assert(cipher.iv.size == IV_SIZE_IN_BYTES)
        logger.debug { "encrypted ${input.size} (${ciphertext.size} output)" }
//        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return EncryptedData(ciphertext)
    }

    override fun decryptData(ciphertext: ByteArray, cipher: Cipher): String {
        logger.debug { "decrypting ${ciphertext.size} bytes (iv: ${IV_SIZE_IN_BYTES}, tag: ${TAG_SIZE_IN_BYTES})" }
        val iv = ciphertext.sliceArray(IntRange(0, IV_SIZE_IN_BYTES - 1))
        if (!iv.contentEquals(cipher.iv)) {
            throw IllegalStateException("expected first bytes of ciphertext to equal cipher iv.")
        }
        val plaintext = cipher.doFinal(ciphertext, IV_SIZE_IN_BYTES, ciphertext.size - IV_SIZE_IN_BYTES)
        return String(plaintext, Charset.forName("UTF-8"))
    }

    private fun getCipher(): Cipher {
        val transformation = "$ENCRYPTION_ALGORITHM/$ENCRYPTION_BLOCK_MODE/$ENCRYPTION_PADDING"
        return Cipher.getInstance(transformation)
    }

    /**
     * The key for [keyName], or null when the keystore positively reports that it does not
     * exist. Deliberately [KeyStore.getKey] and not [KeyStore.containsAlias]: on Android 12+
     * `containsAlias` answers false for *every* keystore failure except "not found" — the
     * daemon restarting, a locked user, a busy backend — while `getKey` throws for those and
     * returns null only for KEY_NOT_FOUND. A caller that removes data on a null here must
     * not be able to do so on a hiccup. (Below Android 12 both go through a binder `exist`
     * call that answers false on a lost connection; nothing on the API surface can tell the
     * two apart there, which is why the file is set aside rather than deleted.)
     */
    private fun getSecretKey(keyName: String): SecretKey? {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null) // Keystore must be loaded before it can be accessed
        return keyStore.getKey(KEY_PREFIX + keyName, null) as SecretKey?
    }

    fun deleteKey(keyName: String) {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null) // Keystore must be loaded before it can be accessed
        try {
            keyStore.deleteEntry(KEY_PREFIX + keyName)
        } catch (e: KeyStoreException) {
            logger.warn(e) { "Unable to delete key from KeyStore $KEY_PREFIX$keyName" }
        }
    }

    private fun getOrCreateSecretKey(keyName: String): SecretKey {
        getSecretKey(keyName)?.let { return it }

        // if you reach here, then a new SecretKey must be generated for that keyName
        val paramsBuilder = KeyGenParameterSpec.Builder(
            KEY_PREFIX + keyName,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
        paramsBuilder.apply {
            setBlockModes(ENCRYPTION_BLOCK_MODE)
            setEncryptionPaddings(ENCRYPTION_PADDING)
            setKeySize(KEY_SIZE)
            setUserAuthenticationRequired(true)
            configure()
        }

        val keyGenParams = paramsBuilder.build()
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEYSTORE
        )
        keyGenerator.init(keyGenParams)
        return keyGenerator.generateKey()
    }

}
