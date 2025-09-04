import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cupertino_sidebar/cupertino_sidebar.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:animations/animations.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/i18n/locale_provider.dart';
import '../../core/ui/responsive_policies.dart';

typedef SidebarOnSelect = void Function(int index);

class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key, required this.selectedIndex, required this.onSelect, this.isVibrant = false});
  final int selectedIndex;
  final SidebarOnSelect onSelect;
  final bool isVibrant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(authStateProvider).value;
    final cs = Theme.of(context).colorScheme;
    final role = appUser?.role ?? UserRole.projectOwner;
    final auth = ref.read(authRepositoryProvider);

    // Unread notifications for Owner/Nodal
    final wantsUnread = role == UserRole.projectOwner || role == UserRole.superNodal || role == UserRole.subNodal;
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    final Stream<int>? unreadStream = wantsUnread && uid != null
        ? FirebaseFirestore.instance
            .collection('updates')
            .where('userId', isEqualTo: uid)
            .where('readAt', isNull: true)
            .snapshots()
            .map((s) => s.size)
        : null;

    return StreamBuilder<int>(
      stream: unreadStream,
      builder: (context, snap) {
        final unread = snap.data ?? 0;
        final int? notifIndex = role == UserRole.projectOwner
            ? 2
            : (role == UserRole.superNodal || role == UserRole.subNodal)
                ? 2
                : null;

        final sidebar = CupertinoSidebar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelect,
          backgroundColor: cs.surface,
          isVibrant: isVibrant,
          children: _buildSectionsForRole(role, cs, notifIndex, unread, selectedIndex),
        );

        return LayoutBuilder(builder: (context, c) {
          final maxH = c.maxHeight.isFinite ? c.maxHeight : MediaQuery.of(context).size.height;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: cs.shadow.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: SizedBox(
              height: maxH,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: R.gutter(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageTransitionSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, a, sa) => FadeThroughTransition(animation: a, secondaryAnimation: sa, child: child),
                      child: KeyedSubtree(key: ValueKey(appUser?.uid ?? 'guest'), child: _ProfileCard(appUser: appUser)),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: sidebar,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SidebarFooter(onLogout: () async {
                      await auth.signOut();
                      if (context.mounted) context.go('/');
                    }),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  List<Widget> _buildSectionsForRole(UserRole role, ColorScheme cs, int? notifIndex, int unread, int selectedIndex) {
    // Helper to build a destination with filled/outline icons
    SidebarDestination dest({
      required int index,
      required IconData icon,
      required IconData? filled,
      required String label,
    }) {
      final showLabel = (notifIndex != null && index == notifIndex && unread > 0) ? '$label ($unread)' : label;
      return SidebarDestination(
        icon: Icon(icon, size: 18, color: cs.onSurface),
        selectedIcon: Icon(filled ?? icon, size: 18, color: cs.primary),
        // Single-line label with ellipsis to keep titles fully visible on one line
        label: Text(
          showLabel,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: index == selectedIndex ? cs.primary : null),
        ),
      );
    }

    if (role == UserRole.devAdmin) {
      return [
        SidebarSection(
          label: const Text('Management'),
          children: [
            dest(index: 0, icon: CupertinoIcons.square_grid_2x2, filled: CupertinoIcons.square_grid_2x2_fill, label: 'Dashboard'),
            dest(index: 1, icon: CupertinoIcons.person_2, filled: CupertinoIcons.person_2_fill, label: 'Users'),
            dest(index: 2, icon: CupertinoIcons.folder, filled: CupertinoIcons.folder_fill, label: 'Projects'),
          ],
        ),
        SidebarSection(
          label: const Text('My Services'),
          children: [
            dest(index: 3, icon: CupertinoIcons.person_crop_circle, filled: CupertinoIcons.person_crop_circle_fill, label: 'Profile'),
          ],
        ),
      ];
    }

    if (role == UserRole.superNodal || role == UserRole.subNodal) {
      return [
        SidebarSection(
          label: const Text('Overview'),
          children: [
            dest(index: 0, icon: CupertinoIcons.square_grid_2x2, filled: CupertinoIcons.square_grid_2x2_fill, label: 'Dashboard'),
          ],
        ),
        SidebarSection(
          label: const Text('Projects'),
          children: [
            dest(index: 1, icon: CupertinoIcons.folder, filled: CupertinoIcons.folder_fill, label: 'Projects'),
          ],
        ),
        SidebarSection(
          label: const Text('My Services'),
          children: [
            dest(index: 2, icon: CupertinoIcons.bell, filled: CupertinoIcons.bell_fill, label: 'Updates'),
            dest(index: 3, icon: CupertinoIcons.person_crop_circle, filled: CupertinoIcons.person_crop_circle_fill, label: 'Profile'),
          ],
        ),
      ];
    }

    // Project Owner
    return [
      SidebarSection(
        label: const Text('Projects'),
        children: [
          dest(index: 0, icon: CupertinoIcons.list_bullet, filled: CupertinoIcons.list_bullet, label: 'Projects'),
          dest(index: 1, icon: CupertinoIcons.add_circled, filled: CupertinoIcons.add_circled_solid, label: 'Create Project'),
        ],
      ),
      SidebarSection(
        label: const Text('My Services'),
        children: [
          dest(index: 2, icon: CupertinoIcons.bell, filled: CupertinoIcons.bell_fill, label: 'Updates'),
          dest(index: 3, icon: CupertinoIcons.person_crop_circle, filled: CupertinoIcons.person_crop_circle_fill, label: 'Profile'),
        ],
      ),
    ];
  }
}

// Removed old header with compact profile; brand is shown instead.

// legacy item model removed

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.appUser});
  final AppUser? appUser;
  @override
  Widget build(BuildContext context) {
  // final cs = Theme.of(context).colorScheme;
    final email = appUser?.email ?? '';
    final name = (appUser?.displayName ?? '').trim();
  // role chip removed per design
  final photoUrl = fb.FirebaseAuth.instance.currentUser?.photoURL;
  // No initials overlay; use person icon when no photo
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Unified avatar: same as profile page (Avatar.profile base + HashCachedImage overlay)
          _SidebarAvatar(text: name.isNotEmpty ? name : email, fallbackUrl: photoUrl),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            // Make horizontally scrollable on extremely narrow sidebars to avoid overflow
            final row = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.person, size: 16),
                const SizedBox(width: 6),
                Flexible(child: Text(name.isNotEmpty ? name : email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
              ],
            );
            return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(constraints: BoxConstraints(minWidth: 0, maxWidth: c.maxWidth), child: row));
          }),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 4),
            LayoutBuilder(builder: (context, c) {
              final row2 = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.mail, size: 14),
                  const SizedBox(width: 6),
                  Flexible(child: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
                ],
              );
              return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(constraints: BoxConstraints(minWidth: 0, maxWidth: c.maxWidth), child: row2));
            }),
          ],
          // Removed role chip as requested
        ],
      ),
    );
  }
}

