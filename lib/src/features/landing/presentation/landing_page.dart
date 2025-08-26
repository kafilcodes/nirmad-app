import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/i18n/locale_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/branding_footer.dart';

class LandingPage extends ConsumerWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nirmad'),
        actions: [
          Builder(
            builder: (context) {
              final current = ref.watch(localeProvider) ?? const Locale('en');
              final isEn = current.languageCode == 'en';
              final label = isEn ? 'EN' : 'HI';
              final icon = isEn ? Icons.language : Icons.translate;
              return TextButton.icon(
                onPressed: () => ref.read(localeProvider.notifier).state = isEn ? const Locale('hi') : const Locale('en'),
                icon: Icon(icon),
                label: Text(label),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _Tile(
              label: 'Nodal Officer',
              icon: Icons.admin_panel_settings,
              onTap: () => context.go('/login'),
            ),
            const SizedBox(height: 16),
            _Tile(
              label: 'Project Owner',
              icon: Icons.account_circle,
              onTap: () => context.go('/login'),
            ),
            const SizedBox(height: 16),
            _Tile(
              label: 'Project Entry',
              icon: Icons.edit_note,
              onTap: () => context.go('/login'),
            ),
            const SizedBox(height: 16),
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
        ),
      ),
    );
  }
}
