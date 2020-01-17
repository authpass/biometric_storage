package design.codeux.biometric_storage_example

import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

import io.flutter.plugins.GeneratedPluginRegistrant
import mu.KotlinLogging

private val logger = KotlinLogging.logger {}

class MainActivity: FlutterFragmentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    logger.trace { "created MainActivity." }
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }
}
