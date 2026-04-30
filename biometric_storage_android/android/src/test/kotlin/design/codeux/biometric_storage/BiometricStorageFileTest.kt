package design.codeux.biometric_storage

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.ProviderException

class BiometricStorageFileTest {

    @Test
    fun `encodes unsafe Android storage names into flat file names`() {
        val fileName = androidStorageFileName("g/Owg7F/hx8=nonce")

        assertTrue(fileName.endsWith(".v2.txt"))
        assertTrue(fileName.startsWith("_encoded_"))
        assertFalse(fileName.removeSuffix(".v2.txt").contains('/'))
        assertFalse(fileName.removeSuffix(".v2.txt").contains('\\'))
    }

    @Test
    fun `keeps safe Android storage names unchanged`() {
        assertEquals("plain-name.v2.txt", androidStorageFileName("plain-name"))
    }

    @Test
    fun `retries without StrongBox after provider exception`() {
        var deleted = false
        var strongBoxDisabled = false
        var attempts = 0

        val result = retryWithoutStrongBoxIfNeeded(
            useStrongBoxBackedKeystore = true,
            deleteKey = { deleted = true },
            disableStrongBox = { strongBoxDisabled = true },
        ) {
            attempts += 1
            if (attempts == 1) {
                throw ProviderException("Keystore key generation failed")
            }
            "ok"
        }

        assertEquals("ok", result)
        assertEquals(2, attempts)
        assertTrue(deleted)
        assertTrue(strongBoxDisabled)
    }

    @Test
    fun `does not retry when StrongBox is already disabled`() {
        var attempts = 0
        val error = ProviderException("Keystore key generation failed")

        val thrown = runCatching {
            retryWithoutStrongBoxIfNeeded(
                useStrongBoxBackedKeystore = false,
                deleteKey = { throw AssertionError("deleteKey should not be called") },
                disableStrongBox = { throw AssertionError("disableStrongBox should not be called") },
            ) {
                attempts += 1
                throw error
            }
        }.exceptionOrNull()

        assertSame(error, thrown)
        assertEquals(1, attempts)
    }
}