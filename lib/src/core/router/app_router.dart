import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/modern_login_page.dart';
import '../../features/dashboard/presentation/dashboard_wrapper_page.dart';
import '../../features/owner/presentation/owner_shell.dart';
import 'package:go_transitions/go_transitions.dart';
import '../../core/logging/app_logger.dart';

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// Default transition setup for the app
void _setDefaultTransitions() {
  GoTransition.defaultCurve = Curves.easeInOut;
  GoTransition.defaultDuration = const Duration(milliseconds: 300);
}

final routerProvider = Provider<GoRouter>((ref) {
  // Configure default transitions once
  _setDefaultTransitions();
  // Refresh router when the repository emits AppUser changes (ensures cache + role ready)
  final authStream = ref.read(authRepositoryProvider).authStateChanges();
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthNotifier(authStream),
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const _SplashGate(),
        pageBuilder: GoTransitions.fadeUpwards,
      ),
      GoRoute(
        path: '/',
        name: 'login',
        builder: (context, state) => const ModernLoginPage(),
  pageBuilder: GoTransitions.fadeUpwards,
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
  builder: (context, state) => const DashboardWrapperPage(),
  pageBuilder: GoTransitions.zoom,
      ),
      GoRoute(
        path: '/owner',
        name: 'owner',
  builder: (context, state) => const OwnerShell(),
  pageBuilder: GoTransitions.cupertino,
      ),
    ],
    redirect: (context, state) {
  if (state.matchedLocation == '/splash') return null; // let splash decide
      final atLogin = state.matchedLocation == '/' || state.fullPath == '/';
      final isLoggedIn = fb.FirebaseAuth.instance.currentUser != null;
      AppLogger.i.d('Router redirect check -> loc: ${state.matchedLocation}, atLogin: $atLogin, isLoggedIn: $isLoggedIn');
      if (!isLoggedIn) {
        AppLogger.i.d('Router redirect -> not logged in, to /');
        return atLogin ? null : '/';
      }
      // Prefer cached role-based target for instant redirects
      final cachedTarget = ref.read(cachedRedirectPathProvider);
      String? target = cachedTarget;
      if (target == null) {
        final authAsync = ref.read(authStateProvider);
        if (authAsync.hasValue && authAsync.value != null) {
          final role = authAsync.value!.role;
          target = (role == UserRole.projectOwner) ? '/owner' : '/dashboard';
        }
      }
      AppLogger.i.d('Router redirect -> target: ${target ?? '(none)'}');
      if (target != null && state.matchedLocation != target) return target;
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

class _SplashGate extends ConsumerWidget {
  const _SplashGate({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached = ref.read(cachedRedirectPathProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isLoggedIn = fb.FirebaseAuth.instance.currentUser != null;
      final target = isLoggedIn ? (cached ?? '/dashboard') : '/';
      AppLogger.i.d('SplashGate -> isLoggedIn: $isLoggedIn, cached: ${cached ?? '(none)'}, go: $target');
      if (context.mounted) context.go(target);
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
