import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/env/env_check.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('main: after ensureInitialized');
  await Firebase.initializeApp();
  print('Firebase initialized');

  // request notification permission (Android13+/iOS)
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
    } catch (e) {
      // ignore: avoid_print
      print('FCM permission request failed: $e');
    }
    // print token after permission
    FirebaseMessaging.instance.getToken().then((t) => print('FCM token: $t'));

    FirebaseMessaging.onMessage.listen((msg) {
      print('FCM onMessage: ${msg.notification?.title} ${msg.data}');
    });
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      print('FCM onMessageOpenedApp: ${msg.notification?.title} ${msg.data}');
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

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
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
