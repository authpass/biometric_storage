package design.codeux.biometric_storage_example

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

import io.flutter.plugins.GeneratedPluginRegistrant

// FlutterFragmentActivity, not FlutterActivity: androidx.biometric's
// BiometricPrompt hosts itself in a Fragment, so storage that shows a prompt
// needs a FragmentActivity underneath it.
class MainActivity: FlutterFragmentActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }
}
