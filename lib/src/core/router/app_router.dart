import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/dashboard/presentation/dashboard_wrapper_page.dart';
import '../../features/owner/presentation/owner_shell.dart';

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
  // Avoid using deprecated Provider.stream; subscribe to the repository stream directly for refresh
  final authStream = ref.read(authRepositoryProvider).authStateChanges();
  final initial = ref.read(cachedRedirectPathProvider) ?? '/';
  return GoRouter(
    initialLocation: initial,
    refreshListenable: _AuthNotifier(authStream),
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        builder: (context, state) => const DashboardWrapperPage(),
      ),
      GoRoute(
        path: '/owner',
        name: 'owner',
        builder: (context, state) => const OwnerShell(),
      ),
    ],
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      final loggingIn = state.fullPath == '/';
      // Fast path: if unauth and on '/', consider cached user to jump early
      if (loggingIn && (authAsync.isLoading || (!authAsync.hasValue && !authAsync.hasError))) {
        final cached = ref.read(cachedRedirectPathProvider);
        if (cached != null) return cached;
      }

      // If loading, we still allow immediate redirect to '/' when user becomes null on sign-out
      // otherwise avoid jitter by returning null during loading
      if (authAsync.isLoading) {
  // While loading, keep current route; auth notifier will refresh once state resolves.
        return null;
      }
      if (authAsync.hasError) {
        // In case the auth stream errors, do not spin forever
        return loggingIn ? null : '/';
      }
      final user = authAsync.value;

      if (user == null) {
        // Not signed in: always show login at '/' (instant on web)
        return '/';
      }

  // Signed in: route based on role; default to dashboard unless project owner
  final role = user.role;
      if (role == UserRole.superNodal || role == UserRole.subNodal || role == UserRole.devAdmin) {
        if (state.fullPath == '/dashboard') return null;
        return '/dashboard';
      }
      if (role == UserRole.projectOwner) {
        if (state.fullPath == '/owner') return null;
        return '/owner';
      }
  // Unknown role, send to login (safe fallback)
  return '/';
    },
    errorPageBuilder: (context, state) => MaterialPage(
      child: Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(state.error.toString())),
      ),
    ),
  );
});
