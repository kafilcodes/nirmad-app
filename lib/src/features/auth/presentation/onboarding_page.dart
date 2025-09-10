import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../../core/prefs/shared_prefs.dart';
import '../../../services/permission_service.dart';

class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool('onboarding_seen', true);
  // Fire-and-forget permission requests on Android (notifications/location/storage)
  // Safe to ignore failures.
  PermissionService.requestCorePermissions();
    if (context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget svg(String asset, {double maxW = 360}) {
      return LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.clamp(220.0, maxW);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: SvgPicture.asset(
            asset,
            width: w,
            height: w,
            fit: BoxFit.contain,
          ),
        );
      });
    }

    final pages = <PageViewModel>[
      PageViewModel(
        titleWidget: Text('Create and Manage Projects Effortlessly', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
        bodyWidget: Text(
          'Project Owners can create projects in minutes. Nodal officers track progress and keep everything moving—organized and on time.',
          style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        image: svg('assets/login_page_graphics.svg'),
        decoration: PageDecoration(pageColor: Theme.of(context).colorScheme.surface),
      ),
      PageViewModel(
        titleWidget: Text('Full Project Transparency', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
        bodyWidget: Text(
          'Nodal officers get a real‑time view across every project—status, updates, and actions—all in one place for the entire district.',
          style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        image: svg('assets/login_page_graphics_2.svg'),
        decoration: PageDecoration(pageColor: Theme.of(context).colorScheme.surface),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: IntroductionScreen(
          globalBackgroundColor: Theme.of(context).colorScheme.surface,
          pages: pages,
          showSkipButton: true,
          skip: Text('Skip', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
          next: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_forward, color: cs.onPrimary),
          ),
          done: Text('Start', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
          // Using a custom next widget above; no nextStyle needed
          dotsDecorator: DotsDecorator(
            activeColor: cs.primary,
            color: cs.primary.withOpacity(0.25),
            activeSize: const Size(22, 8),
            activeShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            size: const Size(8, 8),
          ),
          onDone: () => _finish(context, ref),
          onSkip: () => _finish(context, ref),
          curve: Curves.easeInOut,
          controlsMargin: const EdgeInsets.all(16),
          controlsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      ),
    );
  }
}
