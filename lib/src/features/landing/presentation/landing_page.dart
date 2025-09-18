import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/branding_footer.dart';
import '../../auth/data/auth_repository.dart';
import 'package:gap/gap.dart';
import '../../../shared/ui/progress.dart';

class LandingPage extends ConsumerWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (auth.isLoading) {
      return const Scaffold(
        body: Center(child: AppLoadingIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nirmad'),
  actions: const [Gap(4)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Gap(16),
            _Tile(
              label: 'Nodal Officer',
              icon: CupertinoIcons.person_badge_plus,
              onTap: () => context.go('/login'),
            ),
            const Gap(16),
            _Tile(
              label: 'Project Owner',
              icon: CupertinoIcons.person_crop_circle,
              onTap: () => context.go('/login'),
            ),
            const Gap(16),
            _Tile(
              label: 'Project Entry',
              icon: CupertinoIcons.pencil_circle,
              onTap: () => context.go('/login'),
            ),
            const Gap(16),
            const Spacer(),
            const BrandingFooter(),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _Tile({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 28),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, style: const TextStyle(fontSize: 18)),
        ),
        style: ElevatedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                height: 1.0,
                leadingDistribution: TextLeadingDistribution.even,
                textBaseline: TextBaseline.alphabetic,
              ),
        ),
      ),
    );
  }
}
