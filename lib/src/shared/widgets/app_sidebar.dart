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
import '../../core/ui/responsive_policies.dart';
import '../../shared/data/blocks_provider.dart';
import '../../core/prefs/shared_prefs.dart';
import '../../services/draft_media_store.dart';

typedef SidebarOnSelect = void Function(int index);

class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key, required this.selectedIndex, required this.onSelect, this.isVibrant = false, this.collapsed = false});
  final int selectedIndex;
  final SidebarOnSelect onSelect;
  final bool isVibrant;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(authStateProvider).value;
    final cs = Theme.of(context).colorScheme;
    final role = appUser?.role ?? UserRole.projectOwner;
    final auth = ref.read(authRepositoryProvider);

    // Unread notifications for Owner/Nodal
    final wantsUnread = role == UserRole.projectOwner || role == UserRole.superNodal || role == UserRole.subNodal;
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    Stream<int>? unreadStream;
    if (wantsUnread && uid != null) {
      final col = FirebaseFirestore.instance.collection('updates');
      if (role == UserRole.projectOwner) {
        unreadStream = col
            .where('userId', isEqualTo: uid)
            .where('readAt', isNull: true)
            .snapshots()
            .map((s) => s.size);
      } else if (role == UserRole.subNodal) {
        final keys = blockQueryKeys(appUser?.blockId);
        if (keys.isNotEmpty) {
          final q = keys.length == 1
              ? col.where('targetRoles', arrayContains: 'sub_nodal').where('blockId', isEqualTo: keys.first)
              : col.where('targetRoles', arrayContains: 'sub_nodal').where('blockId', whereIn: keys.take(10).toList());
          unreadStream = q.snapshots().map((s) => s.docs.where((d) {
                final readBy = ((d.data()['readBy'] as List?) ?? const []).whereType<String>();
                return !readBy.contains(uid);
              }).length);
        }
      } else {
        // super nodal / dev admin
        unreadStream = col
            .where('targetRoles', arrayContainsAny: const ['super_nodal', 'sub_nodal'])
            .snapshots()
            .map((s) => s.docs.where((d) {
                  final readBy = ((d.data()['readBy'] as List?) ?? const []).whereType<String>();
                  return !readBy.contains(uid);
                }).length);
      }
    }

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
            ),
            child: SizedBox(
              height: maxH,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: R.gutter(context)),
                child: collapsed
                    ? Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: sidebar,
                      )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header (non-scrollable)
                    PageTransitionSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, a, sa) => FadeThroughTransition(animation: a, secondaryAnimation: sa, child: child),
                      child: KeyedSubtree(
                        key: ValueKey(appUser?.uid ?? 'guest'),
                        child: _UnifiedProfileHeader(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Sidebar list (scrollable) gets bounded height via Expanded
                    Expanded(
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: sidebar,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Footer stays pinned
          _SidebarFooter(onLogout: () async {
                      if (!context.mounted) return;
                      // Show a modal progress barrier
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => const Center(child: CircularProgressIndicator()),
                      );
                      try {
            // Clear local caches best-effort before signOut
            try { await ref.read(draftMediaStoreProvider).clear(); } catch (_) {}
            try { await ref.read(sharedPrefsProvider).clear(); } catch (_) {}
            // Invalidate profile so next login pulls fresh data
            try { ref.invalidate(currentUserProfileProvider); } catch (_) {}
                        await auth.signOut();
                      } catch (_) {
                        // ignored
                      } finally {
                        if (!context.mounted) return;
                        // Ensure the loading dialog is closed
                        Navigator.of(context, rootNavigator: true).pop();
                        // Now route to login, replacing stack
                        context.go('/');
                      }
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
    Widget _sectionLabel(String text) => LayoutBuilder(
          builder: (context, c) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth),
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
    // Helper to build a destination with filled/outline icons
    SidebarDestination dest({
      required int index,
      required IconData icon,
      required IconData? filled,
      required String label,
    }) {
      final showLabel = (notifIndex != null && index == notifIndex && unread > 0) ? '$label ($unread)' : label;
      final showDot = notifIndex != null && index == notifIndex && unread > 0;
      Widget withDot(Widget child) => Stack(
            clipBehavior: Clip.none,
            children: [
              child,
              if (showDot)
                const Positioned(
                  right: -2,
                  top: -2,
                  child: SizedBox(
                    width: 7,
                    height: 7,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                    ),
                  ),
                ),
            ],
          );
      return SidebarDestination(
        icon: withDot(Icon(icon, size: 18, color: cs.onSurface)),
        selectedIcon: withDot(Icon(filled ?? icon, size: 18, color: cs.primary)),
        // Hide labels when collapsed
        label: collapsed
            ? const SizedBox.shrink()
            : Text(
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
          label: _sectionLabel('Management'),
          children: [
            dest(index: 0, icon: CupertinoIcons.square_grid_2x2, filled: CupertinoIcons.square_grid_2x2_fill, label: 'Dashboard'),
            dest(index: 1, icon: CupertinoIcons.person_2, filled: CupertinoIcons.person_2_fill, label: 'Users'),
            dest(index: 2, icon: CupertinoIcons.folder, filled: CupertinoIcons.folder_fill, label: 'Projects'),
          ],
        ),
      ];
    }

    if (role == UserRole.superNodal || role == UserRole.subNodal) {
      return [
        SidebarSection(
          label: _sectionLabel('Overview'),
          children: [
            dest(index: 0, icon: CupertinoIcons.square_grid_2x2, filled: CupertinoIcons.square_grid_2x2_fill, label: 'Dashboard'),
          ],
        ),
        SidebarSection(
          label: _sectionLabel('Projects'),
          children: [
            dest(index: 1, icon: CupertinoIcons.folder, filled: CupertinoIcons.folder_fill, label: 'Projects'),
          ],
        ),
        SidebarSection(
          label: _sectionLabel('My Services'),
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
        label: _sectionLabel('Projects'),
        children: [
          dest(index: 0, icon: CupertinoIcons.list_bullet, filled: CupertinoIcons.list_bullet, label: 'Projects'),
          dest(index: 1, icon: CupertinoIcons.add_circled, filled: CupertinoIcons.add_circled_solid, label: 'Create Project'),
        ],
      ),
      SidebarSection(
        label: _sectionLabel('My Services'),
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

class _UnifiedProfileHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prof = ref.watch(currentUserProfileProvider);
    final email = (prof?.email ?? fb.FirebaseAuth.instance.currentUser?.email ?? '').trim();
    final name = (prof?.displayName ?? '').trim();
  final text = name.isNotEmpty ? name : (email.split('@').first);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _SidebarAvatar(text: text),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final row = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.person, size: 16),
                const SizedBox(width: 6),
                Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
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
        ],
      ),
    );
  }
}

class _SidebarAvatar extends ConsumerWidget {
  const _SidebarAvatar({required this.text});
  final String text;
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
      child: Text(
        initial,
        textAlign: TextAlign.center,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: true,
          applyHeightToLastDescent: true,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: on,
          height: 1.0,
          leadingDistribution: TextLeadingDistribution.even,
          textBaseline: TextBaseline.alphabetic,
        ),
      ),
    );
  }
}
class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter({required this.onLogout});
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
  final themeMode = ref.watch(themeControllerProvider);
    final themeCtl = ref.read(themeControllerProvider.notifier);
  // Language selector removed; app runs in English only
  return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // District logo (theme-aware) above footer controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4),
          child: SizedBox(
            height: 50,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220, maxHeight: 96),
                child: Builder(builder: (context) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  final asset = isDark ? 'assets/dmt_white.png' : 'assets/dmt_black.png';
                  return Image.asset(
                    asset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    isAntiAlias: true,
                  );
                }),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 4),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 240;
          final children = <Widget>[
            const SizedBox.shrink(),
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
      ],
    );
  }
}
