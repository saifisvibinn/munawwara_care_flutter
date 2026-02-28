import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/env/env_check.dart';
import 'core/services/notification_service.dart';
import 'features/auth/providers/auth_provider.dart';

// Global FCM token
String? _globalFcmToken;

// Global navigator key for navigating from CallKit callbacks
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('main: after ensureInitialized');

  await Firebase.initializeApp();
  print('Firebase initialized');

  // ── Initialize Notification Service ───────────────────────────────────────
  await NotificationService.instance.initialize();
  print('Notification service initialized');

  // ── Set up Firebase Background Message Handler ────────────────────────────
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  print('Background message handler registered');

  // ── Listen for CallKit events (accept/decline/timeout) ────────────────────
  _setupCallKitListeners();

  // ── Request Notification Permissions ──────────────────────────────────────
  print('main: requesting fcm permission');
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // Request local notification permissions
      await NotificationService.instance.requestPermissions();
    } catch (e) {
      print('FCM permission request failed: $e');
    }

    // ── Get and Store FCM Token ───────────────────────────────────────────────
    _globalFcmToken = await FirebaseMessaging.instance.getToken();
    print('FCM token: $_globalFcmToken');

    // ── Handle Token Refresh ──────────────────────────────────────────────────
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _globalFcmToken = newToken;
      print('FCM token refreshed: $newToken');
    });

    // ── Handle Foreground Messages ──────────────────────────────────────────
    FirebaseMessaging.onMessage.listen((msg) async {
      print('FCM onMessage: ${msg.notification?.title} ${msg.data}');
      // Show local notification even when app is in foreground
      await NotificationService.instance.showNotificationFromMessage(msg);
    });

    // ── Handle Message Opened App ───────────────────────────────────────────
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      print('FCM onMessageOpenedApp: ${msg.notification?.title} ${msg.data}');
    });

    // ── Handle Initial Message (App opened from terminated state) ──────────
    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg != null) {
        print('FCM getInitialMessage: ${msg.notification?.title} ${msg.data}');
      }
    });
  }

  // Prevent GoogleFonts from making network requests at runtime.
  // Fonts are served from the local cache only — avoids ANR on emulators.
  GoogleFonts.config.allowRuntimeFetching = false;
  print('main: initializing EasyLocalization');
  await EasyLocalization.ensureInitialized();
  print('main: loading dotenv');
  await dotenv.load(fileName: '.env');
  print('main: verifying env');
  await verifyEnv();
  print('main: screenutil ensureScreenSize');
  await ScreenUtil.ensureScreenSize();

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
        Locale('ur'),
        Locale('fr'),
        Locale('id'), // Bahasa
        Locale('tr'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const ProviderScope(child: MyApp()),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CallKit Event Listeners — handles accept/decline from native call screen
// ─────────────────────────────────────────────────────────────────────────────

void _setupCallKitListeners() {
  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
    if (event == null) return;
    print('📞 CallKit event: ${event.event}');
    print('   Body: ${event.body}');

    switch (event.event) {
      case Event.actionCallAccept:
        print('✅ Call ACCEPTED from native call screen');
        // Store the accepted call info so the call provider can pick it up
        final extra = event.body?['extra'] as Map<dynamic, dynamic>? ?? {};
        _pendingAcceptedCall = {
          'callerId': extra['callerId']?.toString() ?? '',
          'callerName': extra['callerName']?.toString() ?? 'Unknown',
          'channelName': extra['channelName']?.toString() ?? '',
          'callerRole': extra['callerRole']?.toString() ?? '',
        };
        print('   Pending call data: $_pendingAcceptedCall');
        break;

      case Event.actionCallDecline:
        print('❌ Call DECLINED from native call screen');
        _pendingAcceptedCall = null;
        break;

      case Event.actionCallTimeout:
        print('⏰ Call TIMEOUT from native call screen');
        _pendingAcceptedCall = null;
        break;

      case Event.actionCallEnded:
        print('📵 Call ENDED from native call screen');
        _pendingAcceptedCall = null;
        break;

      default:
        break;
    }
  });
}

/// Pending call data set when user accepts from native call screen.
/// The call provider reads this to know which call to join.
Map<String, String>? _pendingAcceptedCall;

/// Get and clear the pending accepted call data.
Map<String, String>? consumePendingAcceptedCall() {
  final data = _pendingAcceptedCall;
  _pendingAcceptedCall = null;
  return data;
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    // ── Register FCM Token when user logs in ──────────────────────────────────
    ref.listen<AuthState>(authProvider, (previous, next) {
      // When user becomes authenticated and we have an FCM token, register it
      if (next.isAuthenticated && _globalFcmToken != null) {
        ref.read(authProvider.notifier).updateFcmToken(_globalFcmToken!);
      }
    });

    return ScreenUtilInit(
      designSize: const Size(393, 852),
      minTextAdapt: true,
      ensureScreenSize: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: 'Munawwara Care',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          routerConfig: AppRouter.router,
        );
      },
    );
  }
}
