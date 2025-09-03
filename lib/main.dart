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
import 'src/core/i18n/locale_provider.dart';
import 'src/services/messaging_service.dart';
import 'src/core/prefs/shared_prefs.dart';
import 'package:toastification/toastification.dart';
import 'src/core/logging/app_logger.dart';
import 'src/utils/firebase_storage_bucket.dart';
import 'package:logger/logger.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Configure logging early
  Logger.level = Level.debug;
  AppLogger.i.i('Booting Nirmad app');
  // Load .env (bundled as asset, path declared in pubspec.yaml)
  await dotenv.load(fileName: ".env");
  // Init Hive (for offline draft media)
  try { await Hive.initFlutter(); } catch (_) {}
  // Initialize Firebase
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: dotenv.get('FIREBASE_API_KEY'),
  authDomain: dotenv.maybeGet('FIREBASE_AUTH_DOMAIN'),
  projectId: dotenv.get('FIREBASE_PROJECT_ID'),
  storageBucket: dotenv.maybeGet('FIREBASE_STORAGE_BUCKET'),
        messagingSenderId: dotenv.get('FIREBASE_MESSAGING_SENDER_ID'),
        appId: dotenv.get('FIREBASE_APP_ID'),
        measurementId: dotenv.maybeGet('FIREBASE_MEASUREMENT_ID'),
      ),
    );
    // Log resolved storage bucket for diagnostics
    try {
      final bucket = Firebase.app().options.storageBucket;
      final normalized = normalizeStorageBucket(bucket);
      AppLogger.i.i('Firebase storageBucket: ${bucket ?? '(none)'} -> normalized: ${normalized.isEmpty ? '(none)' : normalized}');
    } catch (_) {}
  } else {
    // On mobile/desktop, this uses platform-specific configuration files if present.
    await Firebase.initializeApp();
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
  // Optionally, re-register token on sign-in and refresh/clear avatar URL
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;
    try {
      await MessagingService.init();
    } catch (_) {}
    // One-time avatar URL migration: resolve fresh URL from storage or clear invalid legacy URL
    try {
      final uid = user.uid;
      final storage = storageForCurrentApp();
      final ref = storage.ref().child('users/$uid/avatar.jpg');
      try {
        final fresh = await ref.getDownloadURL();
        if (fresh.isNotEmpty && fresh != user.photoURL) {
          await user.updatePhotoURL(fresh);
          await FirebaseFirestore.instance.collection('users').doc(uid)
              .set({'photoUrl': fresh, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
          AppLogger.i.i('Migrated avatar URL to fresh download URL');
        }
      } catch (e) {
        final raw = user.photoURL ?? '';
        if (raw.contains('.firebasestorage.app')) {
          await user.updatePhotoURL(null);
          await FirebaseFirestore.instance.collection('users').doc(uid)
              .set({'photoUrl': FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
          AppLogger.i.i('Cleared invalid avatar URL');
        }
      }
    } catch (_) {}
  });
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [
      themeControllerProvider.overrideWith((ref) => ThemeController(prefs)),
  sharedPrefsProvider.overrideWithValue(prefs),
    ],
    child: const MyApp(),
  ));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goRouter = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeControllerProvider);
    return ToastificationWrapper(
      child: MaterialApp.router(
      title: 'Nirmad',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: goRouter,
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
      ],
      debugShowCheckedModeBanner: false,
      ),
    );
  }
}
// The rest of the app is organized under /src
