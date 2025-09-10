import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import '../domain/app_user.dart';
import '../../../services/permission_service.dart';

class ModernLoginPage extends ConsumerStatefulWidget {
  const ModernLoginPage({super.key});

  @override
  ConsumerState<ModernLoginPage> createState() => _ModernLoginPageState();
}

class _ModernLoginPageState extends ConsumerState<ModernLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _rememberMe = true;
  bool _loading = false;
  // Permissions are not required to login; we track them only to offer quick-fix later.
  bool _permissionsOk = true;
  List<String> _missing = const [];

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final ok = await PermissionService.allGranted();
    final miss = ok ? const <String>[] : await PermissionService.missingPermissions();
    if (!mounted) return;
    setState(() {
      _permissionsOk = ok;
      _missing = miss;
    });
  }

  String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return 'Authentication failed (${e.code}).';
    }
  }

  Future<void> _signIn() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).signIn(
            _emailCtrl.text.trim(),
            _passwordCtrl.text,
          );
      // Immediate, reliable navigation with final role
      if (!mounted) return;
      try {
        // Wait for Firebase to publish auth change
        await FirebaseAuth.instance.authStateChanges().firstWhere((u) => u != null);
      } catch (_) {}
      // Prefer cached redirect; if missing, compute from currentUser()
      String? target = ref.read(cachedRedirectPathProvider);
      target ??= () {
        // Best-effort synchronous mapping from current user role
        return null;
      }();
      if (target == null) {
        try {
          final app = await ref.read(authRepositoryProvider).currentUser();
          if (app != null) {
            target = app.role == UserRole.projectOwner ? '/owner' : '/dashboard';
          }
        } catch (_) {}
      }
      if (target != null) {
        // ignore: use_build_context_synchronously
  context.go(target);
      }
    } on FirebaseAuthException catch (e) {
      final msg = _mapFirebaseError(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      final err = e.toString();
      // Detect our single-device guard error and offer takeover
      final conflict = err.contains('already active on another device');
      if (mounted && conflict) {
        final confirmedPassword = await showDialog<String?>(
          context: context,
          builder: (ctx) {
            final confirmCtrl = TextEditingController();
            final formKey = GlobalKey<FormState>();
            return AlertDialog(
              title: const Text('Active session detected'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('This account is signed in on another device. To continue here, confirm your password. The other device will be logged out immediately.'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (v) => (v == null || v.length < 6) ? 'Enter your password' : null,
                    ),
                  ],
                ),
              ),
              actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
          Navigator.pop(ctx, confirmCtrl.text);
                    }
                  },
                  child: const Text('Continue here'),
                ),
              ],
            );
          },
        );
    if (confirmedPassword != null) {
          try {
            await ref.read(authRepositoryProvider).forceSignInTakeover(
                  _emailCtrl.text.trim(),
      confirmedPassword,
                );
            if (!mounted) return;
            // Navigate as in normal sign-in
            try {
              await FirebaseAuth.instance.authStateChanges().firstWhere((u) => u != null);
            } catch (_) {}
            String? target = ref.read(cachedRedirectPathProvider);
            if (target == null) {
              try {
                final app = await ref.read(authRepositoryProvider).currentUser();
                if (app != null) {
                  target = app.role == UserRole.projectOwner ? '/owner' : '/dashboard';
                }
              } catch (_) {}
            }
            if (target != null) context.go(target);
          } on FirebaseAuthException catch (e2) {
            final msg = _mapFirebaseError(e2);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            }
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to continue here. Try again.')));
            }
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Something went wrong. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter your email to reset password.')));
      return;
    }
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset link sent.')));
      }
    } on FirebaseAuthException catch (e) {
      final msg = _mapFirebaseError(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _AnimatedBackdrop(isDark: isDark),
          // Small header mark: Dhamtari district logo (login-only)
          // Dhamtari district logo removed from login page per spec.
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1000;
                final card = _AuthCard(
                  formKey: _formKey,
                  emailCtrl: _emailCtrl,
                  passwordCtrl: _passwordCtrl,
                  obscure: _obscure,
                  onToggleObscure: () => setState(() => _obscure = !_obscure),
                  rememberMe: _rememberMe,
                  onRememberChanged: (v) => setState(() => _rememberMe = v),
                  onSubmit: _signIn,
                  onForgotPassword: _resetPassword,
                  loading: _loading,
                  permissionsOk: _permissionsOk,
                  onFixPermissions: () async {
                    final ok = await PermissionService.requestCorePermissions();
                    await _refreshPermissions();
                    if (!ok && mounted) {
                      final list = _missing.isEmpty ? 'required permissions' : _missing.join(', ');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Please grant $list to continue.')),
                      );
                    }
                  },
                  missing: _missing,
                );

                if (!isWide) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _BrandHeader(withCopy: true),
                            const Gap(12),
                            card,
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Expanded(child: _BrandHeader(alignStart: true, withCopy: false)),
                          const Gap(40),
                          Flexible(child: card),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({this.alignStart = false, this.withCopy = false});
  final bool alignStart;
  final bool withCopy; // show welcome + paragraph beside logo

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = MediaQuery.of(context).size.width;
    final bool small = w < 600;
    final bool medium = w >= 600 && w < 1000;
    final double pad = small ? 8 : (medium ? 24 : 40);
    final double logoSize = small ? 240 : (medium ? 340 : 450);
  final double bottomPad = small ? 0 : (medium ? 0 : 2);
  final double copyGap = small ? 2 : (medium ? 4 : 6);
    final double copyMaxWidth = small ? 520 : 560;

  Widget logo = Padding(
      padding: EdgeInsets.only(left: pad, right: pad, top: pad, bottom: bottomPad),
      child: SizedBox(
        width: logoSize,
        height: logoSize,
    child: Builder(builder: (context) {
  // Primary login logo is always Nirmad (app brand)
  const asset = 'assets/logo.png';
  return Image.asset(asset, fit: BoxFit.contain);
    }),
      ),
    ).animate().fadeIn(duration: 250.ms).moveY(begin: 6, end: 0);

  Widget? copy;
  if (withCopy && small) {
      copy = Transform.translate(
        offset: Offset(0, small ? -18 : (medium ? -26 : -34)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: copyMaxWidth),
          child: Column(
            crossAxisAlignment: alignStart ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Text(
                'Welcome back',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                textAlign: alignStart ? TextAlign.start : TextAlign.center,
              ).animate().fadeIn(duration: 300.ms).moveY(begin: 6, end: 0),
              const SizedBox(height: 2),
              Text(
                'Sign in to continue managing your projects effortlessly.',
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: alignStart ? TextAlign.start : TextAlign.center,
              ).animate().fadeIn(duration: 450.ms).moveY(begin: 10, end: 0),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: alignStart ? Alignment.centerLeft : Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignStart ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          logo,
          if (copy != null) ...[Gap(copyGap), copy],
        ],
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.formKey,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.rememberMe,
    required this.onRememberChanged,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.loading,
  required this.permissionsOk,
  required this.onFixPermissions,
  required this.missing,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool rememberMe;
  final ValueChanged<bool> onRememberChanged;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onForgotPassword;
  final bool loading;
  final bool permissionsOk;
  final Future<void> Function() onFixPermissions;
  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final radius = 20.0;
    return Card(
      elevation: 0,
  color: theme.colorScheme.surface.withValues(alpha: 0.85),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sign in',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              // Don't block login if permissions are missing. Show a light hint instead.
              if (!permissionsOk) ...[
                const Gap(8),
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const Gap(6),
                    Expanded(
                      child: Text(
                        missing.isEmpty
                            ? 'Some features may require permissions later.'
                            : 'Missing permissions: ${missing.join(', ')}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onFixPermissions,
                      icon: const Icon(Icons.security, size: 18),
                      label: const Text('Fix'),
                    )
                  ],
                ),
              ],
              const Gap(12),
              _LabeledField(
                label: 'Email',
                icon: Icons.mail_outline,
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Email is required';
                  final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                  if (!re.hasMatch(s)) return 'Enter a valid email';
                  return null;
                },
              ),
        const Gap(12),
              _LabeledField(
                label: 'Password',
                icon: Icons.lock_outline,
                controller: passwordCtrl,
                obscureText: obscure,
                trailing: IconButton(
                  icon:
                      Icon(obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: onToggleObscure,
                ),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
              ),
        const Gap(8),
              LayoutBuilder(builder: (context, c) {
                final narrow = c.maxWidth < 460;
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                              value: rememberMe,
                              onChanged: (v) => onRememberChanged(v ?? true)),
                          const Gap(4),
                          const Text('Remember me'),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onForgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Checkbox(
                        value: rememberMe,
                        onChanged: (v) => onRememberChanged(v ?? true)),
                    const Gap(4),
                    const Text('Remember me'),
                    const Spacer(),
                    TextButton(
                        onPressed: onForgotPassword,
                        child: const Text('Forgot password?')),
                  ],
                );
              }),
        const Gap(8),
              FilledButton.icon(
                onPressed: loading ? null : onSubmit,
                icon: loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(color.onPrimary)),
                      )
                    : const Icon(Icons.login),
                label: const Text('Sign in'),
                style: FilledButton.styleFrom(
                  alignment: Alignment.center,
                  textStyle: theme.textTheme.labelLarge?.copyWith(
                        height: 1.0,
                        leadingDistribution: TextLeadingDistribution.even,
                        textBaseline: TextBaseline.alphabetic,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 350.ms).scale(
        begin: const Offset(0.98, 0.98),
        end: const Offset(1, 1),
        alignment: Alignment.center);
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.icon,
    required this.controller,
    this.trailing,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
  textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: trailing,
      ),
    );
  }
}

class _AnimatedBackdrop extends StatelessWidget {
  const _AnimatedBackdrop({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
  // Background only needs theme; size-based SVGs removed.
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surfaceContainerHighest.withValues(alpha: isDark ? .28 : .45),
                cs.surface,
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _BlobPainter(cs.primary.withValues(alpha: isDark ? .18 : .10)),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: -8, end: 8, curve: Curves.easeInOut, duration: 6.seconds),
  // Removed background SVG ornaments per request; keep subtle animated blob backdrop only.
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final paint = Paint()
      ..color = color
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    for (var i = 0; i < 6; i++) {
      final w = size.width;
      final h = size.height;
      final cx = rnd.nextDouble() * w;
      final cy = rnd.nextDouble() * h;
      final r = rnd.nextDouble() * (w * .12) + (w * .05);
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
