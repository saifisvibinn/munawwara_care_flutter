import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'callkit_service.dart';
import '../../core/utils/app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Background Message Handler
// MUST be a top-level function (not in a class)
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.i('📩 Background message received: ${message.messageId}');
  AppLogger.i('   Title: ${message.notification?.title}');
  AppLogger.i('   Body: ${message.notification?.body}');
  AppLogger.i('   Data: ${message.data}');

  // ── Incoming call → show native call screen (like WhatsApp) ─────────────
  final handled = await CallKitService.handleFcmMessage(message);
  if (handled) return; // CallKit took over, don't show regular notification

  // ── Other messages → show local notification ────────────────────────────
  await NotificationService.instance.initialize();
  await NotificationService.instance.showNotificationFromMessage(message);
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification Service
// Handles local notifications, channels, sounds, and incoming call alerts
// ─────────────────────────────────────────────────────────────────────────────

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ── Initialize ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }

    _initialized = true;
    AppLogger.i('✅ NotificationService initialized');
  }

  // ── Create Android Notification Channels ──────────────────────────────────

  Future<void> _createNotificationChannels() async {
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin == null) return;

    // Default channel for regular messages
    const defaultChannel = AndroidNotificationChannel(
      'default',
      'Default Notifications',
      description: 'General notifications for messages and updates',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    // Urgent channel with custom sound
    final urgentChannel = AndroidNotificationChannel(
      'urgent',
      'Urgent Notifications',
      description: 'High-priority urgent messages and alerts',
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('urgent'),
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFFF97316), // AppColors.primary
    );

    // Call channel with full-screen intent
    final callChannel = AndroidNotificationChannel(
      'calls',
      'Incoming Calls',
      description: 'Incoming voice calls',
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('urgent'),
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFF10B981),
    );

    await androidPlugin.createNotificationChannel(defaultChannel);
    await androidPlugin.createNotificationChannel(urgentChannel);
    await androidPlugin.createNotificationChannel(callChannel);

    AppLogger.i('✅ Notification channels created');
  }

  // ── Show Notification from FCM Message ────────────────────────────────────

  Future<void> showNotificationFromMessage(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    final type = data['type'] ?? 'normal';

    // Determine title and body
    String title = notification?.title ?? data['title'] ?? 'Munawwara Care';
    String body = notification?.body ?? data['body'] ?? '';

    AppLogger.d('🔔 Processing FCM message:');
    AppLogger.d('   Type: $type');
    AppLogger.d('   Title: $title');
    AppLogger.d('   Body: $body');
    AppLogger.d('   Has notification block: ${notification != null}');
    AppLogger.d('   Data keys: ${data.keys.toList()}');

    // Handle incoming call → route to native CallKit screen
    if (type == 'incoming_call') {
      AppLogger.i('📞 INCOMING CALL DETECTED → routing to native call screen');
      await CallKitService.handleFcmMessage(message);
      return;
    }

    // Handle urgent notifications
    if (type == 'urgent') {
      AppLogger.w('🚨 Urgent notification detected');
      await _showUrgentNotification(title: title, body: body, data: data);
      return;
    }

    // Default notification
    AppLogger.i('📬 Default notification');
    await _showDefaultNotification(title: title, body: body, data: data);
  }

  // (Incoming call notifications are now handled by CallKitService)

  // ── Show Urgent Notification ──────────────────────────────────────────────

  Future<void> _showUrgentNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    AppLogger.w('🚨 Showing urgent notification');

    final androidDetails = AndroidNotificationDetails(
      'urgent',
      'Urgent Notifications',
      channelDescription: 'High-priority urgent messages and alerts',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('urgent'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 250, 500]),
      enableLights: true,
      color: const Color(0xFFF97316),
      icon: '@mipmap/ic_launcher',
      styleInformation: const BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'urgent.wav',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: _encodePayload(data),
    );
  }

  // ── Show Default Notification ─────────────────────────────────────────────

  Future<void> _showDefaultNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    AppLogger.i('📬 Showing default notification');

    const androidDetails = AndroidNotificationDetails(
      'default',
      'Default Notifications',
      channelDescription: 'General notifications for messages and updates',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: _encodePayload(data),
    );
  }

  // (Ringtone is now handled by flutter_callkit_incoming native call screen)

  // ── Cancel Notification ────────────────────────────────────────────────────

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  // ── Notification Tap Handler ──────────────────────────────────────────────

  void _onNotificationTap(NotificationResponse response) {
    AppLogger.i('📱 Notification tapped: ${response.payload}');

    if (response.actionId == 'accept_call') {
      AppLogger.i('✅ Accept call action');
      // TODO: Navigate to incoming call screen or trigger accept
    } else if (response.actionId == 'decline_call') {
      AppLogger.i('❌ Decline call action');
      // TODO: Trigger call decline
    } else {
      // Regular notification tap - navigate to app
      AppLogger.i('📖 Opening app from notification');
    }
  }

  // ── Helper: Encode Payload ────────────────────────────────────────────────

  String _encodePayload(Map<String, dynamic> data) {
    try {
      return data.entries.map((e) => '${e.key}=${e.value}').join('&');
    } catch (e) {
      return '';
    }
  }

  // ── Request Permissions ────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidPlugin != null) {
        // Request notification permission
        final notifGranted = await androidPlugin
            .requestNotificationsPermission();
        AppLogger.i('📱 Notification permission: $notifGranted');

        // Request exact alarms permission (for scheduling)
        await androidPlugin.requestExactAlarmsPermission();

        // ── CRITICAL: Request Full-Screen Intent Permission ──────────────────
        // This is REQUIRED on Android 10+ (API 29+) to show full-screen call UI
        // Without this, incoming calls will only show as regular notifications
        final fullScreenGranted = await androidPlugin
            .requestFullScreenIntentPermission();
        AppLogger.i('📱 Full-screen intent permission: $fullScreenGranted');

        if (fullScreenGranted == false) {
          AppLogger.w('⚠️ WARNING: Full-screen intent permission denied!');
          AppLogger.w('   Incoming calls will NOT show full-screen call UI');
          AppLogger.w(
            '   User must enable in Settings > Apps > Munawwara Care > Notifications',
          );
        }
      }
      return true;
    } else if (Platform.isIOS) {
      final iosPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      return await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }
}