class _SidebarAvatar extends ConsumerWidget {
  const _SidebarAvatar({required this.text, this.fallbackUrl});
  final String text;
  final String? fallbackUrl;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final name = (text.trim().isNotEmpty ? text.trim() : (fb.FirebaseAuth.instance.currentUser?.email ?? '')).trim();
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : 'U';
    // Accent circle with theme-aware text color
    final bg = cs.primary;
    final on = cs.onPrimary;
    return CircleAvatar(
      radius: 40,
      backgroundColor: bg,
      child: Text(initial, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: on)),
    );
  }
}
class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter({required this.onLogout});
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeControllerProvider);
    final themeCtl = ref.read(themeControllerProvider.notifier);
    final currentLocale = ref.watch(localeProvider) ?? const Locale('en');
    final isEn = currentLocale.languageCode == 'en';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
  Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
  const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 240;
          final children = <Widget>[
            Tooltip(
              message: isEn ? 'Switch to Hindi' : 'Switch to English',
              child: IconButton(
                onPressed: () {
                  ref.read(localeProvider.notifier).state = isEn ? const Locale('hi') : const Locale('en');
                },
                icon: const Icon(CupertinoIcons.globe),
              ),
            ),
            Tooltip(
              message: 'Toggle theme',
              child: IconButton(
                onPressed: themeCtl.toggle,
                icon: Icon(themeMode == ThemeMode.dark ? CupertinoIcons.moon : CupertinoIcons.sun_max),
              ),
            ),
            const SizedBox(width: 4),
            if (narrow)
              IconButton(onPressed: onLogout, icon: const Icon(CupertinoIcons.square_arrow_right))
            else
              SizedBox(
                width: 140,
                child: FilledButton.tonalIcon(
                  onPressed: onLogout,
                  icon: const Icon(CupertinoIcons.square_arrow_right),
                  label: const Text('Logout'),
                ),
              ),
          ];
          // Make horizontally scrollable to avoid RenderFlex overflow during collapse/resize
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: children,
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: const [
              Text('NIRMAD YOJNA', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              SizedBox(height: 2),
              Text('© DHAMTARI DISTRICT ADMINISTRATION', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }
}
