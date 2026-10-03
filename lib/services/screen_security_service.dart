import 'package:flutter/services.dart';

class ScreenSecurityService {
  ScreenSecurityService._();

  static const _channel = MethodChannel('nisa_e_sakina/screen_security');

  static Future<void> setScreenshotBlocked(bool blocked) async {
    try {
      await _channel.invokeMethod<void>('setScreenshotBlocked', blocked);
    } on MissingPluginException {
      // The app currently targets Android. Keep the UI usable if the native
      // channel is unavailable during a hot restart or another platform test.
    } on PlatformException {
      // Screenshot blocking is a privacy enhancement, not a reason to stop
      // the user from viewing their own photo.
    }
  }
}
