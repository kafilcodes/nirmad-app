// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:nirmadapp/main.dart';
import 'package:nirmadapp/src/core/prefs/shared_prefs.dart';
import 'package:nirmadapp/src/core/theme/theme_controller.dart';
import 'package:nirmadapp/src/core/router/app_router.dart';
import 'package:nirmadapp/src/features/auth/presentation/login_page.dart';

void main() {
  testWidgets('App boots to landing page', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const LoginPage()),
      ],
      initialLocation: '/',
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        themeControllerProvider.overrideWith((ref) => ThemeController(prefs)),
        routerProvider.overrideWithValue(router),
      ],
      child: const MyApp(),
    ));
  // Avoid pumpAndSettle due to infinite background animation on login page
  await tester.pump(const Duration(milliseconds: 100));

  // Verify the login page renders
  expect(find.text('Sign in'), findsAtLeastNWidgets(1));
  expect(find.text('Email'), findsOneWidget);
  expect(find.text('Password'), findsOneWidget);

  // Let internal one-shot timers complete to avoid test pending timers
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pump();
  });
}
