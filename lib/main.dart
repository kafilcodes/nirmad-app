import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'src/core/router/app_router.dart';
import 'src/core/theme/app_theme.dart';
import 'src/core/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'src/services/messaging_service.dart';
import 'src/core/prefs/shared_prefs.dart';
import 'src/core/bootstrap/bootstrap_prefetch.dart';
import 'package:toastification/toastification.dart';
import 'src/core/logging/app_logger.dart';
import 'package:logger/logger.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'src/core/widgets/offline_monitor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Surface all uncaught errors to the console with context (helps on web release builds)
  FlutterError.onError = (FlutterErrorDetails details) {
    // Forward Flutter framework errors to the zone handler below
    Zone.current.handleUncaughtError(details.exception, details.stack ?? StackTrace.current);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    // Ensure top-level uncaught errors still print something useful
    // Avoid leaking secrets; we only log error type/message
    // ignore: avoid_print
    print('Top-level error: ' + error.toString());
    // ignore: avoid_print
    print(stack.toString());
    return true; // handled
  };
  // Configure logging early (quiet in release)
  Logger.level = kReleaseMode ? Level.off : Level.debug;
  AppLogger.i.i('Booting Nirmad app');
  // Load .env (bundled as asset, path declared in pubspec.yaml)
  try {
    await dotenv.load(fileName: ".env");
  } catch (e, st) {
    // ignore: avoid_print
    print('dotenv load error: ' + e.toString());
    // ignore: avoid_print
    print(st.toString());
    rethrow;
  }
  // Init Hive (for offline draft media)
  try { await Hive.initFlutter(); } catch (_) {}
  // Initialize Firebase
  if (kIsWeb) {
    try {
      final apiKey = dotenv.maybeGet('FIREBASE_API_KEY');
      final projectId = dotenv.maybeGet('FIREBASE_PROJECT_ID');
      final appId = dotenv.maybeGet('FIREBASE_APP_ID');
      final msgSenderId = dotenv.maybeGet('FIREBASE_MESSAGING_SENDER_ID');
      final authDomain = dotenv.maybeGet('FIREBASE_AUTH_DOMAIN');
      final storageBucket = dotenv.maybeGet('FIREBASE_STORAGE_BUCKET');
      if ([apiKey, projectId, appId, msgSenderId].any((v) => (v == null || v.isEmpty))) {
        // ignore: avoid_print
        print('FirebaseOptions missing required keys. projectId=$projectId, appId=$appId, senderId=$msgSenderId, authDomain=$authDomain, bucket=$storageBucket');
        throw StateError('Missing FirebaseOptions keys from .env');
      }
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: apiKey!,
          authDomain: authDomain,
          projectId: projectId!,
          storageBucket: storageBucket,
          messagingSenderId: msgSenderId!,
          appId: appId!,
          measurementId: dotenv.maybeGet('FIREBASE_MEASUREMENT_ID'),
        ),
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('Firebase.initializeApp (web) failed: ' + e.toString());
      // ignore: avoid_print
      print(st.toString());
      rethrow;
    }
    // Log configured storage bucket for diagnostics (no normalization)
    try {
      final bucket = Firebase.app().options.storageBucket;
      AppLogger.i.i('Firebase storageBucket: ${bucket ?? '(none)'}');
    } catch (_) {}
  } else {
    // On mobile/desktop, this uses platform-specific configuration files if present.
    try {
      await Firebase.initializeApp();
    } catch (e, st) {
      // ignore: avoid_print
      print('Firebase.initializeApp (native) failed: ' + e.toString());
      // ignore: avoid_print
      print(st.toString());
      rethrow;
    }
  }
  // Enable offline persistence
  try {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  } catch (_) {
    // ignore if unavailable (e.g., unsupported platform)
  }
  // Initialize Firebase Messaging (FCM) after Firebase init
  try {
    await MessagingService.init();
  } catch (e) {
    // Don’t block app startup if messaging fails (e.g., missing service worker on web)
  }
  // Do not prompt for permissions at startup. Request contextually when a feature needs it.
  // Optionally, re-register token on sign-in
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;
    try {
      await MessagingService.init();
    } catch (_) {}
  });
  final prefs = await SharedPreferences.getInstance();
  runZonedGuarded(() {
    runApp(ProviderScope(
      overrides: [
        themeControllerProvider.overrideWith((ref) => ThemeController(prefs)),
        sharedPrefsProvider.overrideWithValue(prefs),
      ],
      child: const MyApp(),
    ));
  }, (error, stack) {
    // ignore: avoid_print
    print('Uncaught zone error: ' + error.toString());
    // ignore: avoid_print
    print(stack.toString());
  });
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
  final goRouter = ref.watch(routerProvider);
    // Kick off app warmup (disk-first snapshots, user doc, first page lists)
    ref.watch(bootstrapPrefetchProvider);
    final themeMode = ref.watch(themeControllerProvider);
    return ToastificationWrapper(
      child: OfflineMonitor(
        child: DefaultTextHeightBehavior(
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: true,
            applyHeightToLastDescent: true,
            leadingDistribution: TextLeadingDistribution.even,
          ),
          child: MaterialApp.router(
      title: 'Nirmad',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: goRouter,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
  supportedLocales: const [Locale('en')],
      debugShowCheckedModeBanner: false,
          ),
        ),
      ),
    );
  }
}
// The rest of the app is organized under /src
