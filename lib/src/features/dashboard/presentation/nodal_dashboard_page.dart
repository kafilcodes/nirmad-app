import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import 'package:go_router/go_router.dart';
import 'nodal_dashboard_list_page.dart';
import 'metrics_tiles.dart';
import 'projects_charts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/widgets/branding_footer.dart';
import '../../../shared/widgets/app_sidebar.dart';
import '../../profile/presentation/profile_page.dart';
import '../../../shared/widgets/notifications_list.dart';
import '../../../core/ui/responsive_policies.dart';
import 'package:animations/animations.dart';

class NodalDashboardPage extends ConsumerStatefulWidget {
  const NodalDashboardPage({super.key});

  @override
  ConsumerState<NodalDashboardPage> createState() => _NodalDashboardPageState();
}

class _NodalDashboardPageState extends ConsumerState<NodalDashboardPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _sideIndex = 0;

  @override
  void initState() {
    super.initState();
  _tab = TabController(length: 4, vsync: this);
    _sideIndex = _tab.index;
    _tab.addListener(() {
      if (_sideIndex != _tab.index) {
        setState(() => _sideIndex = _tab.index);
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
    final auth = ref.read(authRepositoryProvider);
    final isCompact = MediaQuery.of(context).size.width < 720;
    return Scaffold(
      body: Row(
        children: [
          if (!isCompact) ...[
            SizedBox(
              width: 256,
              child: AppSidebar(selectedIndex: _sideIndex, onSelect: (i) => setState(() { _sideIndex = i; _tab.index = i; })),
            ),
            VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
          ],
          Expanded(
            child: Column(
              children: [
                // Top bar
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      const Text('Dashboard'),
                      const Spacer(),
                      IconButton(
                        onPressed: () async {
                          await auth.signOut();
                          if (context.mounted) context.go('/');
                        },
                        icon: const Icon(CupertinoIcons.square_arrow_right),
                        tooltip: 'Sign out',
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                Expanded(
                  child: PageTransitionSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, a, sa) => FadeThroughTransition(animation: a, secondaryAnimation: sa, child: child),
                    child: TabBarView(
                    controller: _tab,
                    children: [
                      // 0: Dashboard metrics + charts
                        Padding(
                          padding: EdgeInsets.all(R.gutter(context)),
                          child: _NodalMetricsAndCharts(),
                        ),
                      // 1: Projects list
                      const NodalDashboardListPage(),
                      // 2: Notifications
                      const NotificationsList(),
                      // 3: Profile
                      const ProfilePage(),
                    ],
                    ),
                  ),
                ),
                const BrandingFooter(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isCompact
          ? CupertinoTabBar(
              currentIndex: _sideIndex,
              onTap: (i) => setState(() { _sideIndex = i; _tab.index = i; }),
              items: const [
                BottomNavigationBarItem(icon: Icon(CupertinoIcons.square_grid_2x2), label: 'Overview'),
                BottomNavigationBarItem(icon: Icon(CupertinoIcons.list_bullet), label: 'Projects'),
                BottomNavigationBarItem(icon: Icon(CupertinoIcons.bell), label: 'Alerts'),
                BottomNavigationBarItem(icon: Icon(CupertinoIcons.person), label: 'Profile'),
              ],
            )
          : null,
    );
  }
}

class _NodalMetricsAndCharts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MetricsTiles(),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final isWide = c.maxWidth > 900;
            return StreamBuilder(
              stream: db.collection('projects').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
                }
                final docs = (snapshot.data as QuerySnapshot<Map<String, dynamic>>).docs;
                int countWhere(String s) => docs.where((d) => d.data()['status'] == s).length;
                final completed = countWhere('completed');
                final inProgress = countWhere('in_progress');
                final cancelled = countWhere('cancelled');
                return ProjectsCharts(
                  completed: completed,
                  inProgress: inProgress,
                  cancelled: cancelled,
                  isWide: isWide,
                );
              },
            );
          },
        ),
      ],
    );
  }
}
