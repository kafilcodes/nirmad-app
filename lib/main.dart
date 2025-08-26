import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'src/core/router/app_router.dart';
import 'src/core/theme/app_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'src/core/i18n/locale_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load .env (bundled as asset, path declared in pubspec.yaml)
  await dotenv.load(fileName: ".env");
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
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goRouter = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'Nirmad',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
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
    );
  }
}
// The rest of the app is organized under /src
