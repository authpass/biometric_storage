package design.codeux.biometric_storage_example

import android.os.Bundle
import io.flutter.app.*

import io.flutter.plugins.GeneratedPluginRegistrant
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

class MainActivity: FlutterFragmentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    GeneratedPluginRegistrant.registerWith(this)
    logger.trace { "created MainActivity." }
  }
}
