import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import 'metrics_tiles.dart';
import 'projects_charts.dart';
import '../../../shared/widgets/app_sidebar.dart';
import '../../profile/presentation/profile_page.dart';
import '../../../shared/widgets/notifications_list.dart';
import '../../../core/ui/responsive_policies.dart';
import 'package:animations/animations.dart';
import 'package:go_router/go_router.dart';
import '../state/projects_snapshot_provider.dart';
import '../../../shared/data/blocks_provider.dart';
import '../../projects/domain/project.dart';
import 'nodal_dashboard_list_page.dart' show NodalDashboardListPage, nodalOverdueDaysFilterProvider, nodalStatusFilterProvider, blockFilterProvider, nodalStageFilterProvider;
import '../../../shared/ui/progress.dart';

class NodalDashboardPage extends ConsumerStatefulWidget {
  const NodalDashboardPage({super.key});

  @override
  ConsumerState<NodalDashboardPage> createState() => _NodalDashboardPageState();
}

class _NodalDashboardPageState extends ConsumerState<NodalDashboardPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _sideIndex = 0;
  bool _sidebarOpen = false;
  bool _sidebarHidden = false; // for wide screens, fully hide/show
  int _lastTabIndex = 0;

  @override
  void initState() {
    super.initState();
  _tab = TabController(length: 4, vsync: this);
    _sideIndex = _tab.index;
    _lastTabIndex = _tab.index;
    _tab.addListener(() {
      if (_sideIndex != _tab.index) {
        setState(() => _sideIndex = _tab.index);
        // Reset project filters when leaving the Projects tab (index 1),
        // so coming back starts fresh. Do not clear on entering Projects from
        // Metrics, to preserve metric-driven filter taps.
        try {
          if (_lastTabIndex == 1 && _tab.index != 1) {
            final ref = this.ref; // Riverpod ref from ConsumerState
            ref.read(nodalStatusFilterProvider.notifier).state = null;
            ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
            ref.read(blockFilterProvider.notifier).state = null;
            ref.read(nodalStageFilterProvider.notifier).state = null;
          }
        } catch (_) {}
        _lastTabIndex = _tab.index;
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
  // final auth = ref.read(authRepositoryProvider); // logout handled via sidebar footer
    final isCompact = MediaQuery.of(context).size.width < 900;
    final userAsync = ref.watch(authStateProvider);
    if (!userAsync.hasValue) {
      return const Scaffold(body: Center(child: AppLoadingIndicator()));
    }
    final user = userAsync.value;
    if (user == null) {
      return const Scaffold(body: Center(child: AppLoadingIndicator()));
    }
    if (user.role == UserRole.projectOwner) {
      // Owners should be on the owner shell instead
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          context.go('/owner');
        }
      });
      return const Scaffold(body: Center(child: AppLoadingIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: Stack(
        children: [
          Row(
            children: [
              if (!isCompact) ...[
                SizedBox(
                  width: _sidebarHidden ? 0 : 256,
                  child: _sidebarHidden
                      ? const SizedBox.shrink()
                      : AppSidebar(
                          selectedIndex: _sideIndex,
                          onSelect: (i) => setState(() { _sideIndex = i; _tab.index = i; }),
                          collapsed: false,
                        ),
                ),
                // Removed divider for flat sidebar integration
              ],
              Expanded(
                child: Column(
                  children: [
                    // Top utility bar (no title) with sidebar toggle only
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          if (isCompact)
                            IconButton(
                              icon: Icon(_sidebarOpen ? CupertinoIcons.clear : CupertinoIcons.bars),
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                setState(() => _sidebarOpen = !_sidebarOpen);
                              },
                              tooltip: 'Menu',
                            )
                          else
                            IconButton(
                              // Use previous iOS sidebar icons to show/hide the sidebar entirely
                              icon: Icon(_sidebarHidden ? CupertinoIcons.sidebar_right : CupertinoIcons.sidebar_left),
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                setState(() => _sidebarHidden = !_sidebarHidden);
                              },
                              tooltip: _sidebarHidden ? 'Show sidebar' : 'Hide sidebar',
                            ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.transparent),
                    Expanded(
                      child: PageTransitionSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, a, sa) => FadeThroughTransition(animation: a, secondaryAnimation: sa, child: child),
                        child: TabBarView(
                          controller: _tab,
                          children: [
                            Padding(
                              padding: EdgeInsets.all(R.gutter(context)),
                              child: const _NodalMetricsAndCharts(),
                            ),
                            const NodalDashboardListPage(),
                            const NotificationsList(),
                            const ProfilePage(),
                          ],
                        ),
                      ),
                    ),
                    // Branding footer removed from body; remains in sidebar footer and login only
                  ],
                ),
              ),
            ],
          ),
          // Overlay sidebar for compact screens
          if (isCompact && _sidebarOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _sidebarOpen = false),
                child: Container(color: Colors.black.withValues(alpha: 0.32)),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              left: _sidebarOpen ? 0 : -320,
              top: 0,
              bottom: 0,
              width: (MediaQuery.of(context).size.width * 0.85).clamp(260, 320).toDouble(),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Material(
                    elevation: 0,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: AppSidebar(
                      selectedIndex: _sideIndex,
                      onSelect: (i) => setState(() { _sideIndex = i; _tab.index = i; _sidebarOpen = false; }),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
  // Bottom navigation removed: use sidebar across all sizes
    );
  }
}

class _NodalMetricsAndCharts extends ConsumerWidget {
  const _NodalMetricsAndCharts();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Scope charts/metrics to role via central query provider and also build a stable query immediately
    final scopedStream = ref.watch(dashboardProjectsStreamProvider);
    final user = ref.watch(authStateProvider).value;
    final isSub = user?.role == UserRole.subNodal;
    final blockName = isSub ? canonicalizeBlockId(user?.blockId) : '';
    // Build the scoped query deterministically so UI doesn't briefly show unscoped data
    final db = FirebaseFirestore.instance;
    Query<Map<String, dynamic>> scopedQuery = db.collection('projects').orderBy('updatedAt', descending: true);
    if (isSub) {
      final keys = blockQueryKeys(user?.blockId);
      if (keys.isEmpty) {
        scopedQuery = db.collection('projects').where('blockId', isEqualTo: '__none__').orderBy('updatedAt', descending: true);
      } else if (keys.length == 1) {
        scopedQuery = db.collection('projects').where('blockId', isEqualTo: keys.first).orderBy('updatedAt', descending: true);
      } else {
        scopedQuery = db.collection('projects').where('blockId', whereIn: keys.take(10).toList()).orderBy('updatedAt', descending: true);
      }
    } else if (user?.role == UserRole.projectOwner) {
      scopedQuery = db.collection('projects').where('ownerId', isEqualTo: user?.uid).orderBy('updatedAt', descending: true);
    }
    final docs = scopedStream.maybeWhen(data: (snap) => snap.docs, orElse: () => null);
    // Make the dashboard content scrollable to avoid render overflow on shorter viewports.
    String greetFor(DateTime now) {
      final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
      final h = ist.hour;
      if (h < 12) return 'Good Morning';
      if (h < 17) return 'Good Afternoon';
      return 'Good Evening';
    }
    String firstNameFrom(String? displayName, String email) {
      final n = (displayName ?? '').trim();
      if (n.isNotEmpty) {
        final parts = n.split(' ');
        return parts.first;
      }
      final local = email.split('@').first;
      return local;
    }
    final prof = ref.watch(currentUserProfileProvider);
    final greetName = firstNameFrom(prof?.displayName, prof?.email ?? '');
  final greetingPhrase = greetFor(DateTime.now());

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isSub && blockName.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(children: [
                const Icon(CupertinoIcons.person_2_square_stack, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Welcome, Sub Nodal Officer of $blockName', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
              ]),
            ),
            const SizedBox(height: 8),
          ],
          // Mobile-first: show greeting above stats for super nodal
          if ((user?.role == UserRole.superNodal) && MediaQuery.of(context).size.width < 720) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Builder(builder: (context) {
                  final cs = Theme.of(context).colorScheme;
                  return Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$greetingPhrase, ', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                      TextSpan(text: greetName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
          ],
          MetricsTiles(
            query: scopedQuery,
            docs: docs,
            onTap: (key) {
              // Navigate to Projects tab with a filter
              // Keys: 'all' | 'in_progress' | 'completed' | 'delayed_30' | 'delayed_60'
              if (key == 'all') {
                ref.read(nodalStatusFilterProvider.notifier).state = null;
                ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
              } else if (key == 'in_progress') {
                ref.read(nodalStatusFilterProvider.notifier).state = ProjectStatus.in_progress;
                ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
              } else if (key == 'completed') {
                ref.read(nodalStatusFilterProvider.notifier).state = ProjectStatus.completed;
                ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
              } else if (key == 'delayed_30' || key == 'delayed_60') {
                // Apply overdue-days filter and clear status filter
                ref.read(nodalStatusFilterProvider.notifier).state = null;
                ref.read(nodalOverdueDaysFilterProvider.notifier).state = key == 'delayed_30' ? 30 : 60;
              }
              // Switch to Projects tab
              final state = context.findAncestorStateOfType<_NodalDashboardPageState>();
              if (state != null) {
                state._tab.index = 1;
                state._sideIndex = 1;
              }
            },
          ),
          const SizedBox(height: 12),
          // Greeting after Stats section (desktop/web, or non-super-nodal)
          if (!(user?.role == UserRole.superNodal && MediaQuery.of(context).size.width < 720))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Builder(builder: (context) {
                final cs = Theme.of(context).colorScheme;
                return Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$greetingPhrase, ', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                    TextSpan(text: greetName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                );
              }),
            ),
          ),
  LayoutBuilder(
            builder: (context, c) {
              final isWide = c.maxWidth > 900;
  return ProjectsCharts(
              query: scopedQuery,
              isWide: isWide,
              docs: docs,
              isSubNodal: isSub,
              onNavigateToProjects: () {
                final state = context.findAncestorStateOfType<_NodalDashboardPageState>();
                if (state != null) {
                  state._tab.index = 1;
                  state._sideIndex = 1;
                }
              },
            );
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
