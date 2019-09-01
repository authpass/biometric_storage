import 'dart:async';

import 'package:flutter/services.dart';

class BiometricStorage {
  static const MethodChannel _channel =
      const MethodChannel('biometric_storage');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
