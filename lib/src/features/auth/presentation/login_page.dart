import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_login/flutter_login.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';

// Local state for Terms & Conditions acceptance
final _tncAcceptedProvider = StateProvider<bool>((_) => false);

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          // Ensure background fills the entire viewport
      Positioned.fill(child: _LoginBackground()),
          Center(
            child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
              child: FlutterLogin(
                userType: LoginUserType.email,
                initialAuthMode: AuthMode.login,
                // Labels and messages
                title: null,
                messages: LoginMessages(
                  userHint: 'Email',
                  passwordHint: 'Password',
                  confirmPasswordHint: 'Confirm password',
                  loginButton: 'Sign in',
                  forgotPasswordButton: 'Forgot password?',
                  recoverPasswordButton: 'Send reset link',
                  goBackButton: 'Back',
                  confirmSignupIntro: 'Confirm your email',
                ),
                // Theme
                theme: LoginTheme(
                  // Remove the package's default blue page gradient; we draw our own background
                  pageColorLight: Colors.transparent,
                  pageColorDark: Colors.transparent,
                  primaryColor: cs.surface,
                  // Purplish accent to match the background
                  accentColor: const Color(0xFFB07CFF),
                  errorColor: cs.error,
                  titleStyle: theme.textTheme.headlineSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  bodyStyle: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  textFieldStyle: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                  // More breathing room in the card
                  cardInitialHeight: 520,
                  // Purple-ish sign-in button styling
                  buttonTheme: const LoginButtonTheme(
                    backgroundColor: Color(0xFF7A4AE0),
                    highlightColor: Color(0xFFB07CFF),
                    splashColor: Color(0xFFA06AF6),
                    elevation: 1.5,
                    highlightElevation: 2.5,
                  ),
                  inputTheme: InputDecorationTheme(
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.25),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: cs.outlineVariant, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: cs.outlineVariant, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: cs.primary, width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: cs.error, width: 1.5),
                    ),
                  ),
                  cardTheme: CardTheme(
                    color: cs.surface,
                    elevation: 8,
                    shadowColor: cs.shadow.withValues(alpha: 0.3),
                    margin: const EdgeInsets.only(top: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                // Custom header with logo + title + subtitle
                headerWidget: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 420;
                      final logoSize = isNarrow ? 56.0 : 72.0;
                      final titleStyle = theme.textTheme.titleLarge?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600);
                      final subtitleStyle = theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.4);
                      final isDark = theme.brightness == Brightness.dark;
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              'logo.svg',
                              width: logoSize,
                              height: logoSize,
                              colorFilter: ColorFilter.mode(
                                isDark ? Colors.white : Colors.black87,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text('Sign in', style: titleStyle, textAlign: TextAlign.center),
                            const SizedBox(height: 4),
                            Text(
                              'DHAMTARI DISTRICT ADMINISTRATION',
                              style: subtitleStyle,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Hide signup completely by not providing onSignup
                onLogin: (LoginData data) async {
                  final accepted = ref.read(_tncAcceptedProvider);
                  if (!accepted) return 'Please accept Terms & Conditions';
                  try {
                    final email = data.name.trim();
                    final password = data.password.trim();
                    if (email.isEmpty || password.isEmpty) return 'Email and password are required';
                    await ref.read(authRepositoryProvider).signIn(email, password);
                    // Immediately navigate based on role to avoid post-login success animation
                    final u = await ref.read(authRepositoryProvider).currentUser();
                    if (u != null && (context.mounted)) {
                      switch (u.role) {
                        case UserRole.devAdmin:
                        case UserRole.superNodal:
                        case UserRole.subNodal:
                          context.go('/dashboard');
                          break;
                        case UserRole.projectOwner:
                          context.go('/owner');
                          break;
                      }
                    }
                    return null;
                  } catch (e) {
                    final s = e.toString();
                    if (s.contains('wrong-password') || s.contains('invalid-credential')) return 'Invalid email or password';
                    if (s.contains('user-not-found')) return 'No user found for this email';
                    if (s.contains('too-many-requests')) return 'Too many attempts. Try later';
                    if (s.contains('network-request-failed')) return 'Network error. Check connection';
                    return 'Login failed';
                  }
                },
                onRecoverPassword: (String email) async {
                  if (email.trim().isEmpty) return 'Enter your email to receive a reset link';
                  try {
                    await ref.read(authRepositoryProvider).sendPasswordResetEmail(email.trim());
                    return null;
                  } catch (e) {
                    final s = e.toString();
                    if (s.contains('user-not-found')) return 'No user found for this email';
                    return 'Unable to send reset link';
                  }
                },
                // No-op; we already navigate in onLogin to remove the package's success transition
                onSubmitAnimationCompleted: () {},
                // Optional: remove extra debug controls in release
                showDebugButtons: false,
                // Avoid custom page transformer transitions that can cause odd blank states
                disableCustomPageTransformer: true,
                // In case the package shows providers section title
                hideProvidersTitle: true,
                // Better UX on web/smaller heights
                scrollable: true,
                // Place T&C inside the card under the password field, centered
                children: [
                  Builder(
                    builder: (context) {
                      final size = MediaQuery.of(context).size;
                      const cardHeight = 520.0;
                      final topOfCard = (size.height / 2) - (cardHeight / 2);
                      final top = topOfCard + cardHeight - 90; // position within the card near the bottom
                      return Positioned(
                        top: top,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Consumer(
                                    builder: (context, ref, _) {
                                      final accepted = ref.watch(_tncAcceptedProvider);
                                      return Checkbox(
                                        value: accepted,
                                        onChanged: (v) => ref.read(_tncAcceptedProvider.notifier).state = v ?? false,
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'I agree to the Terms & Conditions',
                                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackground extends StatefulWidget {
  const _LoginBackground();
  @override
  State<_LoginBackground> createState() => _LoginBackgroundState();
}

class _LoginBackgroundState extends State<_LoginBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorsLight = [
      const Color(0xFFA06AF6),
      const Color(0xFF7A4AE0),
      const Color(0xFFB07CFF),
    ];
    final colorsDark = [
      const Color(0xFF2B1B4B),
      const Color(0xFF1F1440),
      const Color(0xFF3A2A6A),
    ];
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final colors = isDark ? colorsDark : colorsLight;
        final c1 = Color.lerp(colors[0], colors[1], t)!;
        final c2 = Color.lerp(colors[1], colors[2], t)!;
        final c3 = Color.lerp(colors[2], colors[0], t)!;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.5, 1.0],
              colors: [c1, c2, c3],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
