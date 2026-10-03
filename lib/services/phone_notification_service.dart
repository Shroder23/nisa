import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PhoneNotificationService {
  PhoneNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final ValueNotifier<String?> tappedPayload = ValueNotifier<String?>(
    null,
  );
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        tappedPayload.value = response.payload;
      },
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'nisa_activity',
        'Nisa activity',
        description: 'Messages, interests, and verification updates',
        importance: Importance.high,
      ),
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      tappedPayload.value = launchDetails?.notificationResponse?.payload;
    }
    _initialized = true;
  }

  static Future<void> show({
    required String notificationId,
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    if (!_initialized ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final details = AndroidNotificationDetails(
      'nisa_activity',
      'Nisa activity',
      channelDescription: 'Messages, interests, and verification updates',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(body),
    );
    final id = notificationId.hashCode & 0x7fffffff;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: details),
      payload: jsonEncode(payload),
    );
  }
}
