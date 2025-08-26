import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/dashboard/presentation/dashboard_wrapper_page.dart';
import '../../features/landing/presentation/landing_page.dart';
import '../../features/owner/presentation/owner_home_page.dart';

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(Stream<AppUser?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authStream = ref.watch(authStateProvider.stream);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthNotifier(authStream),
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        name: 'landing',
        pageBuilder: (context, state) => const NoTransitionPage(child: LandingPage()),
        routes: [
          GoRoute(
            path: 'login',
            name: 'login',
            pageBuilder: (context, state) => const NoTransitionPage(child: LoginPage()),
          ),
        ],
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        pageBuilder: (context, state) => const NoTransitionPage(child: DashboardWrapperPage()),
      ),
      GoRoute(
        path: '/owner',
        name: 'owner',
        pageBuilder: (context, state) => const NoTransitionPage(child: OwnerHomePage()),
      ),
    ],
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      final loggingIn = state.uri.toString().contains('/login');

      if (authAsync.isLoading || authAsync.hasError) return null;
      final user = authAsync.value;

      if (user == null) {
        // Not signed in: default to landing unless explicitly on /login
        if (loggingIn) return null;
        return '/';
      }

      // Signed in: route based on role
  final role = user.role;
      if (role == UserRole.superNodal || role == UserRole.subNodal || role == UserRole.devAdmin) {
        if (state.fullPath == '/dashboard') return null;
        return '/dashboard';
      }
      if (role == UserRole.projectOwner) {
        if (state.fullPath == '/owner') return null;
        return '/owner';
      }
      return null;
    },
    errorPageBuilder: (context, state) => MaterialPage(
      child: Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(state.error.toString())),
      ),
    ),
  );
});
