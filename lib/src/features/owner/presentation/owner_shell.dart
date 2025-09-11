import 'package:flutter/material.dart';
import 'package:nirmadapp/src/shared/widgets/required_label.dart';
import 'package:flutter/cupertino.dart';
// SidebarX removed; using cupertino_sidebar via AppSidebar
import 'package:flutter_riverpod/flutter_riverpod.dart';
// import removed: chart visualization no longer used on projects page
import 'package:cloud_firestore/cloud_firestore.dart';
// Theme toggle moved to Profile page per spec
import '../../../shared/widgets/app_sidebar.dart';
import '../../projects/data/project_repository.dart';
import '../../projects/presentation/project_detail_page.dart';
// geo_providers kept for other views but not used in Create form anymore
// Create Project dependencies
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_storage/firebase_storage.dart' as fs;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
// Image compression utility
import '../../../utils/image_utils.dart' as image_utils;
import 'dart:async';
import 'package:image/image.dart' as image_lib;
import '../../projects/domain/project.dart';
import '../../../services/storage_service.dart';
import '../../updates/data/updates_repository.dart';
import '../../../services/draft_media_store.dart';
import '../../profile/presentation/profile_page.dart';
import '../../../shared/widgets/notifications_list.dart';
import '../../../shared/widgets/no_data.dart';
import '../../../shared/widgets/illustrated_background.dart';
import '../../../shared/widgets/date_form_field.dart';
import '../../../shared/widgets/scroll_safe_dialog.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../../utils/geohash.dart';
import '../../../core/prefs/shared_prefs.dart';
import '../../../services/local_draft_service.dart';
import 'package:toastification/toastification.dart';
import '../../../core/ui/responsive_policies.dart';
import 'package:animations/animations.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/data/local_gp_data.dart' as gpdata;
import 'package:gap/gap.dart';
// StateProvider is available from the main riverpod import above

class _SchemeItem {
  final String en;
  final String hi;
  const _SchemeItem(this.en, this.hi);
}

// Owner Projects search query (simple client-side filter)
final projectsSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');
final projectsGridViewProvider = StateProvider<bool>((ref) {
  try {
    final prefs = ref.read(sharedPrefsProvider);
    return prefs.getBool('projectsGrid') ?? true;
  } catch (_) {
    return true;
  }
}); // true=grid, false=list

class OwnerShell extends ConsumerStatefulWidget {
  const OwnerShell({super.key});
  @override
  ConsumerState<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends ConsumerState<OwnerShell> {
  int _index = 0;
  bool _sidebarOpen = true;
  bool _autoManageSidebar = true;
  // Success overlay state (after creating a project)
  Project? _successProject;
  String? _successProjectCode;

  @override
  void initState() {
    super.initState();
    // Default sidebar behavior by screen size: collapsed on phones/small web, open on large screens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final w = MediaQuery.of(context).size.width;
      final shouldOpen = w >= 900; // breakpoint for tablets/desktops
      if (_sidebarOpen != shouldOpen && mounted) {
        setState(() => _sidebarOpen = shouldOpen);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
  // Hard guard: only Project Owners may access this shell
  final userAsync = ref.watch(authStateProvider);
  if (!userAsync.hasValue) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
  final user = userAsync.value;
  if (user == null) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
  if (user.role != UserRole.projectOwner) {
    // Defer navigation to the next frame to avoid build-time setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        context.go('/dashboard');
      }
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
  // Adapt sidebar when resizing, unless user has manually toggled it
  final screenW = MediaQuery.of(context).size.width;
  final desiredOpen = screenW >= 900;
  final overlaySidebar = screenW < 900; // use overlay on phones/tablets to avoid content squeeze
  if (_autoManageSidebar && _sidebarOpen != desiredOpen) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _sidebarOpen = desiredOpen);
    });
  }
  final pages = <Widget>[
    _ProjectsPage(
        openDrawer: null,
        onOpenProject: (Project p) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailPage(project: p)));
        },
        onCreateProject: () {
          setState(() => _index = 1);
        },
      ),
    _ProjectCreatePage(
      onCreated: (project, {String? projectCode}) {
        setState(() {
          _successProject = project;
          _successProjectCode = projectCode;
        });
      },
    ),
  _NotificationsPage(openDrawer: null),
    const ProfilePage(),
    ];
  final titles = ['My Projects', 'Create Project', 'Updates', 'Profile'];

    return Scaffold(
      body: Stack(
        children: [
          // Main content always takes full width; sidebar overlays when on small screens
          Row(
            children: [
              if (!overlaySidebar)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  width: _sidebarOpen ? 260 : 0,
                  child: _sidebarOpen
                      ? Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: SizedBox.expand(
                            child: AppSidebar(
                              selectedIndex: _index,
                              onSelect: (i) => setState(() => _index = i),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              // Removed sidebar divider for flat, seamless design
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Stack(
                    key: ValueKey('page_$_index'),
                    children: [
                      IllustratedBackground(
                        asset: 'assets/undraw_city-life_l74x.svg',
                        opacity: 0.10,
                        alignment: Alignment.bottomRight,
                        child: _PageScaffold(
                          title: titles[_index],
                          onMenu: () => setState(() {
                            _sidebarOpen = !_sidebarOpen;
                            _autoManageSidebar = false; // user preference takes over
                          }),
                          child: pages[_index],
                        ),
                      ),
                      // Project created success overlay
                      if (_successProject != null)
                        Positioned.fill(
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.32),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 520),
                                child: Card(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 8,
                                  child: Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0.8, end: 1.0),
                                          duration: const Duration(milliseconds: 350),
                                          curve: Curves.easeOutBack,
                                          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                                          child: Container(
                                            width: 88,
                                            height: 88,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primaryContainer,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(CupertinoIcons.check_mark_circled_solid, size: 64, color: Theme.of(context).colorScheme.primary),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Project created',
                                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                          textAlign: TextAlign.center,
                                        ),
                                        if (_successProjectCode != null) ...[
                                          const SizedBox(height: 4),
                                          Text(_successProjectCode!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
                                        ],
                                        const SizedBox(height: 12),
                                        Text(
                                          _successProject!.name,
                                          style: Theme.of(context).textTheme.bodyMedium,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 20),
                                        LayoutBuilder(builder: (context, c) {
                                          final wide = c.maxWidth > 380;
                                          final closeBtn = OutlinedButton.icon(
                                            onPressed: () => setState(() => _successProject = null),
                                            icon: const Icon(CupertinoIcons.xmark_circle),
                                            label: const Text('Close'),
                                            style: OutlinedButton.styleFrom(
                                              alignment: Alignment.center,
                                              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                    height: 1.0,
                                                    leadingDistribution: TextLeadingDistribution.even,
                                                    textBaseline: TextBaseline.alphabetic,
                                                  ),
                                            ),
                                          );
                                          final viewBtn = FilledButton.icon(
                                            onPressed: () {
                                              final p = _successProject!;
                                              setState(() {
                                                _successProject = null;
                                                _index = 0; // go to My Projects tab
                                              });
                                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailPage(project: p)));
                                            },
                                            icon: const Icon(CupertinoIcons.arrow_right_circle_fill),
                                            label: const Text('View Project'),
                                            style: FilledButton.styleFrom(
                                              alignment: Alignment.center,
                                              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                                                    height: 1.0,
                                                    leadingDistribution: TextLeadingDistribution.even,
                                                    textBaseline: TextBaseline.alphabetic,
                                                  ),
                                            ),
                                          );
                                          if (wide) {
                                            return Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [closeBtn, const SizedBox(width: 12), viewBtn],
                                            );
                                          }
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [viewBtn, const SizedBox(height: 8), closeBtn],
                                          );
                                        })
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Details overlay removed: we now navigate to a dedicated page
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Backdrop below, sidebar above
          if (overlaySidebar && _sidebarOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _sidebarOpen = false),
                child: Container(color: Colors.black.withValues(alpha: 0.32)),
              ),
            ),
          if (overlaySidebar)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              left: _sidebarOpen ? 0 : -320,
              top: 0,
              bottom: 0,
              width: (screenW * 0.85).clamp(260, 320).toDouble(),
              child: SafeArea(
                child: Shortcuts(
                  shortcuts: <LogicalKeySet, Intent>{
                    LogicalKeySet(LogicalKeyboardKey.escape): DismissIntent(),
                  },
                  child: Actions(
                    actions: {
                      DismissIntent: CallbackAction<DismissIntent>(
                        onInvoke: (intent) {
                          if (_sidebarOpen) setState(() => _sidebarOpen = false);
                          return null;
                        },
                      ),
                    },
                    child: FocusScope(
                      canRequestFocus: true,
                      autofocus: true,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Material(
                          elevation: 0,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: AppSidebar(
                            selectedIndex: _index,
                            onSelect: (i) => setState(() {
                              _index = i;
                              _sidebarOpen = false; // auto close on selection on small screens
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Owner uses the shared AppSidebar

class _NotificationsPage extends ConsumerWidget {
  const _NotificationsPage({required this.openDrawer});
  final VoidCallback? openDrawer;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
  return const Scaffold(body: NotificationsList());
  }
}

class _ProjectsPage extends ConsumerWidget {
  const _ProjectsPage({required this.openDrawer, required this.onOpenProject, required this.onCreateProject});
  final VoidCallback? openDrawer;
  final void Function(Project) onOpenProject;
  final VoidCallback onCreateProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  final cached = ref.watch(ownerProjectsDiskFirstProvider);
  final projectsAsync = ref.watch(ownerProjectsProvider);
  final query = ref.watch(projectsSearchQueryProvider);
  return Scaffold(
    body: SafeArea(
      child: cached.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) {
          // Log Firestore index URL (if present) to console for copy-paste and hide from UI
          try {
            final msg = e.toString();
            final m = RegExp(r'https://console\.firebase\.google\.com[^\s\)]*').firstMatch(msg);
            final url = m?.group(0);
            if (url != null) {
              // ignore: avoid_print
              print('Firestore index required (Owner Projects): $url');
            }
          } catch (_) {}
          return const NoData(
            title: 'Something went wrong',
            message: 'We couldn\'t load your projects right now.',
            asset: 'assets/server_down.svg',
          );
        },
        data: (cachedProjects) {
          // If realtime stream has data, prefer it; else show cached
          final allProjects = projectsAsync.asData?.value ?? cachedProjects;
          final hadAny = allProjects.isNotEmpty;
          final q = query.trim().toLowerCase();
          var projects = allProjects;
          if (q.isNotEmpty) {
            projects = allProjects.where((p) {
              final inId = p.id.toLowerCase().contains(q);
              final inName = p.name.toLowerCase().contains(q);
              final inAddr = (p.address ?? '').toLowerCase().contains(q);
              final ld = p.landDetails;
              final inBlock = ((ld['blockName'] ?? '') as String).toLowerCase().contains(q);
              final inVillage = ((ld['villageName'] ?? '') as String).toLowerCase().contains(q);
              return inId || inName || inAddr || inBlock || inVillage;
            }).toList();
          }
          if (!hadAny) {
            return const Center(
              child: NoData(
                title: 'No projects yet',
                message: 'Create your first project to get started.',
                asset: 'assets/no_projects.svg',
              ),
            );
          }
          final total = projects.length;
          final completed = projects.where((p) => p.status == ProjectStatus.completed).length;
          final cancelled = projects.where((p) => p.status == ProjectStatus.cancelled).length;
          // Treat any non-completed/non-cancelled as in-progress for metrics (personalized expectation)
          final inProgress = total - completed - cancelled;
          // chart removed; percentage computation no longer needed
          return LayoutBuilder(builder: (context, c) {
            final isWide = c.maxWidth > 800;
            final gap = isWide ? 12.0 : 8.0;
            final cols = c.maxWidth > 1280 ? 4 : c.maxWidth > 960 ? 3 : c.maxWidth > 640 ? 2 : 1;

            DateTime? deadlineOf(dynamic v) {
              try {
                if (v == null) return null;
                if (v is Timestamp) return v.toDate();
                if (v is DateTime) return v;
                if (v is String) return DateTime.tryParse(v);
                if (v is Map && v['seconds'] != null) {
                  final secs = (v['seconds'] as num).toInt();
                  return DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true).toLocal();
                }
              } catch (_) {}
              return null;
            }
            int byUrgency(Project a, Project b) {
              final ad = deadlineOf(a.financials['deadline']);
              final bd = deadlineOf(b.financials['deadline']);
              if (ad == null && bd == null) return b.updatedAt.compareTo(a.updatedAt); // recent first
              if (ad == null) return 1; // nulls last
              if (bd == null) return -1;
              return ad.compareTo(bd); // earlier first
            }
            final today = DateTime.now();
            final startOfToday = DateTime(today.year, today.month, today.day);
            final lateProjects = <Project>[];
            final pendingProjects = <Project>[];
            for (final p in projects) {
              if (p.status == ProjectStatus.completed) continue;
              final d = deadlineOf(p.financials['deadline']);
              if (d != null && d.isBefore(startOfToday)) {
                lateProjects.add(p);
              } else {
                pendingProjects.add(p);
              }
            }
            lateProjects.sort(byUrgency);
            pendingProjects.sort(byUrgency);

            String greetFor(DateTime now) {
              // Convert to IST (UTC+5:30)
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

            return CustomScrollView(
              slivers: [
                // Greeting above Your Projects (mobile-first spacing)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
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
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        // Header row: search + view toggle
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _ProjectsSearchBar(onChanged: (q) {
                                    ref.read(projectsSearchQueryProvider.notifier).state = q;
                                  }),
                                ),
                                const SizedBox(width: 8),
                                SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(value: true, icon: Icon(CupertinoIcons.square_grid_2x2)),
                                    ButtonSegment(value: false, icon: Icon(CupertinoIcons.list_bullet)),
                                  ],
                                  selected: {ref.watch(projectsGridViewProvider)},
                                  onSelectionChanged: (s) {
                                    final v = s.first;
                                    ref.read(projectsGridViewProvider.notifier).state = v;
                                    try { ref.read(sharedPrefsProvider).setBool('projectsGrid', v); } catch (_) {}
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Gap(12),
                        LayoutBuilder(builder: (context, cc) {
                          final compact = cc.maxWidth < 720;
                          final metrics = [
                            _MetricData('Total', total, CupertinoIcons.folder, Colors.blue),
                            _MetricData('In Progress', inProgress, CupertinoIcons.arrow_2_circlepath, Colors.orange),
                            _MetricData('Completed', completed, CupertinoIcons.check_mark_circled, Colors.green),
                          ];
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final m in metrics)
                                SizedBox(
                                  width: compact ? (cc.maxWidth) : (cc.maxWidth - 24) / 3,
                                  child: _metricCard(context, m),
                                ),
                            ],
                          );
                        }),
                        const Gap(12),
                        // Pie chart removed per spec to keep the page focused and clean.
                      ],
                    ),
                  ),
                ),
                // No-results state for search without blanking the whole page
                if (q.isNotEmpty && lateProjects.isEmpty && pendingProjects.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: NoData(
                        title: 'No projects found',
                        message: 'Try a different search term or clear the filter.',
                        asset: 'assets/search_projects.svg',
                      ),
                    ),
                  ),
                if (q.isEmpty && lateProjects.isEmpty && pendingProjects.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: NoData(
                        title: 'No projects',
                        message: 'Projects will appear here once created.',
                        asset: 'assets/no_projects.svg',
                      ),
                    ),
                  ),
                if (lateProjects.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Late (${lateProjects.length})', style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ),
                  ),
                if (lateProjects.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.all(12.0),
                    sliver: ref.watch(projectsGridViewProvider)
                        ? SliverGrid(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: gap,
                              mainAxisSpacing: gap,
                              // Slightly taller cards reduce vertical overflow risk on small widths
                              childAspectRatio: 1.2,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final p = lateProjects[index];
                                return _ProjectCard(project: p, onOpen: () => onOpenProject(p));
                              },
                              childCount: lateProjects.length,
                            ),
                          )
                        : SliverList.builder(
                            itemBuilder: (context, index) {
                              final p = lateProjects[index];
                              return _ProjectListTile(project: p, onOpen: () => onOpenProject(p));
                            },
                            itemCount: lateProjects.length,
                          ),
                  ),
                if (pendingProjects.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Your projects (${pendingProjects.length})', style: Theme.of(context).textTheme.titleMedium),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (pendingProjects.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.all(12.0),
                    sliver: ref.watch(projectsGridViewProvider)
                        ? SliverGrid(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: gap,
                              mainAxisSpacing: gap,
                              // Slightly taller cards reduce vertical overflow risk on small widths
                              childAspectRatio: 1.2,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final p = pendingProjects[index];
                                return _ProjectCard(project: p, onOpen: () => onOpenProject(p));
                              },
                              childCount: pendingProjects.length,
                            ),
                          )
                        : SliverList.builder(
                            itemBuilder: (context, index) {
                              final p = pendingProjects[index];
                              return _ProjectListTile(project: p, onOpen: () => onOpenProject(p));
                            },
                            itemCount: pendingProjects.length,
                          ),
                  ),
              ],
            );
          });
        },
      ),
    ),
  );
  }

}

class _MetricData {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  _MetricData(this.label, this.value, this.icon, this.color);
}

Widget _metricCard(BuildContext context, _MetricData m) {
  return Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(14.0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: m.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(m.icon, color: m.color),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.label, style: Theme.of(context).textTheme.bodyMedium),
            Text('${m.value}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
        ],
      ),
    ),
  );
}

typedef ProjectCreatedCallback = void Function(Project project, {String? projectCode});

class _ProjectCreatePage extends ConsumerStatefulWidget {
  const _ProjectCreatePage({this.onCreated});
  final ProjectCreatedCallback? onCreated;
  @override
  ConsumerState<_ProjectCreatePage> createState() => _ProjectCreatePageState();
}

class _ProjectCreatePageState extends ConsumerState<_ProjectCreatePage> {
  final _formKey = GlobalKey<FormState>();
  // Focus nodes for validation autofocus
  final _fnName = FocusNode();
  final _fnAddress = FocusNode();
  // final _fnVillage = FocusNode(); // replaced by dropdown
  // final _fnSarpanchName = FocusNode(); // name is auto-filled and read-only now
  final _fnSarpanchMobile = FocusNode();
  // final _fnGramPanchayat = FocusNode(); // removed with Basic Details dropdown
  // final _fnSecretaryName = FocusNode(); // name is auto-filled and read-only now
  final _fnSecretaryMobile = FocusNode();
  final _fnSubEngineerName = FocusNode();
  final _fnSubEngineerMobile = FocusNode();
  final _fnSanctionDept = FocusNode();
  final _fnItem = FocusNode();
  final _fnPlanHead = FocusNode();
  final _fnTechApprovalNo = FocusNode();
  final _fnAdminApprovalNo = FocusNode();
  final _fnBankName = FocusNode();
  final _fnAccountNumber = FocusNode();
  final _fnBranch = FocusNode();
  final _fnIFSC = FocusNode();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _villageCtrl = TextEditingController();
  // Section 1: preliminary description controllers (placeholders for future UI)
  final _sarpanchNameCtrl = TextEditingController();
  final _sarpanchMobileCtrl = TextEditingController();
  final _gramPanchayatCtrl = TextEditingController();
  final _secretaryNameCtrl = TextEditingController();
  final _secretaryMobileCtrl = TextEditingController();
  final _subEngineerNameCtrl = TextEditingController();
  final _subEngineerMobileCtrl = TextEditingController();
  
  // Section 2: Sanction & Compliance controllers
  final _technicalApprovalNoCtrl = TextEditingController();
  final _technicalApprovalDateCtrl = TextEditingController();
  final _adminApprovalNoCtrl = TextEditingController();
  final _adminApprovalDateCtrl = TextEditingController();
  final _approvedAmountCtrl = TextEditingController();
  final _sanctioningDepartmentCtrl = TextEditingController();
  final _schemeCtrl = TextEditingController();
  final _itemCtrl = TextEditingController();
  final _planHeadCtrl = TextEditingController();
  String? _selectedSanctioningDepartmentName;
  String? _selectedSchemeName;
  String? _selectedItemName;
  String? _selectedPlanHeadName;
  
  // Section 3: Allotment Details controllers
  final _installment1AmountCtrl = TextEditingController();
  final _installment1DateCtrl = TextEditingController();
  final _installment1ReceivedAmountCtrl = TextEditingController();
  final _installment1ReceivedDateCtrl = TextEditingController();
  final _installment2AmountCtrl = TextEditingController();
  final _installment2DateCtrl = TextEditingController();
  final _installment2ReceivedAmountCtrl = TextEditingController();
  final _installment2ReceivedDateCtrl = TextEditingController();
  final _installment3AmountCtrl = TextEditingController();
  final _installment3DateCtrl = TextEditingController();
  final _installment3ReceivedAmountCtrl = TextEditingController();
  final _installment3ReceivedDateCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  String? _selectedBankName;
  // Optional installments visibility
  bool _showInstallment2 = false;
  bool _showInstallment3 = false;
  
  // Section 4: Work Description controllers
  final _startDateCtrl = TextEditingController();
  final _endDateCtrl = TextEditingController();
  final _fnStartDate = FocusNode();
  // New: Project deadline
  final _deadlineCtrl = TextEditingController();
  WorkStage? _selectedWorkStage;
  ApramStatus? _selectedApramStatus;
  String? _selectedGramPanchayatName;
  int _currentStep = 0;
  double? _lat;
  double? _lng;
  bool _locating = false;
  final _photos = <XFile>[];
  final _docs = <XFile>[];
  // Removed video support per requirements
  // Section 2 specific files
  final _techApprovalDoc = <XFile>[]; // allow max 1
  final _techApprovalPhotos = <XFile>[]; // allow up to 3, <=7MB each
  final _adminApprovalDocs = <XFile>[]; // min 1 required
  // Section 4 categorized work documents
  final _mbDocs = <XFile>[]; // Measurement Books
  final _testReportDocs = <XFile>[]; // Test Reports
  final _workReportDocs = <XFile>[]; // Work Reports
  final _certificateDocs = <XFile>[]; // Certificates
  // Offline draft media store
  DraftMediaStore? _mediaStore;
  final _mapKey = GlobalKey();
  final MapController _mapController = MapController();
  bool _saving = false;
  // Upload progress state
  int _totalUploads = 0;
  int _completedUploads = 0;
  double _currentFileProgress = 0.0; // 0..1
  String _currentLabel = '';
  String? _lastUploadError; // sticky capture for better error messages
  // Per-file status and progress
  // keyed by DraftMediaItem.id
  final Map<String, String> _photoStatus = {}; // id -> pending|uploading|done|fail
  final Map<String, double> _photoProgress = {}; // id -> 0..1
  final Map<String, String> _docStatus = {};
  final Map<String, double> _docProgress = {};
  // Removed video status/progress per requirements
  // Finance & planning controllers
  final _budgetCtrl = TextEditingController();
  final _fundingCtrl = TextEditingController();
  final _contractorNameCtrl = TextEditingController();
  final _contractorContactCtrl = TextEditingController();
  final _labourCtrl = TextEditingController();
  final _etaCtrl = TextEditingController();
  // External links
  final _linkCtrl = TextEditingController();
  final List<String> _externalLinks = [];
  // Dropdown selections
  String? _selectedBlockId;
  String? _selectedBlockName;
  String? _selectedVillageName;
  // Local draft service
  LocalDraftService? _drafts;
  // Debounced autosave
  Timer? _saveTimer;
  late final List<TextEditingController> _draftControllers;
  bool _didRestoreDraft = false;
  // Schemes list: English (default) with Hindi shown in brackets
  static const List<_SchemeItem> _schemeItems = [
    _SchemeItem('Chief Minister Samagra Gramin Vikas Yojana', 'मुख्यमंत्री समग्र ग्रामीण विकास योजना'),
    _SchemeItem('CG State Rural and Other Backward Classes Area Development Authority', 'छ.ग. राज्य ग्रामीण एवं अन्य पिछड़ा वर्ग क्षेत्र विकास प्राधिकरण'),
    _SchemeItem('MGNREGA', 'मनरेगा'),
    _SchemeItem('Swachh Bharat Mission (Gram) District Panchayat Development Fund', 'स्वच्छ भारत मिशन (ग्रा.) जिला पंचायत विकास निध ि'),
    _SchemeItem('Capacity Development Fund', 'क्षमता विकास निध ि'),
    _SchemeItem('15th Finance Commission', '15 वें वित्त आयोग'),
    _SchemeItem('Mahatma Gandhi Rural Industrial Park (RIPA)', 'महात्मा गांधी रूरल इंडिस्ट्रयल पार्क (रीपा)'),
    _SchemeItem('Chief Minister Rural Internal', 'मुख्यमंत्री ग्रामीण आंतरिक'),
    _SchemeItem('Electrification Scheme', 'विद्युतीकरण योजना'),
    _SchemeItem('Mahatari Sadan Nirman Yojana', 'महतारी सदन निर्माण योजना'),
    _SchemeItem('Minor Minerals', 'गौण खनिज'),
    _SchemeItem('Eco Tourism Board', 'ईको टूरिज्म बोर्ड'),
    _SchemeItem('MP MLA Adarsh Gram Yojana', 'सांसद विधायक आदर्श ग्राम योजना'),
    _SchemeItem('School Education', 'स्कूल शिक्षा मद'),
    _SchemeItem('Pradhan Mantri Poshan Shakti Yojana', 'प्रधानमंत्री पोषण शक्ति योजना'),
    _SchemeItem('Minor Repairs (School Education)', 'लघु मरम्मत (स्कूल शिक्षा)'),
    _SchemeItem('Central Area Development Authority', 'मध्य क्षेत्र विकास प्राधिकरण'),
    _SchemeItem('Anganwadi Bhawan Construction', 'आंगनबाड़ी भवन निर्माण'),
    _SchemeItem('District Mineral Institute Trust Fund (DMF)', 'जिला खनिज संस्थान न्यास निध ि (डीएमएफ)'),
  ];

  // Static blocks as per spec (bypass Firestore for blocks)
  static const List<String> _staticBlocks = [
    'Dhamtari','Kurud','Nagri','Magarlod'
  ];
  bool _showAutosaved = false;
  Timer? _autosaveBadgeTimer;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
  _villageCtrl.dispose();
    _sarpanchNameCtrl.dispose();
    _sarpanchMobileCtrl.dispose();
    _gramPanchayatCtrl.dispose();
    _secretaryNameCtrl.dispose();
    _secretaryMobileCtrl.dispose();
    _subEngineerNameCtrl.dispose();
    _subEngineerMobileCtrl.dispose();
    _budgetCtrl.dispose();
    _fundingCtrl.dispose();
    _contractorNameCtrl.dispose();
    _contractorContactCtrl.dispose();
    _labourCtrl.dispose();
    _etaCtrl.dispose();
    _linkCtrl.dispose();
    _technicalApprovalNoCtrl.dispose();
    _technicalApprovalDateCtrl.dispose();
    _adminApprovalNoCtrl.dispose();
    _adminApprovalDateCtrl.dispose();
    _approvedAmountCtrl.dispose();
  _sanctioningDepartmentCtrl.dispose();
  _schemeCtrl.dispose();
  _itemCtrl.dispose();
  _planHeadCtrl.dispose();
    _installment1AmountCtrl.dispose();
    _installment1DateCtrl.dispose();
    _installment1ReceivedAmountCtrl.dispose();
    _installment1ReceivedDateCtrl.dispose();
    _installment2AmountCtrl.dispose();
    _installment2DateCtrl.dispose();
    _installment2ReceivedAmountCtrl.dispose();
    _installment2ReceivedDateCtrl.dispose();
    _installment3AmountCtrl.dispose();
    _installment3DateCtrl.dispose();
    _installment3ReceivedAmountCtrl.dispose();
    _installment3ReceivedDateCtrl.dispose();
    _accountNumberCtrl.dispose();
    _branchCtrl.dispose();
    _ifscCtrl.dispose();
  _bankNameCtrl.dispose();
  _startDateCtrl.dispose();
  _endDateCtrl.dispose();
  _deadlineCtrl.dispose();
  _saveTimer?.cancel();
  _autosaveBadgeTimer?.cancel();
    super.dispose();
  }

  IconData _stageIcon(WorkStage s) {
    switch (s) {
      case WorkStage.layout:
        return CupertinoIcons.map;
      case WorkStage.plinth:
        return Icons.foundation;
      case WorkStage.lintel:
        return Icons.architecture;
      case WorkStage.finishing:
        return Icons.brush;
      case WorkStage.completed:
        return CupertinoIcons.check_mark_circled;
    }
  }

  // Responsive helpers: stack on narrow screens, two-up on wide screens
  Widget _pair(Widget left, Widget right) {
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 640; // phones and small tablets
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            left,
            const SizedBox(height: 8),
            right,
          ],
        );
      }
      return Row(children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ]);
    });
  }

  Widget _singleOrEmpty(Widget child, {Widget empty = const SizedBox.shrink()}) {
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 640;
      if (narrow) {
        return child;
      }
      return Row(children: [
        Expanded(child: child),
        const SizedBox(width: 12),
        Expanded(child: empty),
      ]);
    });
  }

  Widget _fieldAndButton({required Widget field, required Widget button}) {
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 520;
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: button),
          ],
        );
      }
      return Row(children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        button,
      ]);
    });
  }

  @override
  void initState() {
    super.initState();
    // Wire up autosave for key draft fields
    _draftControllers = [
      _nameCtrl,
      _descCtrl,
      _addressCtrl,
  _villageCtrl,
      _sarpanchNameCtrl,
      _sarpanchMobileCtrl,
      _secretaryNameCtrl,
      _secretaryMobileCtrl,
      _subEngineerNameCtrl,
      _subEngineerMobileCtrl,
  _gramPanchayatCtrl,
      _technicalApprovalNoCtrl,
      _technicalApprovalDateCtrl,
      _adminApprovalNoCtrl,
      _adminApprovalDateCtrl,
      _approvedAmountCtrl,
  _sanctioningDepartmentCtrl,
  _schemeCtrl,
  _itemCtrl,
  _planHeadCtrl,
      _installment1AmountCtrl,
      _installment1DateCtrl,
      _installment1ReceivedAmountCtrl,
      _installment1ReceivedDateCtrl,
      _installment2AmountCtrl,
      _installment2DateCtrl,
      _installment2ReceivedAmountCtrl,
      _installment2ReceivedDateCtrl,
      _installment3AmountCtrl,
      _installment3DateCtrl,
      _installment3ReceivedAmountCtrl,
      _installment3ReceivedDateCtrl,
      _accountNumberCtrl,
      _branchCtrl,
      _ifscCtrl,
  _bankNameCtrl,
  ];
    // Initialize local draft service and restore any draft
    try {
      final prefs = ref.read(sharedPrefsProvider);
      _drafts = LocalDraftService(prefs);
      _tryRestoreDraft();
    } catch (_) {
      // sharedPrefsProvider not overridden; skip drafts silently
    }
    // Debounced autosave on edits
    for (final c in _draftControllers) {
      c.addListener(_scheduleAutosave);
    }
  }

  void _scheduleAutosave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () async {
      await _saveDraftLocally();
      if (!mounted) return;
      setState(() {
        _showAutosaved = true;
      });
      _autosaveBadgeTimer?.cancel();
      _autosaveBadgeTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showAutosaved = false;
          });
        }
      });
    });
  }

  void _tryRestoreDraft() {
    final d = _drafts?.loadDraft();
    if (d == null) return;
    // Minimal safe restores; more fields will be added as UI expands
    _nameCtrl.text = (d['name'] as String?) ?? _nameCtrl.text;
    _descCtrl.text = (d['description'] as String?) ?? _descCtrl.text;
    _addressCtrl.text = (d['address'] as String?) ?? _addressCtrl.text;
  _selectedBlockId = d['blockId'] as String? ?? _selectedBlockId;
  _selectedBlockName = d['blockName'] as String? ?? _selectedBlockName;
  _villageCtrl.text = (d['villageName'] as String?) ?? _villageCtrl.text;
  _selectedVillageName = _villageCtrl.text.trim().isEmpty ? _selectedVillageName : _villageCtrl.text.trim();
    // Preliminary
    _sarpanchNameCtrl.text = (d['sarpanchName'] as String?) ?? _sarpanchNameCtrl.text;
    _sarpanchMobileCtrl.text = (d['sarpanchMobile'] as String?) ?? _sarpanchMobileCtrl.text;
    _secretaryNameCtrl.text = (d['secretaryName'] as String?) ?? _secretaryNameCtrl.text;
    _secretaryMobileCtrl.text = (d['secretaryMobile'] as String?) ?? _secretaryMobileCtrl.text;
    _subEngineerNameCtrl.text = (d['subEngineerName'] as String?) ?? _subEngineerNameCtrl.text;
    _subEngineerMobileCtrl.text = (d['subEngineerMobile'] as String?) ?? _subEngineerMobileCtrl.text;
  _gramPanchayatCtrl.text = (d['gramPanchayatName'] as String?) ?? _gramPanchayatCtrl.text;
  _selectedGramPanchayatName = _gramPanchayatCtrl.text.trim().isEmpty ? _selectedGramPanchayatName : _gramPanchayatCtrl.text.trim();
    // Sanction & Compliance
  _sanctioningDepartmentCtrl.text = (d['sanctionDeptName'] as String?) ?? _sanctioningDepartmentCtrl.text;
  _selectedSanctioningDepartmentName = _sanctioningDepartmentCtrl.text.trim().isEmpty ? _selectedSanctioningDepartmentName : _sanctioningDepartmentCtrl.text.trim();
  _schemeCtrl.text = (d['schemeName'] as String?) ?? _schemeCtrl.text;
  _selectedSchemeName = _schemeCtrl.text.trim().isEmpty ? _selectedSchemeName : _schemeCtrl.text.trim();
  _itemCtrl.text = (d['itemName'] as String?) ?? _itemCtrl.text;
  _selectedItemName = _itemCtrl.text.trim().isEmpty ? _selectedItemName : _itemCtrl.text.trim();
  _planHeadCtrl.text = (d['planHeadName'] as String?) ?? _planHeadCtrl.text;
  _selectedPlanHeadName = _planHeadCtrl.text.trim().isEmpty ? _selectedPlanHeadName : _planHeadCtrl.text.trim();
    _technicalApprovalNoCtrl.text = (d['technicalApprovalNo'] as String?) ?? _technicalApprovalNoCtrl.text;
    _technicalApprovalDateCtrl.text = (d['technicalApprovalDate'] as String?) ?? _technicalApprovalDateCtrl.text;
    _adminApprovalNoCtrl.text = (d['adminApprovalNo'] as String?) ?? _adminApprovalNoCtrl.text;
    _adminApprovalDateCtrl.text = (d['adminApprovalDate'] as String?) ?? _adminApprovalDateCtrl.text;
    _approvedAmountCtrl.text = (d['approvedAmount'] as String?) ?? _approvedAmountCtrl.text;
    // Allotment & Bank
    _installment1AmountCtrl.text = (d['installment1Amount'] as String?) ?? _installment1AmountCtrl.text;
    _installment1DateCtrl.text = (d['installment1Date'] as String?) ?? _installment1DateCtrl.text;
    _installment1ReceivedAmountCtrl.text = (d['installment1ReceivedAmount'] as String?) ?? _installment1ReceivedAmountCtrl.text;
    _installment1ReceivedDateCtrl.text = (d['installment1ReceivedDate'] as String?) ?? _installment1ReceivedDateCtrl.text;
    _installment2AmountCtrl.text = (d['installment2Amount'] as String?) ?? _installment2AmountCtrl.text;
    _installment2DateCtrl.text = (d['installment2Date'] as String?) ?? _installment2DateCtrl.text;
    _installment2ReceivedAmountCtrl.text = (d['installment2ReceivedAmount'] as String?) ?? _installment2ReceivedAmountCtrl.text;
    _installment2ReceivedDateCtrl.text = (d['installment2ReceivedDate'] as String?) ?? _installment2ReceivedDateCtrl.text;
    _installment3AmountCtrl.text = (d['installment3Amount'] as String?) ?? _installment3AmountCtrl.text;
    _installment3DateCtrl.text = (d['installment3Date'] as String?) ?? _installment3DateCtrl.text;
    _installment3ReceivedAmountCtrl.text = (d['installment3ReceivedAmount'] as String?) ?? _installment3ReceivedAmountCtrl.text;
    _installment3ReceivedDateCtrl.text = (d['installment3ReceivedDate'] as String?) ?? _installment3ReceivedDateCtrl.text;
  _bankNameCtrl.text = (d['bankName'] as String?) ?? _bankNameCtrl.text;
  _selectedBankName = _bankNameCtrl.text.trim().isEmpty ? _selectedBankName : _bankNameCtrl.text.trim();
    _accountNumberCtrl.text = (d['accountNumber'] as String?) ?? _accountNumberCtrl.text;
    _branchCtrl.text = (d['branch'] as String?) ?? _branchCtrl.text;
    _ifscCtrl.text = (d['ifsc'] as String?) ?? _ifscCtrl.text;
    // Work
  _startDateCtrl.text = (d['workStartDate'] as String?) ?? _startDateCtrl.text;
  _endDateCtrl.text = (d['workEndDate'] as String?) ?? _endDateCtrl.text;
  _deadlineCtrl.text = (d['deadline'] as String?) ?? _deadlineCtrl.text;
    final ws = d['workStage'] as String?;
    if (ws != null) {
      _selectedWorkStage = WorkStage.values.firstWhere(
        (e) => e.name == ws,
        orElse: () => _selectedWorkStage ?? WorkStage.layout,
      );
    }
    final as = d['apramStatus'] as String?;
    if (as != null) {
      _selectedApramStatus = ApramStatus.values.firstWhere(
        (e) => e.name == as,
        orElse: () => _selectedApramStatus ?? ApramStatus.incomplete,
      );
    }
    final loc = d['location'];
    if (loc is Map) {
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        _lat = lat;
        _lng = lng;
      }
    }
    // External links
    final ln = d['externalLinks'];
    if (ln is List) {
      _externalLinks
        ..clear()
        ..addAll(ln.whereType<String>());
    }
    // Step index
  final step = d['currentStep'];
    if (step is int) {
      _currentStep = step.clamp(0, 3);
    }
  // Reveal optional installments if any fields were entered
  _showInstallment2 = _installment2AmountCtrl.text.trim().isNotEmpty ||
    _installment2DateCtrl.text.trim().isNotEmpty ||
    _installment2ReceivedAmountCtrl.text.trim().isNotEmpty ||
    _installment2ReceivedDateCtrl.text.trim().isNotEmpty;
  _showInstallment3 = _installment3AmountCtrl.text.trim().isNotEmpty ||
    _installment3DateCtrl.text.trim().isNotEmpty ||
    _installment3ReceivedAmountCtrl.text.trim().isNotEmpty ||
    _installment3ReceivedDateCtrl.text.trim().isNotEmpty;
  setState(() { _didRestoreDraft = true; });
  }

  Future<void> _saveDraftLocally() async {
    final d = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
    'blockId': _selectedBlockId,
  'blockName': _selectedBlockName,
  'villageName': _villageCtrl.text.trim(),
  // Preliminary
  'sarpanchName': _sarpanchNameCtrl.text.trim(),
  'sarpanchMobile': _sarpanchMobileCtrl.text.trim(),
  'secretaryName': _secretaryNameCtrl.text.trim(),
  'secretaryMobile': _secretaryMobileCtrl.text.trim(),
  'subEngineerName': _subEngineerNameCtrl.text.trim(),
  'subEngineerMobile': _subEngineerMobileCtrl.text.trim(),
  'gramPanchayatName': _gramPanchayatCtrl.text.trim(),
  // Sanction & Compliance
  'sanctionDeptName': _sanctioningDepartmentCtrl.text.trim(),
  'schemeName': _schemeCtrl.text.trim(),
  'itemName': _itemCtrl.text.trim(),
  'planHeadName': _planHeadCtrl.text.trim(),
  'technicalApprovalNo': _technicalApprovalNoCtrl.text.trim(),
  'technicalApprovalDate': _technicalApprovalDateCtrl.text.trim(),
  'adminApprovalNo': _adminApprovalNoCtrl.text.trim(),
  'adminApprovalDate': _adminApprovalDateCtrl.text.trim(),
  'approvedAmount': _approvedAmountCtrl.text.trim(),
  // Allotment & Bank
  'installment1Amount': _installment1AmountCtrl.text.trim(),
  'installment1Date': _installment1DateCtrl.text.trim(),
  'installment1ReceivedAmount': _installment1ReceivedAmountCtrl.text.trim(),
  'installment1ReceivedDate': _installment1ReceivedDateCtrl.text.trim(),
  'installment2Amount': _installment2AmountCtrl.text.trim(),
  'installment2Date': _installment2DateCtrl.text.trim(),
  'installment2ReceivedAmount': _installment2ReceivedAmountCtrl.text.trim(),
  'installment2ReceivedDate': _installment2ReceivedDateCtrl.text.trim(),
  'installment3Amount': _installment3AmountCtrl.text.trim(),
  'installment3Date': _installment3DateCtrl.text.trim(),
  'installment3ReceivedAmount': _installment3ReceivedAmountCtrl.text.trim(),
  'installment3ReceivedDate': _installment3ReceivedDateCtrl.text.trim(),
  'bankName': _bankNameCtrl.text.trim(),
  'accountNumber': _accountNumberCtrl.text.trim(),
  'branch': _branchCtrl.text.trim(),
  'ifsc': _ifscCtrl.text.trim(),
  // Work
  'workStartDate': _startDateCtrl.text.trim(),
  'workEndDate': _endDateCtrl.text.trim(),
  'deadline': _deadlineCtrl.text.trim(),
  'workStage': _selectedWorkStage?.name,
  'apramStatus': _selectedApramStatus?.name,
      'location': {
        if (_lat != null && _lng != null) 'lat': _lat,
        if (_lat != null && _lng != null) 'lng': _lng
      },
  'externalLinks': List.of(_externalLinks),
  'currentStep': _currentStep,
    };
    await _drafts?.saveDraft(d);
  }

  // _pickVideos removed per requirements

  // Render a label with required indicator
  InputDecoration _req(String label, {Widget? prefixIcon}) => InputDecoration(
        label: RequiredLabel(label),
        prefixIcon: prefixIcon,
      );

  // Section 3: received status options
  static const receivedStatusOptions = <String>['Received', 'Not Received', 'Not Applicable'];
  String? _installment1Status;
  String? _installment2Status;
  String? _installment3Status;

  static const List<String> _ones = [
    'zero','one','two','three','four','five','six','seven','eight','nine','ten','eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen'
  ];
  static const List<String> _tens = [
    '','','twenty','thirty','forty','fifty','sixty','seventy','eighty','ninety'
  ];
  String _twoDigits(int n) {
    if (n < 20) return _ones[n];
    final t = n ~/ 10;
    final o = n % 10;
    return _tens[t] + (o > 0 ? '-${_ones[o]}' : '');
  }
  String _threeDigits(int n) {
    final h = n ~/ 100;
    final r = n % 100;
    if (h == 0) return _twoDigits(r);
    final head = '${_ones[h]} hundred';
    if (r == 0) return head;
    return '$head ${_twoDigits(r)}';
  }
  String _toIndianWords(int n) {
    if (n == 0) return 'zero';
    final parts = <String>[];
    final crore = n ~/ 10000000;
    final lakh = (n % 10000000) ~/ 100000;
    final thousand = (n % 100000) ~/ 1000;
    final hundred = n % 1000;
    // Use three-digits for crores to support values >= 100 crores safely
    if (crore > 0) parts.add('${crore < 100 ? _twoDigits(crore) : _threeDigits(crore)} crore');
    if (lakh > 0) parts.add('${_twoDigits(lakh)} lakh');
    if (thousand > 0) parts.add('${_twoDigits(thousand)} thousand');
    if (hundred > 0) parts.add(_threeDigits(hundred));
    return parts.join(' ');
  }

  // Sanitize file names for Storage: allow letters, numbers, dot, underscore, hyphen; replace others with '_'
  String _safeName(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  // Human-readable size like 1.2 MB
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024.0;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  // Icon color by content-type
  (IconData, Color) _iconForContentType(String ct, BuildContext context) {
  final cs = Theme.of(context).colorScheme;
    if (ct.startsWith('image/')) return (Icons.image, cs.primary);
    if (ct == 'application/pdf') return (Icons.picture_as_pdf, Colors.redAccent);
    if (ct.contains('sheet') || ct.contains('excel') || ct == 'text/csv') return (Icons.table_chart, Colors.green);
    if (ct.contains('word') || ct.endsWith('/msword')) return (Icons.description, Colors.blueAccent);
    return (Icons.insert_drive_file, cs.secondary);
  }

  // Unified file card with progress/status and remove
  Widget _fileCard(DraftMediaItem it) {
    final isImage = it.contentType.startsWith('image/');
    final statusMap = isImage ? _photoStatus : _docStatus;
    final progMap = isImage ? _photoProgress : _docProgress;
    final status = statusMap[it.id] ?? 'pending';
    final prog = progMap[it.id] ?? 0.0;
    final (iconData, iconColor) = _iconForContentType(it.contentType, context);
    return SizedBox(
      width: 280,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(iconData, color: iconColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('${_formatBytes(it.size)} • ${it.contentType}', style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () async {
                      await _mediaStore?.remove(it.id);
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(CupertinoIcons.delete),
                  ),
                ],
              ),
              if (status == 'uploading' || status == 'fail' || status == 'done') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (status == 'uploading') ...[
                      Expanded(child: LinearProgressIndicator(value: prog)),
                      const SizedBox(width: 8),
                      Text('${(prog * 100).toStringAsFixed(0)}%', style: Theme.of(context).textTheme.labelSmall),
                    ] else if (status == 'done') ...[
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Text('Uploaded', style: Theme.of(context).textTheme.labelSmall),
                    ] else ...[
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 6),
                      Text('Failed', style: Theme.of(context).textTheme.labelSmall),
                    ]
                  ],
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  // Convert a numeric amount string to Indian currency words for helper text
  String? _amountToWordsString(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    // Normalize: remove commas, allow period for paise
    final norm = t.replaceAll(',', '');
    final value = double.tryParse(norm);
    if (value == null) return null;
    final rupees = value.floor();
    final paise = ((value - rupees) * 100).round();
    final r = _toIndianWords(rupees);
    final rsLabel = rupees == 1 ? ' rupee' : ' rupees';
    final p = paise > 0 ? ' and ${_twoDigits(paise)} paise' : '';
    return '$r$rsLabel$p only';
  }

  // Common amount field with optional required validation and helper words
  // Supports extraValidator for cross-field rules (e.g., sum of installments ≤ approved amount)
  Widget _amountField(
    TextEditingController controller,
    String label, {
    bool required = false,
    FocusNode? focusNode,
    String? Function(String?)? extraValidator,
  }) {
    // Max allowed amount: 50 crores (₹50,00,00,000)
    const maxRupees = 500000000; // 50 * 1 crore (10,000,000)
    final words = _amountToWordsString(controller.text);
    final decoration = required
        ? _req(label, prefixIcon: const Icon(Icons.currency_rupee))
        : const InputDecoration(labelText: null).copyWith(labelText: label, prefixIcon: const Icon(Icons.currency_rupee));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          focusNode: focusNode,
          controller: controller,
          decoration: decoration,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[0-9,\.]")),
            LengthLimitingTextInputFormatter(18),
          ],
          onChanged: (_) => setState(() {}),
          validator: (v) {
            final t = (v ?? '').trim();
            if (required && t.isEmpty) return 'Required';
            if (t.isEmpty) return null;
            final norm = t.replaceAll(',', '');
            final parsed = double.tryParse(norm);
            if (parsed == null) return 'Enter valid amount';
            if (parsed > maxRupees) return 'Max ₹50,00,00,000 (50 crores)';
            if (extraValidator != null) {
              final er = extraValidator(v);
              if (er != null) return er;
            }
            return null;
          },
        ),
        if (words != null && words.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text('≈ $words', style: Theme.of(context).textTheme.labelSmall),
          ),
      ],
    );
  }

  Future<void> _clearDraftLocally() async {
    await _drafts?.clearDraft();
  }

  // Removed _focusFirstInvalidInCurrentStep() as Next no longer runs global validation.

  // After changing step, focus the first field in that step to guide data entry
  void _focusFirstFieldInStep(int step) {
    Future<void> focus(FocusNode n) async {
      n.requestFocus();
      final ctx = n.context;
      if (ctx != null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
      }
    }
    switch (step) {
      case 0:
  focus(_fnSarpanchMobile);
        break;
      case 1:
        focus(_fnSanctionDept);
        break;
      case 2:
        focus(_fnBankName);
        break;
      case 3:
  // Focus the Work section's first field (start date) to avoid jumping back to Basic Details
  focus(_fnStartDate);
        break;
    }
  }

  Future<void> _getLocation() async {
  // messenger removed; using toastification for user feedback
    setState(() => _locating = true);
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        if (mounted) {
          toastification.show(
            context: context,
            title: const Text('Location permission denied'),
            type: ToastificationType.warning,
            style: ToastificationStyle.fillColored,
            autoCloseDuration: const Duration(seconds: 3),
            showProgressBar: false,
            icon: const Icon(CupertinoIcons.location_slash),
          );
        }
        return;
      }
  final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
  // Enforce location within Chhattisgarh bounds (approx): lat 17.78..24.10, lng 80.22..84.40
  const cgMinLat = 17.78, cgMaxLat = 24.10, cgMinLng = 80.22, cgMaxLng = 84.40;
  final lat = pos.latitude, lng = pos.longitude;
  final inCG = lat >= cgMinLat && lat <= cgMaxLat && lng >= cgMinLng && lng <= cgMaxLng;
  if (!inCG) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please capture a location within Chhattisgarh.')));
    }
  } else {
    setState(() {
      _lat = lat;
      _lng = lng;
    });
  }
      // Recenter map view when coordinates update
      try {
        if (_lat != null && _lng != null) {
          _mapController.move(LatLng(_lat!, _lng!), 16);
        }
      } catch (_) {}
  // autosave location
  await _saveDraftLocally();
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          title: const Text('Location error'),
          description: Text('$e'),
          type: ToastificationType.error,
          style: ToastificationStyle.fillColored,
          autoCloseDuration: const Duration(seconds: 4),
          showProgressBar: true,
          icon: const Icon(CupertinoIcons.exclamationmark_triangle),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickPhotos() async {
    if (_mediaStore == null || !_mediaStore!.ready) {
      final store = ref.read(draftMediaStoreProvider);
      await store.init();
      _mediaStore = store;
    }
    final picker = ImagePicker();
    final imgs = await picker.pickMultiImage(imageQuality: 85);
    if (!mounted) return;
    // Allow jpg/jpeg/png/heic up to 5MB each, cap list to 5
    const maxBytes = 5 * 1024 * 1024;
    final allowed = {'jpg','jpeg','png','heic','heif'};
    final current = _mediaStore?.list(category: 'work_photo').length ?? 0;
    int remaining = (5 - current).clamp(0, 5);
    for (final x in imgs) {
      if (remaining <= 0) break;
      final ext = x.name.split('.').last.toLowerCase();
      if (!allowed.contains(ext)) continue;
      final len = await x.length();
      if (len > maxBytes) continue;
      final id = await _mediaStore!.addFromXFile(x, category: 'work_photo', maxBytes: maxBytes);
      _photoStatus[id] = 'pending';
      _photoProgress[id] = 0.0;
      remaining--;
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickDocs() async {
    if (_mediaStore == null || !_mediaStore!.ready) {
      final store = ref.read(draftMediaStoreProvider);
      await store.init();
      _mediaStore = store;
    }
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withReadStream: !kIsWeb,
      withData: kIsWeb,
      type: FileType.custom,
    // Support PDF, Excel, and Office docs (Google exported as Office)
    allowedExtensions: const ['pdf','xls','xlsx','csv','doc','docx'],
    );
  if (res == null) return;
  if (!mounted) return;
    for (final f in res.files) {
      if (f.size > 10 * 1024 * 1024) {
        toastification.show(
          context: context,
      title: Text('Skipping ${f.name}: >10MB'),
          type: ToastificationType.info,
          style: ToastificationStyle.fillColored,
          autoCloseDuration: const Duration(seconds: 2),
          showProgressBar: false,
          icon: const Icon(CupertinoIcons.info),
        );
        continue;
      }
      final name = f.name;
      final ext = name.split('.').last.toLowerCase();
    const allowed = ['pdf','xls','xlsx','csv','doc','docx'];
      if (!allowed.contains(ext)) {
        toastification.show(
          context: context,
          title: Text('Skipping ${f.name}'),
      description: const Text('Use PDF/Excel/Doc only'),
          type: ToastificationType.info,
          style: ToastificationStyle.fillColored,
          autoCloseDuration: const Duration(seconds: 2),
          showProgressBar: false,
          icon: const Icon(CupertinoIcons.info),
        );
        continue;
      }
      // Add to offline store under generic work docs
  // On Web, use in-memory bytes; on Mobile, use XFile via path
  final id = await _mediaStore!.addFromPlatformFile(f, category: 'work_doc', maxBytes: 10 * 1024 * 1024);
  _docStatus[id] = 'pending';
  _docProgress[id] = 0.0;
    }
    setState(() {});
  }

  Future<void> _pickTechApprovalDoc() async {
    if (_mediaStore == null || !_mediaStore!.ready) {
      final store = ref.read(draftMediaStoreProvider);
      await store.init();
      _mediaStore = store;
    }
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withReadStream: !kIsWeb,
      withData: kIsWeb,
      type: FileType.custom,
  // Restrict to PDF only as per rules
  allowedExtensions: const ['pdf'],
    );
    if (res == null) return;
    if (!mounted) return;
    final f = res.files.first;
    if (f.size > StorageService.maxDocBytes) {
      toastification.show(
        context: context,
        title: const Text('Document too large'),
        description: const Text('Must be <= 20MB'),
        type: ToastificationType.warning,
        style: ToastificationStyle.fillColored,
        autoCloseDuration: const Duration(seconds: 3),
        showProgressBar: false,
  icon: const Icon(CupertinoIcons.doc_plaintext),
      );
      return;
    }
  // Allow both PDF and Photos together; do not clear other category
  final id = await _mediaStore!.addFromPlatformFile(f, category: 'sanction_tech_doc', maxBytes: StorageService.maxDocBytes);
  _docStatus[id] = 'pending';
  _docProgress[id] = 0.0;
    if (mounted) setState(() {});
  }

  Future<void> _pickTechApprovalPhotos() async {
    if (_mediaStore == null || !_mediaStore!.ready) {
      final store = ref.read(draftMediaStoreProvider);
      await store.init();
      _mediaStore = store;
    }
    final picker = ImagePicker();
    final imgs = await picker.pickMultiImage(imageQuality: 85);
    if (!mounted) return;
  const maxBytes = 5 * 1024 * 1024; // 5MB per photo
  // Allow both PDF and Photos together; do not clear other category
    int added = 0;
    for (final x in imgs) {
      if (added >= 3) break;
      final ext = x.name.split('.').last.toLowerCase();
      if (!{'jpg','jpeg','png','heic','heif'}.contains(ext)) continue;
      if (await x.length() > maxBytes) continue;
      final id = await _mediaStore!.addFromXFile(x, category: 'sanction_tech_photo', maxBytes: maxBytes);
      _photoStatus[id] = 'pending';
      _photoProgress[id] = 0.0;
      added++;
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickAdminApprovalDocs() async {
    if (_mediaStore == null || !_mediaStore!.ready) {
      final store = ref.read(draftMediaStoreProvider);
      await store.init();
      _mediaStore = store;
    }
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withReadStream: !kIsWeb,
      withData: kIsWeb,
      type: FileType.custom,
  // Restrict to PDF only as per rules
  allowedExtensions: const ['pdf'],
    );
    if (res == null) return;
    if (!mounted) return;
  for (final f in res.files) {
      if (f.size > StorageService.maxDocBytes) {
        toastification.show(
          context: context,
          title: Text('Skipping ${f.name} (>20MB)'),
          type: ToastificationType.info,
          style: ToastificationStyle.fillColored,
          autoCloseDuration: const Duration(seconds: 2),
          showProgressBar: false,
          icon: const Icon(CupertinoIcons.info),
        );
        continue;
      }
  final id = await _mediaStore!.addFromPlatformFile(f, category: 'sanction_admin_doc', maxBytes: StorageService.maxDocBytes);
  _docStatus[id] = 'pending';
  _docProgress[id] = 0.0;
    }
    setState(() {});
  }

  Future<void> _pickGenericDocsCategory(String category) async {
    if (_mediaStore == null || !_mediaStore!.ready) {
      final store = ref.read(draftMediaStoreProvider);
      await store.init();
      _mediaStore = store;
    }
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withReadStream: !kIsWeb,
      withData: kIsWeb,
      type: FileType.custom,
    allowedExtensions: const ['pdf','xls','xlsx','csv','doc','docx'],
    );
    if (res == null) return;
    if (!mounted) return;
    // Using toastification for feedback
    for (final f in res.files) {
      if (f.size > 10 * 1024 * 1024) {
        toastification.show(
          context: context,
      title: Text('Skipping ${f.name}: >10MB'),
          type: ToastificationType.info,
          style: ToastificationStyle.fillColored,
          autoCloseDuration: const Duration(seconds: 2),
          showProgressBar: false,
          icon: const Icon(CupertinoIcons.info),
        );
        continue;
      }
      final name = f.name;
      final ext = name.split('.').last.toLowerCase();
    const allowed = ['pdf','xls','xlsx','csv','doc','docx'];
      if (!allowed.contains(ext)) {
        toastification.show(
          context: context,
          title: Text('Skipping ${f.name}'),
      description: const Text('Use PDF/Excel/Doc only'),
          type: ToastificationType.info,
          style: ToastificationStyle.fillColored,
          autoCloseDuration: const Duration(seconds: 2),
          showProgressBar: false,
          icon: const Icon(CupertinoIcons.info),
        );
        continue;
      }
  final id = await _mediaStore!.addFromPlatformFile(f, category: category, maxBytes: 10 * 1024 * 1024);
  _docStatus[id] = 'pending';
  _docProgress[id] = 0.0;
    }
    setState(() {});
  }

  Future<void> _pickMeasurementBooks() async => _pickGenericDocsCategory('work_mb');
  Future<void> _pickTestReports() async => _pickGenericDocsCategory('work_test');
  Future<void> _pickWorkReports() async => _pickGenericDocsCategory('work_workrep');
  Future<void> _pickCertificates() async => _pickGenericDocsCategory('work_cert');

  void _addExternalLink() {
    final raw = _linkCtrl.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    final hasScheme = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!hasScheme) {
      toastification.show(
        context: context,
        title: const Text('Enter a valid http(s) URL'),
        type: ToastificationType.warning,
        style: ToastificationStyle.fillColored,
        autoCloseDuration: const Duration(seconds: 2),
        showProgressBar: false,
  icon: const Icon(CupertinoIcons.link),
      );
      return;
    }
    setState(() {
      if (!_externalLinks.contains(raw)) {
        _externalLinks.add(raw);
      }
      _linkCtrl.clear();
    });
    _saveDraftLocally();
  }

  Future<void> _resetForm() async {
    // Clear controllers
    for (final c in [
      _nameCtrl,
      _descCtrl,
      _addressCtrl,
      _villageCtrl,
      _sarpanchNameCtrl,
      _sarpanchMobileCtrl,
      _gramPanchayatCtrl,
      _secretaryNameCtrl,
      _secretaryMobileCtrl,
      _subEngineerNameCtrl,
      _subEngineerMobileCtrl,
      _technicalApprovalNoCtrl,
      _technicalApprovalDateCtrl,
      _adminApprovalNoCtrl,
      _adminApprovalDateCtrl,
      _approvedAmountCtrl,
  _sanctioningDepartmentCtrl,
  _schemeCtrl,
  _itemCtrl,
  _planHeadCtrl,
      _installment1AmountCtrl,
      _installment1DateCtrl,
      _installment1ReceivedAmountCtrl,
      _installment1ReceivedDateCtrl,
      _installment2AmountCtrl,
      _installment2DateCtrl,
      _installment2ReceivedAmountCtrl,
      _installment2ReceivedDateCtrl,
      _installment3AmountCtrl,
      _installment3DateCtrl,
      _installment3ReceivedAmountCtrl,
      _installment3ReceivedDateCtrl,
      _accountNumberCtrl,
      _branchCtrl,
      _ifscCtrl,
  _bankNameCtrl,
      _startDateCtrl,
      _linkCtrl,
    ]) {
      c.clear();
    }
  // Clear picks (legacy lists) and offline media store
  _photos.clear();
  _docs.clear();
  _techApprovalDoc.clear();
  _techApprovalPhotos.clear();
  _adminApprovalDocs.clear();
  _mbDocs.clear();
  _testReportDocs.clear();
  _workReportDocs.clear();
  _certificateDocs.clear();
  await _mediaStore?.clear();
    // Clear statuses
  _photoStatus.clear();
  _photoProgress.clear();
  _docStatus.clear();
  _docProgress.clear();
  // video state removed
  // Clear selections (IDs not used in manual mode)
    _selectedSanctioningDepartmentName = null;
    _selectedSchemeName = null;
    _selectedItemName = null;
    _selectedPlanHeadName = null;
    _selectedBankName = null;
    _selectedGramPanchayatName = null;
    _selectedWorkStage = null;
    _selectedApramStatus = null;
  _selectedBlockId = null;
    _lat = null;
    _lng = null;
    _externalLinks.clear();
    _currentStep = 0;
    _didRestoreDraft = false;
    await _clearDraftLocally();
    if (!mounted) return;
    setState(() {});
  // Toast shown by caller if needed
  }

  Widget _buildPreliminarySection() {
  final basicValid = (_selectedBlockId?.isNotEmpty ?? false) &&
    (_gramPanchayatCtrl.text.trim().isNotEmpty) &&
    (_selectedVillageName?.isNotEmpty ?? false);
  final content = Column(children: [
    const SizedBox(height: 8),
    _pair(
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          controller: _sarpanchNameCtrl,
      enabled: false,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s\-\.\u0900-\u097F]")),
            LengthLimitingTextInputFormatter(60),
          ],
          decoration: _req('Sarpanch Name (सरपंच नाम)', prefixIcon: const Icon(CupertinoIcons.person)),
          validator: (v)=> (v==null||v.trim().isEmpty)?'Required':null,
        ),
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          focusNode: _fnSarpanchMobile,
          controller: _sarpanchMobileCtrl,
          decoration: _req('Sarpanch Mobile (मोबाइल)', prefixIcon: const Icon(CupertinoIcons.phone)) .copyWith(prefixText: '+91 '),
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
          validator: (v){ final s=(v??'').trim(); if(s.length!=10) return '10 digits'; return null; },
        ),
      ),
      const SizedBox(height: 8),
      _pair(
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          controller: _secretaryNameCtrl,
      enabled: false,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s\-\.\u0900-\u097F]")),
            LengthLimitingTextInputFormatter(60),
          ],
          decoration: _req('Secretary Name (सचिव नाम)', prefixIcon: const Icon(CupertinoIcons.person)),
          validator: (v)=> (v==null||v.trim().isEmpty)?'Required':null,
        ),
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          focusNode: _fnSecretaryMobile,
          controller: _secretaryMobileCtrl,
          decoration: _req('Secretary Mobile (मोबाइल)', prefixIcon: const Icon(CupertinoIcons.phone)) .copyWith(prefixText: '+91 '),
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
          validator: (v){ final s=(v??'').trim(); if(s.length!=10) return '10 digits'; return null; },
        ),
      ),
      const SizedBox(height: 8),
      _pair(
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          focusNode: _fnSubEngineerName,
          controller: _subEngineerNameCtrl,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s\-\.\u0900-\u097F]")),
            LengthLimitingTextInputFormatter(60),
          ],
          decoration: _req('Sub Engineer Name (उप-यंत्री)', prefixIcon: const Icon(CupertinoIcons.hammer)),
          validator: (v)=> (v==null||v.trim().isEmpty)?'Required':null,
        ),
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          focusNode: _fnSubEngineerMobile,
          controller: _subEngineerMobileCtrl,
          decoration: _req('Sub Engineer Mobile (मोबाइल)', prefixIcon: const Icon(CupertinoIcons.phone)) .copyWith(prefixText: '+91 '),
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
          validator: (v){ final s=(v??'').trim(); if(s.length!=10) return '10 digits'; return null; },
        ),
      ),
  ]);
  return AbsorbPointer(absorbing: !basicValid, child: Opacity(opacity: basicValid ? 1 : 0.5, child: content));
  }

  Widget _buildSanctionSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      _pair(
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          focusNode: _fnSanctionDept,
          controller: _sanctioningDepartmentCtrl,
          decoration: _req('Sanctioning Department (स्वीकृत विभाग)', prefixIcon: const Icon(CupertinoIcons.checkmark_seal)),
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s\-\.\u0900-\u097F]")),
            LengthLimitingTextInputFormatter(80),
          ],
          onChanged: (_) { _selectedSanctioningDepartmentName = _sanctioningDepartmentCtrl.text.trim(); _saveDraftLocally(); },
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter Department' : null,
        ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Scheme (योजना)', prefixIcon: Icon(CupertinoIcons.square_grid_2x2)),
          initialValue: _selectedSchemeName?.isNotEmpty == true ? _selectedSchemeName : null,
          itemHeight: 56,
          menuMaxHeight: 420,
          selectedItemBuilder: (context) => _schemeItems
              .map((e) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(e.en, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          items: _schemeItems
              .map((e) => DropdownMenuItem<String>(
                    value: e.en,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: e.en),
                        const TextSpan(text: '\n'),
                        TextSpan(text: '(${e.hi})', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                      maxLines: 2,
                      softWrap: true,
                    ),
                  ))
              .toList(),
          onChanged: (val) {
            setState(() {
              _selectedSchemeName = val;
              _schemeCtrl.text = val ?? '';
            });
            _saveDraftLocally();
          },
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Select Scheme' : null,
        ),
      ),
      const SizedBox(height: 8),
      _pair(
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          focusNode: _fnItem,
          controller: _itemCtrl,
          decoration: _req('Sanctioned Work Name - entry', prefixIcon: const Icon(CupertinoIcons.doc_text)),
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9\s\-\,/\.\u0900-\u097F]")),
            LengthLimitingTextInputFormatter(120),
          ],
          onChanged: (_) { _selectedItemName = _itemCtrl.text.trim(); _saveDraftLocally(); },
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter Work Name' : null,
        ),
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          focusNode: _fnPlanHead,
          controller: _planHeadCtrl,
          decoration: _req('Plan Head (योगना शीर्ष)', prefixIcon: const Icon(CupertinoIcons.list_bullet)),
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9\s\-\,/\.\u0900-\u097F]")),
            LengthLimitingTextInputFormatter(60),
          ],
          onChanged: (_) { _selectedPlanHeadName = _planHeadCtrl.text.trim(); _saveDraftLocally(); },
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter Plan Head' : null,
        ),
      ),
      const SizedBox(height: 8),
      _pair(
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          focusNode: _fnTechApprovalNo,
          controller: _technicalApprovalNoCtrl,
          decoration: _req('Technical Approval No. (तकनीकी स्वीकृति नंबर)', prefixIcon: const Icon(CupertinoIcons.number)),
          inputFormatters: [LengthLimitingTextInputFormatter(32)],
          keyboardType: TextInputType.text,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter Technical Approval No.' : null,
        ),
        DateFormField(
          controller: _technicalApprovalDateCtrl,
          label: 'Technical Approval Date (YYYY-MM-DD)',
          required: true,
          validator: (v){
            final s = (v ?? '').trim();
            if (s.isEmpty) return 'Required';
            final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
            if (!re.hasMatch(s)) return 'Use YYYY-MM-DD';
            try { DateTime.parse(s); } catch (_){ return 'Invalid date'; }
            return null;
          },
        ),
      ),
      const SizedBox(height: 8),
      _pair(
        TextFormField(
          textAlignVertical: TextAlignVertical.center,
          focusNode: _fnAdminApprovalNo,
          controller: _adminApprovalNoCtrl,
          decoration: _req('Admin Approval No. (प्रशासनिक स्वीकृति नंबर)', prefixIcon: const Icon(CupertinoIcons.checkmark_shield)),
          inputFormatters: [LengthLimitingTextInputFormatter(32)],
          keyboardType: TextInputType.text,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter Admin Approval No.' : null,
        ),
        DateFormField(
          controller: _adminApprovalDateCtrl,
          label: 'Admin Approval Date (YYYY-MM-DD)',
          required: true,
          validator: (v){
            final s = (v ?? '').trim();
            if (s.isEmpty) return 'Required';
            final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
            if (!re.hasMatch(s)) return 'Use YYYY-MM-DD';
            try { DateTime.parse(s); } catch (_){ return 'Invalid date'; }
            return null;
          },
        ),
      ),
  const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Technical Approval, Map & Outline Upload (तकनीकी स्वीकृति, मानचित्र और रूपरेखा अपलोड)', style: Theme.of(context).textTheme.titleSmall),
          Tooltip(
            message: 'Upload PDF (<=20MB) and/or 1–3 Photos (<=5MB each). You can attach both for technical approval.',
            child: const Icon(Icons.info_outline, size: 18),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: _pickTechApprovalDoc,
          icon: const Icon(Icons.picture_as_pdf),
          label: Text('Add PDF (<=20MB) • ${_mediaStore?.list(category: 'sanction_tech_doc').length ?? 0}'),
        ),
        FilledButton.icon(
          onPressed: _pickTechApprovalPhotos,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text('Add Photos (1–3, <=5MB) • ${_mediaStore?.list(category: 'sanction_tech_photo').length ?? 0}'),
        ),
      ]),
      const SizedBox(height: 8),
      Builder(builder: (context) {
        final items = _mediaStore?.list(category: 'sanction_tech_doc') ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((it) => _fileCard(it)).toList(),
        );
      }),
      Builder(builder: (context) {
        final items = _mediaStore?.list(category: 'sanction_tech_photo') ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((it) => _fileCard(it)).toList(),
        );
      }),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Admin Approval Documents (कम से कम 1)', style: Theme.of(context).textTheme.titleSmall),
          const Tooltip(message: 'Upload one or more PDF files (<=20MB each).', child: Icon(Icons.info_outline, size: 18)),
        ],
      ),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: _pickAdminApprovalDocs, icon: const Icon(Icons.attach_file), label: Text('Add PDF (${_mediaStore?.list(category: 'sanction_admin_doc').length ?? 0})')),
      const SizedBox(height: 8),
      Builder(builder: (context) {
        final items = _mediaStore?.list(category: 'sanction_admin_doc') ?? const [];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((it) => _fileCard(it)).toList(),
        );
      }),
    ]);
  }

  Widget _buildAllotmentSection() {
    DateTime? _parse(String s) { final t=s.trim(); if(t.isEmpty) return null; try{ return DateTime.parse(t);}catch(_){return null;} }
    String? sumErrorFor(String? _) {
      num parseNum(String s){ final t=s.trim().replaceAll(',', ''); return int.tryParse(t) ?? double.tryParse(t) ?? 0; }
      final approved = parseNum(_approvedAmountCtrl.text);
      final a1 = parseNum(_installment1AmountCtrl.text);
      final a2 = _showInstallment2 ? parseNum(_installment2AmountCtrl.text) : 0;
      final a3 = _showInstallment3 ? parseNum(_installment3AmountCtrl.text) : 0;
      if (approved <= 0) return null; // defer error to required validator
      if ((a1 + a2 + a3) > approved) {
        return 'Sum of installments exceeds Approved Amount / Total Project Cost';
      }
      return null;
    }
    return Column(children: [
      const SizedBox(height: 8),
      _singleOrEmpty(
        _amountField(
          _approvedAmountCtrl,
          'Approved Amount / Total Project Cost (स्वीकृत राशि / कुल परियोजना लागत) *',
          required: true,
          extraValidator: sumErrorFor,
        ),
      ),
      const SizedBox(height: 8),
      _pair(
        _amountField(
          _installment1AmountCtrl,
          'Installment 1 Amount *',
          required: true,
          extraValidator: sumErrorFor,
        ),
        DateFormField(
          controller: _installment1DateCtrl,
          label: 'Installment 1 Date (YYYY-MM-DD)',
          required: true,
        ),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: _installment1Status ?? 'Not Received',
        items: const ['Received','Not Received']
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        decoration: const InputDecoration(labelText: 'Installment 1 Received Status'),
        onChanged: (v) => setState(() => _installment1Status = v),
      ),
      const SizedBox(height: 8),
      if (_installment1Status == 'Received')
        _pair(
          _amountField(_installment1ReceivedAmountCtrl, 'Installment 1 Received Amount'),
          DateFormField(controller: _installment1ReceivedDateCtrl, label: 'Installment 1 Received Date (YYYY-MM-DD)'),
        )
      else Align(alignment: Alignment.centerLeft, child: Text('Skipped: ${_installment1Status ?? 'Not Received'}', style: Theme.of(context).textTheme.bodySmall)),
      const SizedBox(height: 12),
    if (!_showInstallment2)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => setState(() => _showInstallment2 = true), icon: const Icon(CupertinoIcons.plus_circle), label: const Text('Add Installment 2')),
        ),
      if (_showInstallment2) ...[
        _pair(
      _amountField(_installment2AmountCtrl, 'Installment 2 Amount', extraValidator: sumErrorFor),
          DateFormField(
            controller: _installment2DateCtrl,
            label: 'Installment 2 Date (YYYY-MM-DD)',
            firstDate: _parse(_installment1DateCtrl.text),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _installment2Status,
          items: receivedStatusOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          decoration: const InputDecoration(labelText: 'Installment 2 Received Status'),
          onChanged: (v) => setState(() => _installment2Status = v),
        ),
        const SizedBox(height: 8),
        if (_installment2Status == 'Received')
          _pair(
            _amountField(_installment2ReceivedAmountCtrl, 'Installment 2 Received Amount'),
            DateFormField(controller: _installment2ReceivedDateCtrl, label: 'Installment 2 Received Date (YYYY-MM-DD)'),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _showInstallment2 = false;
                _installment2AmountCtrl.clear();
                _installment2DateCtrl.clear();
                _installment2ReceivedAmountCtrl.clear();
                _installment2ReceivedDateCtrl.clear();
                _installment2Status = null;
              });
              _saveDraftLocally();
            },
            icon: const Icon(CupertinoIcons.minus_circle),
            label: const Text('Remove Installment 2'),
          ),
        ),
        const SizedBox(height: 12),
      ],
    if (!_showInstallment3)
        Align(
          alignment: Alignment.centerLeft,
      child: TextButton.icon(onPressed: () => setState(() { if (!_showInstallment2) _showInstallment2 = true; _showInstallment3 = true; }), icon: const Icon(CupertinoIcons.plus_circle), label: const Text('Add Installment 3')),
        ),
      if (_showInstallment3) ...[
        _pair(
      _amountField(_installment3AmountCtrl, 'Installment 3 Amount', extraValidator: sumErrorFor),
          DateFormField(
            controller: _installment3DateCtrl,
            label: 'Installment 3 Date (YYYY-MM-DD)',
            firstDate: _parse(_installment2DateCtrl.text) ?? _parse(_installment1DateCtrl.text),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _installment3Status,
          items: receivedStatusOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          decoration: const InputDecoration(labelText: 'Installment 3 Received Status'),
          onChanged: (v) => setState(() => _installment3Status = v),
        ),
        const SizedBox(height: 8),
        if (_installment3Status == 'Received')
          _pair(
            _amountField(_installment3ReceivedAmountCtrl, 'Installment 3 Received Amount'),
            DateFormField(controller: _installment3ReceivedDateCtrl, label: 'Installment 3 Received Date (YYYY-MM-DD)'),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _showInstallment3 = false;
                _installment3AmountCtrl.clear();
                _installment3DateCtrl.clear();
                _installment3ReceivedAmountCtrl.clear();
                _installment3ReceivedDateCtrl.clear();
                _installment3Status = null;
              });
              _saveDraftLocally();
            },
            icon: const Icon(CupertinoIcons.minus_circle),
            label: const Text('Remove Installment 3'),
          ),
        ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 16),
      Align(alignment: Alignment.centerLeft, child: Text('Bank Details', style: Theme.of(context).textTheme.titleSmall)),
      const SizedBox(height: 8),
      _pair(
        TextFormField(
          focusNode: _fnBankName,
          controller: _bankNameCtrl,
          decoration: _req('Bank Name', prefixIcon: const Icon(CupertinoIcons.building_2_fill)),
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s\-\.\u0900-\u097F]")),
            LengthLimitingTextInputFormatter(80),
          ],
          onChanged: (_) { _selectedBankName = _bankNameCtrl.text.trim(); _saveDraftLocally(); },
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter Bank' : null,
        ),
        TextFormField(
          focusNode: _fnAccountNumber,
          controller: _accountNumberCtrl,
          decoration: _req('Account Number', prefixIcon: const Icon(CupertinoIcons.number)),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
          validator: (v){ final s=(v??'').trim(); if(s.isEmpty) return 'Enter Account Number'; if(s.length<6) return 'Too short'; return null; },
        ),
      ),
      const SizedBox(height: 8),
      _pair(
        TextFormField(
          focusNode: _fnBranch,
          controller: _branchCtrl,
          decoration: _req('Branch', prefixIcon: const Icon(CupertinoIcons.building_2_fill)),
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9\s\-\u0900-\u097F]")),
            LengthLimitingTextInputFormatter(80),
          ],
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter Branch' : null,
        ),
        TextFormField(
          focusNode: _fnIFSC,
          controller: _ifscCtrl,
          decoration: _req('IFSC Code', prefixIcon: const Icon(CupertinoIcons.qrcode)),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(11)],
          onChanged: (_) { final t = _ifscCtrl.text.toUpperCase(); if (_ifscCtrl.text != t) { final sel = _ifscCtrl.selection; _ifscCtrl.value = TextEditingValue(text: t, selection: sel); } },
          validator: (v){ final s=(v??'').trim(); if(s.isEmpty) return 'Enter IFSC'; if(s.length!=11) return '11 characters'; return null; },
        ),
      ),
    ]);
  }

  Widget _buildWorkSection() {
    return Column(children: [
      const SizedBox(height: 8),
      _pair(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Helpers for cross-field validation
            // Parse YYYY-MM-DD into DateTime (local) or null
            // Keep lightweight and resilient to empty/invalid inputs
            
            DateFormField(
              focusNode: _fnStartDate,
              controller: _startDateCtrl,
              label: 'Work Start Date (YYYY-MM-DD)',
              lastDate: (() {
                try {
                  final s = _endDateCtrl.text.trim();
                  if (s.isEmpty) return null;
                  return DateTime.parse(s);
                } catch (_) { return null; }
              })(),
              validator: (v){
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'Required';
                final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
                if (!re.hasMatch(s)) return 'Use YYYY-MM-DD';
                DateTime d;
                try { d = DateTime.parse(s); } catch (_){ return 'Invalid date'; }
                // Cross-field: start <= end (when end provided)
                final se = _endDateCtrl.text.trim();
                if (se.isNotEmpty) {
                  try {
                    final e = DateTime.parse(se);
                    if (d.isAfter(e)) return 'Start must be on or before End';
                  } catch (_) {}
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            DateFormField(
              controller: _endDateCtrl,
              label: 'Work End Date (YYYY-MM-DD)',
              firstDate: (() {
                try {
                  final s = _startDateCtrl.text.trim();
                  if (s.isEmpty) return null;
                  return DateTime.parse(s);
                } catch (_) { return null; }
              })(),
              validator: (v){
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'Required';
                final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
                if (!re.hasMatch(s)) return 'Use YYYY-MM-DD';
                DateTime e;
                try { e = DateTime.parse(s); } catch (_){ return 'Invalid date'; }
                // Cross-field: end >= start (when start provided)
                final ss = _startDateCtrl.text.trim();
                if (ss.isNotEmpty) {
                  try {
                    final d = DateTime.parse(ss);
                    if (e.isBefore(d)) return 'End must be on or after Start';
                  } catch (_) {}
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            DateFormField(
              controller: _deadlineCtrl,
              label: 'Project Deadline (YYYY-MM-DD) – max End Date',
              lastDate: (() {
                try {
                  final s = _endDateCtrl.text.trim();
                  if (s.isEmpty) return null;
                  return DateTime.parse(s);
                } catch (_) { return null; }
              })(),
            ),
          ],
        ),
        DropdownButtonFormField<WorkStage>(
          decoration: const InputDecoration(labelText: 'Current stage', prefixIcon: Icon(CupertinoIcons.chart_bar)),
          isExpanded: true,
          initialValue: _selectedWorkStage,
          items: WorkStage.values.map((e) => DropdownMenuItem(
            value: e,
            child: Row(children: [Icon(_stageIcon(e), size: 18), const SizedBox(width: 8), Flexible(child: Text(e.name))]),
          )).toList(),
          onChanged: (v) { setState(() => _selectedWorkStage = v); _saveDraftLocally(); },
        ),
      ),
      const SizedBox(height: 8),
      // APRAM field removed per spec
      const SizedBox(height: 16),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Text('Photos (फोटो) • max 5, <=5MB each', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 6),
            const Tooltip(message: 'JPEG/PNG/HEIC up to 5MB each. You can add up to 5 photos.', child: Icon(Icons.info_outline, size: 16)),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _pickPhotos, icon: const Icon(Icons.add_a_photo), label: Text('Add (${_mediaStore?.list(category: 'work_photo').length ?? 0}/5)')),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final items = _mediaStore?.list(category: 'work_photo') ?? const [];
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((it) => _fileCard(it)).toList(),
          );
        }),
  const SizedBox(height: 16),
  Divider(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
  const SizedBox(height: 8),
  Row(children: [
    Text('Documents (optional, <=10MB each)', style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(width: 6),
    const Tooltip(message: 'PDF, Excel, or Word (<=10MB each).', child: Icon(Icons.info_outline, size: 16)),
  ]),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _pickDocs, icon: const Icon(Icons.attach_file), label: Text('Add (${_mediaStore?.list(category: 'work_doc').length ?? 0})')),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final items = _mediaStore?.list(category: 'work_doc') ?? const [];
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((it) => _fileCard(it)).toList(),
          );
        }),
  const SizedBox(height: 16),
  Divider(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
  const SizedBox(height: 8),
  // Video section removed per requirements
  const SizedBox(height: 16),
  Divider(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
  const SizedBox(height: 8),
  // External Links
  Text('External Links (optional)', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        _fieldAndButton(
          field: TextField(controller: _linkCtrl, decoration: const InputDecoration(labelText: 'https://...')),
          button: FilledButton.icon(onPressed: _addExternalLink, icon: const Icon(Icons.add_link), label: const Text('Add')),
        ),
        const SizedBox(height: 8),
        if (_externalLinks.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _externalLinks.map((u) => InputChip(
              label: Text(u, overflow: TextOverflow.ellipsis),
              onDeleted: () { setState(() { _externalLinks.remove(u); }); _saveDraftLocally(); },
            )).toList(),
          ),
        const SizedBox(height: 16),
        // Categorized documents
  Row(children: [
    Text('Measurement Books (मेज़रमेंट बुक) • optional, <=20MB each', style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(width: 6),
    const Tooltip(message: 'PDF, Excel, or Word up to 20MB.', child: Icon(Icons.info_outline, size: 16)),
  ]),
        const SizedBox(height: 8),
  FilledButton.icon(onPressed: _pickMeasurementBooks, icon: const Icon(Icons.description_outlined), label: Text('Add (${_mediaStore?.list(category: 'work_mb').length ?? 0})')),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final items = _mediaStore?.list(category: 'work_mb') ?? const [];
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((it) => _fileCard(it)).toList(),
          );
        }),
        const SizedBox(height: 16),
  Row(children: [
    Text('Test Reports (टेस्ट रिपोर्ट) • optional, <=20MB each', style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(width: 6),
    const Tooltip(message: 'PDF, Excel, or Word up to 20MB.', child: Icon(Icons.info_outline, size: 16)),
  ]),
        const SizedBox(height: 8),
  FilledButton.icon(onPressed: _pickTestReports, icon: const Icon(Icons.science_outlined), label: Text('Add (${_mediaStore?.list(category: 'work_test').length ?? 0})')),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final items = _mediaStore?.list(category: 'work_test') ?? const [];
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((it) => _fileCard(it)).toList(),
          );
        }),
        const SizedBox(height: 16),
  Row(children: [
    Text('Work Reports (कार्य रिपोर्ट) • optional, <=20MB each', style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(width: 6),
    const Tooltip(message: 'PDF, Excel, or Word up to 20MB.', child: Icon(Icons.info_outline, size: 16)),
  ]),
        const SizedBox(height: 8),
  FilledButton.icon(onPressed: _pickWorkReports, icon: const Icon(Icons.summarize_outlined), label: Text('Add (${_mediaStore?.list(category: 'work_workrep').length ?? 0})')),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final items = _mediaStore?.list(category: 'work_workrep') ?? const [];
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((it) => _fileCard(it)).toList(),
          );
        }),
        const SizedBox(height: 16),
  Row(children: [
    Text('Certificates (प्रमाण पत्र) • optional, <=20MB each', style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(width: 6),
    const Tooltip(message: 'PDF, Excel, or Word up to 20MB.', child: Icon(Icons.info_outline, size: 16)),
  ]),
        const SizedBox(height: 8),
  FilledButton.icon(onPressed: _pickCertificates, icon: const Icon(Icons.verified_outlined), label: Text('Add (${_mediaStore?.list(category: 'work_cert').length ?? 0})')),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final items = _mediaStore?.list(category: 'work_cert') ?? const [];
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((it) => _fileCard(it)).toList(),
          );
        }),
      ]),
    ]);
  }

  Widget _buildBasicDetailsSection() {
  final gpAsync = ref.watch(gpdata.gramPanchayatDataProvider);
  final gpItems = gpAsync.maybeWhen(data: (v) => v, orElse: () => const <gpdata.GPRecord>[]);
  final gpLoading = gpAsync.isLoading;
  final gpError = gpAsync.hasError;
    final gpNames = gpItems.map((e) => e.name).toList();
    final selectedGP = gpItems.where((e) => e.name == _selectedGramPanchayatName).cast<gpdata.GPRecord?>().firstWhere((e) => true, orElse: () => null);
    final villageOptions = (selectedGP?.grams ?? const <String>[]);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Basic Details (मूल विवरण)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            _pair(
              TextFormField(
                focusNode: _fnName,
                controller: _nameCtrl,
                decoration: _req('Project Name (परियोजना नाम)', prefixIcon: const Icon(CupertinoIcons.briefcase)),
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9\s\-\,/\.\u0900-\u097F]")),
                  LengthLimitingTextInputFormatter(80),
                ],
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.length < 3) return 'Enter at least 3 characters';
                  return null;
                },
              ),
              TextFormField(
                focusNode: _fnAddress,
                controller: _addressCtrl,
                decoration: _req('Address (पता)', prefixIcon: const Icon(CupertinoIcons.placemark)),
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9\s\-\,/\.#\u0900-\u097F]")),
                  LengthLimitingTextInputFormatter(200),
                ],
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return 'Required';
                  return null;
                },
              ),
            ),
            const SizedBox(height: 12),
            _pair(
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: _req('Block (ब्लॉक)', prefixIcon: const Icon(CupertinoIcons.building_2_fill)),
                initialValue: _selectedBlockId,
                items: _staticBlocks.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedBlockId = val;
                    _selectedBlockName = val;
                    // Reset dependent selections when block changes
                    _selectedGramPanchayatName = null;
                    _gramPanchayatCtrl.clear();
                    _selectedVillageName = null;
                    _villageCtrl.clear();
                    _sarpanchNameCtrl.clear();
                    _secretaryNameCtrl.clear();
                  });
                  _saveDraftLocally();
                },
                validator: (v) => (v == null || v.isEmpty) ? 'Select Block' : null,
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: _req('Gram Panchayat (ग्राम पंचायत)', prefixIcon: const Icon(CupertinoIcons.building_2_fill)),
                value: (_selectedGramPanchayatName?.isNotEmpty ?? false) ? _selectedGramPanchayatName : null,
                items: gpNames.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (_selectedBlockId == null || gpLoading || gpItems.isEmpty)
                    ? null
                    : (val) {
                        setState(() {
                          _selectedGramPanchayatName = val;
                          _gramPanchayatCtrl.text = val ?? '';
                          // Auto-fill officials
                          final rec = gpItems.firstWhere((e) => e.name == val, orElse: () => gpdata.GPRecord(name: '', grams: const [], sarpanch: '', secretary: ''));
                          _sarpanchNameCtrl.text = rec.sarpanch;
                          _secretaryNameCtrl.text = rec.secretary;
                          // Reset village
                          _selectedVillageName = null;
                          _villageCtrl.clear();
                          if (rec.grams.length == 1) {
                            _selectedVillageName = rec.grams.first;
                            _villageCtrl.text = rec.grams.first;
                          }
                        });
                        _saveDraftLocally();
                      },
                validator: (v) => (v == null || v.isEmpty) ? 'Select Gram Panchayat' : null,
              ),
            ),
            if (gpLoading)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Row(
                  children: const [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Loading local Gram Panchayat list…'),
                  ],
                ),
              ),
            if (gpError)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  'Couldn\'t load local dataset (local_data.json). Please refresh or contact admin.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!gpLoading && !gpError && gpItems.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  'Local Gram Panchayat list is empty. Please ensure local_data.json is bundled.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                ),
              ),
            const SizedBox(height: 12),
            _singleOrEmpty(
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: _req('Village / Gram (ग्राम)', prefixIcon: const Icon(CupertinoIcons.home)),
                value: (_selectedVillageName?.isNotEmpty ?? false) ? _selectedVillageName : null,
                items: villageOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedVillageName = v;
                    _villageCtrl.text = v ?? '';
                  });
                  _saveDraftLocally();
                },
                validator: (v) => (v == null || v.isEmpty) ? 'Select Village' : null,
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _locating ? null : _getLocation,
                          icon: const Icon(CupertinoIcons.location),
                          label: Text(_locating ? 'Locating...' : 'Use current location (वर्तमान स्थान)', textAlign: TextAlign.center,),
                        ),
                        if (_lat != null && _lng != null)
                          Text('Lat: ${_lat!.toStringAsFixed(5)}  Lng: ${_lng!.toStringAsFixed(5)}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    RepaintBoundary(
                      key: _mapKey,
                      child: SizedBox(
                        height: 220,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              // Default to Dhamtari, Chhattisgarh when no GPS available
                              initialCenter: LatLng(_lat ?? 20.7072, _lng ?? 81.5480),
                              initialZoom: (_lat != null && _lng != null) ? 15 : 12,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                                subdomains: const ['a','b','c','d'],
                                userAgentPackageName: 'com.example.nirmadapp',
                              ),
                              if (_lat != null && _lng != null)
                                MarkerLayer(markers: [
                                  Marker(
                                    point: LatLng(_lat!, _lng!),
                                    width: 40,
                                    height: 40,
                                    alignment: Alignment.center,
                                    child: const Icon(CupertinoIcons.location_solid, color: Colors.redAccent, size: 36),
                                  )
                                ]),
                              if (!kIsWeb) const CurrentLocationLayer(),
                              RichAttributionWidget(
                                alignment: AttributionAlignment.bottomRight,
                                attributions: const [
                                  TextSourceAttribution('© OpenStreetMap contributors'),
                                  TextSourceAttribution('© CARTO'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Tip: Move the map and press the GPS button to capture accurate coordinates.', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic form completion percentage (4 new sections)
  bool prelimDone = _sarpanchNameCtrl.text.trim().isNotEmpty && _secretaryNameCtrl.text.trim().isNotEmpty;
  bool sanctionDone = _sanctioningDepartmentCtrl.text.trim().isNotEmpty && (_selectedSchemeName?.isNotEmpty == true || _schemeCtrl.text.trim().isNotEmpty);
  bool allotmentDone = _installment1AmountCtrl.text.trim().isNotEmpty && _bankNameCtrl.text.trim().isNotEmpty;
  bool workDone = _nameCtrl.text.trim().isNotEmpty && _addressCtrl.text.trim().isNotEmpty && _lat != null && _lng != null && _startDateCtrl.text.trim().isNotEmpty && _endDateCtrl.text.trim().isNotEmpty;
  int stepsCompleted = [prelimDone, sanctionDone, allotmentDone, workDone].where((e) => e).length;
    final pct = (stepsCompleted / 4).clamp(0, 1).toDouble();
    return Scaffold(
      body: SingleChildScrollView(
        padding: R.pagePadding(context),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: R.maxContentWidth(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 220,
                        child: Row(children: [
                          Expanded(child: LinearProgressIndicator(value: pct, minHeight: 6, borderRadius: BorderRadius.circular(6))),
                          const SizedBox(width: 8),
                          Text('${(pct * 100).toStringAsFixed(0)}%', style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (_didRestoreDraft || (_drafts?.hasDraft() ?? false))
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(CupertinoIcons.pencil, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Draft available. Changes autosave locally.')),
                          if (_showAutosaved)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Row(children: [
                                const Icon(CupertinoIcons.check_mark_circled_solid, size: 16, color: Colors.green),
                                const SizedBox(width: 4),
                                Text('Autosaved', style: TextStyle(color: Colors.green, fontSize: 12)),
                              ]),
                            ),
                          TextButton.icon(
                            onPressed: () async {
                              // messenger removed; using toastification for user feedback
                              await _clearDraftLocally();
                              if (!mounted) return;
                              setState(() { _didRestoreDraft = false; });
                              toastification.show(
                                context: context,
                                title: const Text('Draft cleared', textAlign: TextAlign.center,),
                                type: ToastificationType.success,
                                style: ToastificationStyle.fillColored,
                                autoCloseDuration: const Duration(seconds: 2),
                                showProgressBar: false,
                                icon: const Icon(CupertinoIcons.delete_solid),
                              );
                            },
                            icon: const Icon(CupertinoIcons.delete),
                            label: const Text('Clear draft', textAlign: TextAlign.center,),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                // Disable form while saving/uploads in progress
                AbsorbPointer(
                  absorbing: _saving,
                  child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBasicDetailsSection(),
                      const SizedBox(height: 12),
                      PageTransitionSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
                          animation: primary,
                          secondaryAnimation: secondary,
                          child: child,
                        ),
                        child: KeyedSubtree(
                          key: ValueKey('stepper_$_currentStep'),
                          child: Stepper(
                    type: StepperType.vertical,
                    currentStep: _currentStep,
                    onStepTapped: (i) {
                      int highest = 0;
                      if (prelimDone) highest = 1;
                      if (prelimDone && sanctionDone) highest = 2;
                      if (prelimDone && sanctionDone && allotmentDone) highest = 3;
                      if (i <= highest) {
                        setState(() => _currentStep = i);
                        _saveDraftLocally();
                        // Move focus to first field in this section
                        WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirstFieldInStep(i));
                      } else {
                        toastification.show(
                          context: context,
                          title: const Text('Complete previous section first'),
                          type: ToastificationType.info,
                          style: ToastificationStyle.fillColored,
                          autoCloseDuration: const Duration(seconds: 2),
                          showProgressBar: false,
                          icon: const Icon(CupertinoIcons.info),
                        );
                      }
                    },
                        controlsBuilder: (context, details) {
                      bool currentStepValid() {
                        // Run a focused validation for the current step's key fields
                        switch (_currentStep) {
                          case 0:
          return (_gramPanchayatCtrl.text.trim().isNotEmpty &&
            (_selectedVillageName?.trim().isNotEmpty ?? false) &&
            _sarpanchNameCtrl.text.trim().isNotEmpty &&
            _sarpanchMobileCtrl.text.trim().length == 10 &&
            _secretaryNameCtrl.text.trim().isNotEmpty &&
            _secretaryMobileCtrl.text.trim().length == 10 &&
            _subEngineerNameCtrl.text.trim().isNotEmpty &&
            _subEngineerMobileCtrl.text.trim().length == 10);
                          case 1:
          return (_sanctioningDepartmentCtrl.text.trim().isNotEmpty &&
            (((_selectedSchemeName?.isNotEmpty) ?? false) || _schemeCtrl.text.trim().isNotEmpty) &&
                                    _itemCtrl.text.trim().isNotEmpty &&
                                    _planHeadCtrl.text.trim().isNotEmpty &&
                                    _technicalApprovalNoCtrl.text.trim().isNotEmpty &&
                                    _technicalApprovalDateCtrl.text.trim().isNotEmpty &&
                                    _adminApprovalNoCtrl.text.trim().isNotEmpty &&
                                    _adminApprovalDateCtrl.text.trim().isNotEmpty &&
                                    _approvedAmountCtrl.text.trim().isNotEmpty);
                          case 2:
                            return (_bankNameCtrl.text.trim().isNotEmpty &&
                                    _accountNumberCtrl.text.trim().length >= 6 &&
                                    _branchCtrl.text.trim().isNotEmpty &&
                                    _ifscCtrl.text.trim().length == 11);
                          case 3:
                            return (_nameCtrl.text.trim().isNotEmpty &&
                                    _addressCtrl.text.trim().isNotEmpty &&
                                    _lat != null && _lng != null &&
                                    _startDateCtrl.text.trim().isNotEmpty &&
                                    _endDateCtrl.text.trim().isNotEmpty);
                          default:
                            return true;
                        }
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            FilledButton(
                              onPressed: currentStepValid()
                                  ? () {
                                      // Only step-level validation to advance; don't validate entire form here
                                      if (_currentStep < 3) {
                                        setState(() => _currentStep++);
                                        _saveDraftLocally();
                                        final next = _currentStep;
                                        // Focus the first field in the next section
                                        WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirstFieldInStep(next));
                                      }
                                    }
                                  : null,
                              child: Text(_currentStep < 3 ? 'Next' : 'Done'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                if (_currentStep > 0) { setState(() => _currentStep--); _saveDraftLocally(); }
                              },
                              child: const Text('Back'),
                            ),
                          ],
                        ),
                      );
                    },
                    steps: [
                      Step(
                        title: const Text('Preliminary Description (प्रारंभिक विवरण)'),
                        isActive: _currentStep >= 0,
                        state: prelimDone ? StepState.complete : StepState.indexed,
                        content: _buildPreliminarySection(),
                      ),
                      Step(
                        title: const Text('Sanction & Compliance (स्वीकृति और अनुपालन)'),
                        isActive: _currentStep >= 1,
                        state: sanctionDone ? StepState.complete : StepState.indexed,
                        content: _buildSanctionSection(),
                      ),
                      Step(
                        title: const Text('Allotment Details (वितरण विवरण)'),
                        isActive: _currentStep >= 2,
                        state: allotmentDone ? StepState.complete : StepState.indexed,
                        content: _buildAllotmentSection(),
                      ),
                      Step(
                        title: const Text('Work Description (कार्य विवरण)'),
                        isActive: _currentStep >= 3,
                        state: workDone ? StepState.complete : StepState.indexed,
                        content: _buildWorkSection(),
                      ),
                    ],
                    onStepContinue: () {
                      // Stepper host: we just scroll; save handled below
                      // No internal state index maintained as Stepper shows all steps vertically
                    },
                    onStepCancel: () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
                const SizedBox(height: 12),
                // helper to auto-focus first invalid field within current step
                // considers only a subset of fields based on our validators
                // works on Android and Web
              
                PageTransitionSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (child, a, sa) => FadeThroughTransition(animation: a, secondaryAnimation: sa, child: child),
                  child: (_saving && _totalUploads > 0)
                      ? Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Uploading...', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: ((_completedUploads + _currentFileProgress) / _totalUploads).clamp(0.0, 1.0)),
                          const SizedBox(height: 8),
                          Text('${_currentLabel.isEmpty ? 'Preparing' : _currentLabel} • ${(_currentFileProgress * 100).toStringAsFixed(0)}% • $_completedUploads/$_totalUploads completed', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ) : const SizedBox.shrink(),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(builder: (context, c) {
                  final narrow = c.maxWidth < 360;
                  // Precompute simple validity to enable/disable Create button
                  final techDocCnt = _mediaStore?.list(category: 'sanction_tech_doc').length ?? 0;
                  final techPhotoCnt = _mediaStore?.list(category: 'sanction_tech_photo').length ?? 0;
                  final adminDocCnt = _mediaStore?.list(category: 'sanction_admin_doc').length ?? 0;
                  final techOk = techDocCnt > 0 || (techPhotoCnt > 0 && techPhotoCnt <= 3);
                  final requiredCtrls = <TextEditingController>[
                    _gramPanchayatCtrl,
                    _sarpanchNameCtrl,
                    _secretaryNameCtrl,
                    _subEngineerNameCtrl,
                    _sanctioningDepartmentCtrl,
                    _itemCtrl,
                    _planHeadCtrl,
                    _technicalApprovalNoCtrl,
                    _technicalApprovalDateCtrl,
                    _adminApprovalNoCtrl,
                    _adminApprovalDateCtrl,
                    _approvedAmountCtrl,
                    _startDateCtrl,
                    _endDateCtrl,
                  ];
                  final textsOk = requiredCtrls.every((c) => c.text.trim().isNotEmpty);
                  final mobilesOk = _sarpanchMobileCtrl.text.trim().length == 10 &&
                      _secretaryMobileCtrl.text.trim().length == 10 &&
                      _subEngineerMobileCtrl.text.trim().length == 10;
                  final blockOk = (_selectedBlockId ?? '').isNotEmpty;
                  final gpOk = _gramPanchayatCtrl.text.trim().isNotEmpty;
                  final villageOk = (_selectedVillageName?.isNotEmpty ?? false);
                  final gpsOk = _lat != null && _lng != null;
                  final adminOk = adminDocCnt > 0;
                  final canCreate = textsOk && mobilesOk && blockOk && gpOk && villageOk && gpsOk && techOk && adminOk && !_saving;
                  Future<T?> _showScrollSafeDialog<T>(Widget Function(BuildContext) builder) => showScrollSafeDialog<T>(context: context, builder: builder);

                  final resetBtn = OutlinedButton.icon(
                    onPressed: _saving ? null : () async {
                        final confirmed = await _showScrollSafeDialog<bool>((ctx) => Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Reset form?', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 12),
                            const Text('This will clear all fields and the saved local draft.'),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                const SizedBox(width: 8),
                                FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reset')),
                              ],
                            )
                          ],
                        ));
                        if (confirmed == true) {
                          await _resetForm();
                          if (mounted) {
                            toastification.show(
                              context: context,
                              title: const Text('Form reset'),
                              type: ToastificationType.success,
                              style: ToastificationStyle.fillColored,
                              autoCloseDuration: const Duration(seconds: 2),
                              showProgressBar: false,
                              icon: const Icon(CupertinoIcons.refresh),
                            );
                          }
                        }
                      },
                    icon: const Icon(CupertinoIcons.refresh),
                    label: const Text('Reset form'),
                  );
                  Future<bool> _confirmCreateDisclaimer() async {
                    final auth = await ref.read(authRepositoryProvider).currentUser();
                    if (auth == null) return false;
                    if (auth.role == UserRole.devAdmin) return true;
                    final ok = await _showScrollSafeDialog<bool>((ctx) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Confirm and proceed', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        const Text(
                          'I confirm the project details are accurate to the best of my knowledge.\n\n'
                          'Submitting false or misleading data may lead to rejection or action.\n\n'
                          'This creates a new project and an audit trail will be recorded.',
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                            const SizedBox(width: 8),
                            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('I understand')),
                          ],
                        )
                      ],
                    ));
                    return ok == true;
                  }
                  final saveBtn = FilledButton.icon(
                    onPressed: canCreate
                        ? () async {
                              // Non-admin confirmation disclaimer
                              final ok = await _confirmCreateDisclaimer();
                              if (!ok) return;
                              // Using toastification for feedback
                              // Optional safety
                              if (!mounted) return;
                              if (!_formKey.currentState!.validate()) return;
                              // Allotment validation rules
                              num _numParse(String s){ final t=s.trim().replaceAll(',', ''); return int.tryParse(t) ?? double.tryParse(t) ?? 0; }
                              DateTime? _date(String s){ final t=s.trim(); if(t.isEmpty) return null; try{return DateTime.parse(t);}catch(_){return null;} }
                              final approved = _numParse(_approvedAmountCtrl.text);
                              final a1 = _numParse(_installment1AmountCtrl.text);
                              final a2 = _showInstallment2 ? _numParse(_installment2AmountCtrl.text) : 0;
                              final a3 = _showInstallment3 ? _numParse(_installment3AmountCtrl.text) : 0;
                              if (a1 <= 0) {
                                toastification.show(context: context, title: const Text('Enter Installment 1 amount'), type: ToastificationType.warning, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 3), showProgressBar: false, icon: const Icon(CupertinoIcons.exclamationmark_triangle));
                                return;
                              }
                              if (approved > 0 && (a1 + a2 + a3) > approved) {
                                toastification.show(context: context, title: const Text('Installments exceed Approved Amount'), description: const Text('Sum must be ≤ Approved Amount'), type: ToastificationType.warning, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 4), showProgressBar: false, icon: const Icon(CupertinoIcons.exclamationmark_triangle));
                                return;
                              }
                              final d1 = _date(_installment1DateCtrl.text);
                              final d2 = _date(_installment2DateCtrl.text);
                              final d3 = _date(_installment3DateCtrl.text);
                              if (d1 == null) {
                                toastification.show(context: context, title: const Text('Enter Installment 1 date'), type: ToastificationType.warning, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 3), showProgressBar: false, icon: const Icon(CupertinoIcons.exclamationmark_triangle));
                                return;
                              }
                              if (d2 != null && d2.isBefore(d1)) {
                                toastification.show(context: context, title: const Text('I2 date must be on/after I1'), type: ToastificationType.warning, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 4), showProgressBar: false, icon: const Icon(CupertinoIcons.exclamationmark_triangle));
                                return;
                              }
                              if (d3 != null) {
                                if (d2 == null) {
                                  toastification.show(context: context, title: const Text('Enter I2 before I3'), type: ToastificationType.info, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 3), showProgressBar: false, icon: const Icon(CupertinoIcons.info));
                                  return;
                                }
                                if (d3.isBefore(d2)) {
                                  toastification.show(context: context, title: const Text('I3 date must be on/after I2'), type: ToastificationType.warning, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 4), showProgressBar: false, icon: const Icon(CupertinoIcons.exclamationmark_triangle));
                                  return;
                                }
                              }
                              // Received gating
                              if ((_installment1Status ?? 'Not Received') == 'Received') {
                                final rAmt = _numParse(_installment1ReceivedAmountCtrl.text);
                                final rDate = _date(_installment1ReceivedDateCtrl.text);
                                if (rAmt <= 0 || rDate == null) {
                                  toastification.show(context: context, title: const Text('Fill I1 received amount and date'), type: ToastificationType.warning, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 4), showProgressBar: false, icon: const Icon(CupertinoIcons.exclamationmark_triangle));
                                  return;
                                }
                                if (a1 > 0 && rAmt > a1) {
                                  toastification.show(context: context, title: const Text('I1 received > planned'), type: ToastificationType.info, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 3), showProgressBar: false, icon: const Icon(CupertinoIcons.info));
                                  return;
                                }
                              }
                              if (_showInstallment2 && _installment2Status == 'Received') {
                                final rAmt = _numParse(_installment2ReceivedAmountCtrl.text);
                                final rDate = _date(_installment2ReceivedDateCtrl.text);
                                if (rAmt <= 0 || rDate == null) {
                                  toastification.show(context: context, title: const Text('Fill I2 received amount and date'), type: ToastificationType.warning, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 4), showProgressBar: false, icon: const Icon(CupertinoIcons.exclamationmark_triangle));
                                  return;
                                }
                                if (a2 > 0 && rAmt > a2) {
                                  toastification.show(context: context, title: const Text('I2 received > planned'), type: ToastificationType.info, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 3), showProgressBar: false, icon: const Icon(CupertinoIcons.info));
                                  return;
                                }
                              }
                              if (_showInstallment3 && _installment3Status == 'Received') {
                                final rAmt = _numParse(_installment3ReceivedAmountCtrl.text);
                                final rDate = _date(_installment3ReceivedDateCtrl.text);
                                if (rAmt <= 0 || rDate == null) {
                                  toastification.show(context: context, title: const Text('Fill I3 received amount and date'), type: ToastificationType.warning, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 4), showProgressBar: false, icon: const Icon(CupertinoIcons.exclamationmark_triangle));
                                  return;
                                }
                                if (a3 > 0 && rAmt > a3) {
                                  toastification.show(context: context, title: const Text('I3 received > planned'), type: ToastificationType.info, style: ToastificationStyle.fillColored, autoCloseDuration: const Duration(seconds: 3), showProgressBar: false, icon: const Icon(CupertinoIcons.info));
                                  return;
                                }
                              }
                              // Removed mandatory photo requirement to align with new stepper
                              if (_lat == null || _lng == null) {
                                toastification.show(
                                  context: context,
                                  title: const Text('Please capture GPS location'),
                                  type: ToastificationType.info,
                                  style: ToastificationStyle.fillColored,
                                  autoCloseDuration: const Duration(seconds: 3),
                                  showProgressBar: false,
                                  icon: const Icon(CupertinoIcons.location),
                                );
                                return;
                              }
                              if ((_selectedBlockId ?? '').isEmpty) {
                                toastification.show(
                                  context: context,
                                  title: const Text('Please select Block'),
                                  type: ToastificationType.info,
                                  style: ToastificationStyle.fillColored,
                                  autoCloseDuration: const Duration(seconds: 3),
                                  showProgressBar: false,
                                  icon: const Icon(CupertinoIcons.placemark),
                                );
                                return;
                              }
                if ((_selectedVillageName?.isNotEmpty ?? false) == false) {
                                toastification.show(
                                  context: context,
                  title: const Text('Please select Village / Gram'),
                                  type: ToastificationType.info,
                                  style: ToastificationStyle.fillColored,
                                  autoCloseDuration: const Duration(seconds: 3),
                                  showProgressBar: false,
                                  icon: const Icon(CupertinoIcons.home),
                                );
                                return;
                              }
                              // Sanction gate: must have either tech doc or 1-3 photos, and >=1 admin doc (from offline store)
                              final techDocCnt = _mediaStore?.list(category: 'sanction_tech_doc').length ?? 0;
                              final techPhotoCnt = _mediaStore?.list(category: 'sanction_tech_photo').length ?? 0;
                              final adminDocCnt = _mediaStore?.list(category: 'sanction_admin_doc').length ?? 0;
                              final techOk = techDocCnt > 0 || (techPhotoCnt > 0 && techPhotoCnt <= 3);
                              if (!techOk) {
                                toastification.show(
                                  context: context,
                                  title: const Text('Add technical approval'),
                                  description: const Text('Upload 1 doc or 1–3 photos'),
                                  type: ToastificationType.warning,
                                  style: ToastificationStyle.fillColored,
                                  autoCloseDuration: const Duration(seconds: 3),
                                  showProgressBar: false,
                                  icon: const Icon(CupertinoIcons.doc_plaintext),
                                );
                                return;
                              }
                              if (adminDocCnt == 0) {
                                toastification.show(
                                  context: context,
                                  title: const Text('Admin approval required'),
                                  description: const Text('Add at least one document'),
                                  type: ToastificationType.warning,
                                  style: ToastificationStyle.fillColored,
                                  autoCloseDuration: const Duration(seconds: 3),
                                  showProgressBar: false,
                                  icon: const Icon(CupertinoIcons.paperclip),
                                );
                                return;
                              }
                              // If marking stage as completed, require at least one certificate
                              final certCnt = _mediaStore?.list(category: 'work_cert').length ?? 0;
                              if (_selectedWorkStage == WorkStage.completed && certCnt == 0) {
                                toastification.show(
                                  context: context,
                                  title: const Text('Completion certificate needed'),
                                  type: ToastificationType.info,
                                  style: ToastificationStyle.fillColored,
                                  autoCloseDuration: const Duration(seconds: 3),
                                  showProgressBar: false,
                                  icon: const Icon(CupertinoIcons.checkmark_seal),
                                );
                                return;
                              }
                              // Final confirmation before creating (irreversible)
                              final confirm = await _showScrollSafeDialog<bool>((ctx) {
                                final cs = Theme.of(ctx).colorScheme;
                                final workPhotoCnt = _mediaStore?.list(category: 'work_photo').length ?? 0;
                                final workDocCnt = _mediaStore?.list(category: 'work_doc').length ?? 0;
                                final certCnt2 = _mediaStore?.list(category: 'work_cert').length ?? 0;
                                final techDocCnt2 = _mediaStore?.list(category: 'sanction_tech_doc').length ?? 0;
                                final techPhotoCnt2 = _mediaStore?.list(category: 'sanction_tech_photo').length ?? 0;
                                final adminDocCnt2 = _mediaStore?.list(category: 'sanction_admin_doc').length ?? 0;
                                final techOk2 = techDocCnt2 > 0 || (techPhotoCnt2 > 0 && techPhotoCnt2 <= 3);
                                Widget bullet(String label, String value, {bool ok = true}) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(ok ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.xmark_octagon_fill, size: 16, color: ok ? cs.primary : cs.error),
                                      const SizedBox(width: 6),
                                      Expanded(child: RichText(text: TextSpan(style: Theme.of(ctx).textTheme.bodySmall, children: [
                                        TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                                        TextSpan(text: value),
                                      ]))),
                                    ],
                                  ),
                                );
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Create project?', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 12),
                                    Text('Review & confirm. After creation, editing requires proper permissions.', style: Theme.of(ctx).textTheme.bodySmall),
                                    const SizedBox(height: 12),
                                    Text('Section Summary', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    bullet('Preliminary', prelimDone ? 'Complete' : 'Incomplete', ok: prelimDone),
                                    bullet('Sanction & Compliance', sanctionDone ? 'Complete' : 'Incomplete', ok: sanctionDone),
                                    bullet('Allotment Details', allotmentDone ? 'Complete' : 'Incomplete', ok: allotmentDone),
                                    bullet('Work Description', workDone ? 'Complete' : 'Incomplete', ok: workDone),
                                    const SizedBox(height: 12),
                                    Text('Gating Checks', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    bullet('Technical Approval', techOk2 ? (techDocCnt2 > 0 ? '$techDocCnt2 doc(s)' : '$techPhotoCnt2 photo(s)') : 'Missing', ok: techOk2),
                                    bullet('Admin Approval Docs', adminDocCnt2 > 0 ? '$adminDocCnt2 doc(s)' : 'Missing', ok: adminDocCnt2 > 0),
                                    bullet('GPS Location', (_lat != null && _lng != null) ? 'Captured' : 'Missing', ok: _lat != null && _lng != null),
                                    bullet('Certificates (if completed)', _selectedWorkStage == WorkStage.completed ? (certCnt2 > 0 ? '$certCnt2 doc(s)' : 'Missing') : 'Not required', ok: _selectedWorkStage != WorkStage.completed || certCnt2 > 0),
                                    const SizedBox(height: 12),
                                    Text('Media Overview', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    Text('Work Photos: $workPhotoCnt • Work Docs: $workDocCnt • Certificates: $certCnt2', style: Theme.of(ctx).textTheme.bodySmall),
                                    if (_startDateCtrl.text.trim().isNotEmpty || _endDateCtrl.text.trim().isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Text('Schedule', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      if (_startDateCtrl.text.trim().isNotEmpty) Text('Start: ${_startDateCtrl.text.trim()}', style: Theme.of(ctx).textTheme.bodySmall),
                                      if (_endDateCtrl.text.trim().isNotEmpty) Text('End: ${_endDateCtrl.text.trim()}', style: Theme.of(ctx).textTheme.bodySmall),
                                      if (_deadlineCtrl.text.trim().isNotEmpty) Text('Deadline: ${_deadlineCtrl.text.trim()}', style: Theme.of(ctx).textTheme.bodySmall),
                                    ],
                                    const SizedBox(height: 18),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: cs.errorContainer.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 18, color: cs.error),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text('Submitting creates an immutable project record. Ensure accuracy before proceeding.', style: Theme.of(ctx).textTheme.bodySmall)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                        const SizedBox(width: 8),
                                        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create Project')),
                                      ],
                                    )
                                  ],
                                );
                              });
                              if (confirm != true) return;
                              // Save a lightweight draft now (after dialog) before heavy operations
                              await _saveDraftLocally();
                              if (!mounted) return;
                              setState(() {
                                _saving = true;
                                _totalUploads = 0;
                                _completedUploads = 0;
                                _currentFileProgress = 0.0;
                                _currentLabel = '';
                                _lastUploadError = null;
                              });
                              try {
                                final auth = await ref.read(authRepositoryProvider).currentUser();
                                if (auth == null) throw Exception('Not signed in');
                                final repo = ref.read(projectRepositoryProvider);
                                final storage = ref.read(storageServiceProvider);
                                final now = DateTime.now();
                                // simple retry helper for uploads
            Future<String?> uploadWithRetry(String label, Future<String> Function() action) async {
                                  const attempts = 3;
                                  final delays = <Duration>[const Duration(milliseconds: 300), const Duration(milliseconds: 700), const Duration(milliseconds: 1200)];
                                  for (int i = 0; i < attempts; i++) {
                                    try {
                                      return await action();
                                    } catch (e) {
                                      _lastUploadError = e.toString();
                                      // last attempt failed, give up
                                      if (i == attempts - 1) {
                                        debugPrint('Upload failed for $label after $attempts attempts: $e');
                                        return null;
                                      }
                                      await Future.delayed(delays[i]);
                                    }
                                  }
                                  return null;
                                }
                                // Helpers
                                DateTime? parseDate(String s) { final t = s.trim(); if (t.isEmpty) return null; try { return DateTime.parse(t); } catch (_) { return null; } }
                                num? parseNum(String s) {
                                  const maxRupees = 500000000; // 50 crores
                                  final t = s.trim().replaceAll(',', '');
                                  final v = int.tryParse(t) ?? double.tryParse(t);
                                  if (v == null) return null;
                                  if (v > maxRupees) return maxRupees;
                                  if (v < 0) return 0;
                                  return v;
                                }
                                // draft
                                // capture finance inputs
                                final budgetStr = _budgetCtrl.text.trim().replaceAll(',', '');
                                final num? budgetNum = int.tryParse(budgetStr) ?? double.tryParse(budgetStr);
                                final labourStr = _labourCtrl.text.trim();
                                final int? labourNum = labourStr.isEmpty ? null : int.tryParse(labourStr);
                                final etaStr = _etaCtrl.text.trim();
                                final finance = <String, dynamic>{
                                  if (budgetNum != null) 'budget': budgetNum,
                                  if (_fundingCtrl.text.trim().isNotEmpty) 'fundingSource': _fundingCtrl.text.trim(),
                                  'contractor': {
                                    if (_contractorNameCtrl.text.trim().isNotEmpty) 'name': _contractorNameCtrl.text.trim(),
                                    if (_contractorContactCtrl.text.trim().isNotEmpty) 'contact': _contractorContactCtrl.text.trim(),
                                  },
                                  if (labourNum != null) 'labourCount': labourNum,
                                  if (etaStr.isNotEmpty) 'eta': etaStr,
                                  if (_deadlineCtrl.text.trim().isNotEmpty) 'deadline': parseDate(_deadlineCtrl.text),
                                  if (_externalLinks.isNotEmpty) 'externalLinks': List.of(_externalLinks),
                                };
                                final prelim = PreliminaryDescription(
                                  sarpanchName: _sarpanchNameCtrl.text.trim().isEmpty ? null : _sarpanchNameCtrl.text.trim(),
                                  sarpanchMobile: _sarpanchMobileCtrl.text.trim().isEmpty ? null : _sarpanchMobileCtrl.text.trim(),
                                  gramPanchayat: (_selectedGramPanchayatName ?? _gramPanchayatCtrl.text.trim()).isEmpty ? null : (_selectedGramPanchayatName ?? _gramPanchayatCtrl.text.trim()),
                                  secretaryName: _secretaryNameCtrl.text.trim().isEmpty ? null : _secretaryNameCtrl.text.trim(),
                                  secretaryMobile: _secretaryMobileCtrl.text.trim().isEmpty ? null : _secretaryMobileCtrl.text.trim(),
                                  subEngineerName: _subEngineerNameCtrl.text.trim().isEmpty ? null : _subEngineerNameCtrl.text.trim(),
                                  subEngineerMobile: _subEngineerMobileCtrl.text.trim().isEmpty ? null : _subEngineerMobileCtrl.text.trim(),
                                );
                                final sanction = SanctionCompliance(
                                  sanctioningDepartmentId: null,
                                  sanctioningDepartmentName: _selectedSanctioningDepartmentName ?? _sanctioningDepartmentCtrl.text.trim(),
                                  technicalApprovalNo: _technicalApprovalNoCtrl.text.trim().isEmpty ? null : _technicalApprovalNoCtrl.text.trim(),
                                  technicalApprovalDate: parseDate(_technicalApprovalDateCtrl.text),
                                  adminApprovalNo: _adminApprovalNoCtrl.text.trim().isEmpty ? null : _adminApprovalNoCtrl.text.trim(),
                                  adminApprovalDate: parseDate(_adminApprovalDateCtrl.text),
                                  schemeId: null,
                                  schemeName: _selectedSchemeName ?? _schemeCtrl.text.trim(),
                                  itemId: null,
                                  itemName: _selectedItemName ?? _itemCtrl.text.trim(),
                                  planHeadId: null,
                                  planHeadName: _selectedPlanHeadName ?? _planHeadCtrl.text.trim(),
                                  approvedAmount: parseNum(_approvedAmountCtrl.text),
                                  approvalDocumentUrls: const [],
                                );
                                final i1 = Installment(
                                  amount: parseNum(_installment1AmountCtrl.text),
                                  date: parseDate(_installment1DateCtrl.text),
                                  receivedAmount: parseNum(_installment1ReceivedAmountCtrl.text),
                                  receivedDate: parseDate(_installment1ReceivedDateCtrl.text),
                                );
                                final i2 = Installment(
                                  amount: parseNum(_installment2AmountCtrl.text),
                                  date: parseDate(_installment2DateCtrl.text),
                                  receivedAmount: parseNum(_installment2ReceivedAmountCtrl.text),
                                  receivedDate: parseDate(_installment2ReceivedDateCtrl.text),
                                );
                                final i3 = Installment(
                                  amount: parseNum(_installment3AmountCtrl.text),
                                  date: parseDate(_installment3DateCtrl.text),
                                  receivedAmount: parseNum(_installment3ReceivedAmountCtrl.text),
                                  receivedDate: parseDate(_installment3ReceivedDateCtrl.text),
                                );
                                final bank = BankDetails(
                                  bankId: null,
                                  bankName: _selectedBankName ?? _bankNameCtrl.text.trim(),
                                  accountNumber: _accountNumberCtrl.text.trim().isEmpty ? null : _accountNumberCtrl.text.trim(),
                                  branch: _branchCtrl.text.trim().isEmpty ? null : _branchCtrl.text.trim(),
                                  ifsc: _ifscCtrl.text.trim().isEmpty ? null : _ifscCtrl.text.trim(),
                                );
                                final allot = AllotmentDetails(
                                  installment1: i1,
                                  installment2: i2,
                                  installment3: i3,
                                  bankDetails: bank,
                                );
                                final work = WorkDescription(
                                  startDate: parseDate(_startDateCtrl.text),
                                  endDate: parseDate(_endDateCtrl.text),
                                  stage: _selectedWorkStage,
                                  apramStatus: _selectedApramStatus,
                                );
                                // Compute Financial Phase based on received installments
                                int finPhase = 0;
                                if ((i1.receivedAmount ?? 0) > 0) finPhase = 1;
                                if ((i2.receivedAmount ?? 0) > 0) finPhase = 2;
                                if ((i3.receivedAmount ?? 0) > 0) finPhase = 3;
                                final draft = Project(
                                  id: 'new',
                                  name: _nameCtrl.text.trim(),
                                  description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                                  ownerId: auth.uid,
                                  blockId: _selectedBlockId ?? (auth.blockId ?? ''),
                                  villageId: (auth.assignedVillage ?? ''),
                                  status: ProjectStatus.in_progress,
                                  phase: finPhase,
                                  location: GeoPoint(_lat!, _lng!),
                                  address: _addressCtrl.text.trim(),
                                  geohash: encodeGeohash(_lat!, _lng!, precision: 10),
                                  financials: finance,
                                  landDetails: {
                                    if ((_selectedBlockName ?? '').isNotEmpty) 'blockName': _selectedBlockName,
                                    if (_villageCtrl.text.trim().isNotEmpty) 'villageName': _villageCtrl.text.trim(),
                                    if (_selectedGramPanchayatName != null && _selectedGramPanchayatName!.isNotEmpty) 'gramPanchayat': _selectedGramPanchayatName,
                                  },
                                  preliminaryDescription: prelim,
                                  sanctionCompliance: sanction,
                                  allotmentDetails: allot,
                                  workDescription: work,
                                  createdAt: now,
                                  updatedAt: now,
                                );
                                // Allocate an ID upfront to upload under a deterministic path
                                final projectId = repo.allocateId();
                                // Generate a sequential project code (best-effort)
                                String? projectCode;
                                try {
                                  projectCode = await repo.nextProjectCode();
                                } catch (_) {}

                                // uploads (with retry)
                                // Count uploads from offline store categories
                                final workPhotos = _mediaStore?.list(category: 'work_photo') ?? const [];
                                final workDocs = _mediaStore?.list(category: 'work_doc') ?? const [];
                                final sanctionTechDocItems = _mediaStore?.list(category: 'sanction_tech_doc') ?? const [];
                                final sanctionTechPhotoItems = _mediaStore?.list(category: 'sanction_tech_photo') ?? const [];
                                final sanctionAdminDocItems = _mediaStore?.list(category: 'sanction_admin_doc') ?? const [];
                                // check map snapshot availability for counting
                                final boundaryForCount = _mapKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                                final includeMapSnapshot = boundaryForCount != null;
                                // Work categorized docs (Section 4)
                                final mbDocItems = _mediaStore?.list(category: 'work_mb') ?? const [];
                                final testDocItems = _mediaStore?.list(category: 'work_test') ?? const [];
                                final workRepDocItems = _mediaStore?.list(category: 'work_workrep') ?? const [];
                                final certDocItems = _mediaStore?.list(category: 'work_cert') ?? const [];
                                setState(() {
                                  _totalUploads = workPhotos.length + workDocs.length + (includeMapSnapshot ? 1 : 0)
                                    + sanctionTechDocItems.length + sanctionTechPhotoItems.length + sanctionAdminDocItems.length
                                    + mbDocItems.length + testDocItems.length + workRepDocItems.length + certDocItems.length;
                                  _completedUploads = 0;
                                  _currentFileProgress = 0;
                                });
                                // helper for bytes upload with progress via adapter (fire_storage_impl on mobile, native on web)
                                Future<String> uploadBytesWithProgress({
                                  required String label,
                                  required String path,
                                  required List<int> bytes,
                                  fs.SettableMetadata? metadata,
                                  String? statusKey,
                                  Map<String, String>? statusMap,
                                  Map<String, double>? progMap,
                                }) async {
                                  setState(() {
                                    _currentLabel = label;
                                    _currentFileProgress = 0.0;
                                  });
                                  if (statusMap != null && statusKey != null) statusMap[statusKey] = 'uploading';
                                  final contentType = metadata?.contentType;
                                  await storage.uploadWithAdapter(
                                    path: path,
                                    bytes: bytes,
                                    contentType: contentType,
                                    fileName: path.split('/').isNotEmpty ? path.split('/').last : null,
                                    onProgress: (v) {
                                      setState(() {
                                        _currentFileProgress = v;
                                        if (progMap != null && statusKey != null) progMap[statusKey] = v;
                                      });
                                    },
                                  );
                                  if (statusMap != null && statusKey != null) statusMap[statusKey] = 'done';
                                  return path;
                                }

                                // sanction uploads from store
                                final sanctionUrls = <String>[];
                                for (final it in sanctionTechDocItems) {
                                  final dest = 'projects/$projectId/sanction/technical_approval_docs/${DateTime.now().millisecondsSinceEpoch}_${_safeName(it.name)}';
                                  final label = 'Document: Technical Approval ${it.name}';
                                  final path = await uploadWithRetry(label, () => uploadBytesWithProgress(
                                    label: label,
                                    path: dest,
                                    bytes: it.bytes,
                                    metadata: fs.SettableMetadata(
                                      contentType: 'application/pdf',
                                      customMetadata: {'uploaderId': auth.uid},
                                    ),
                                    statusKey: it.id,
                                    statusMap: _docStatus,
                                    progMap: _docProgress,
                                  ));
                                  if (path != null) sanctionUrls.add(path);
                                  if (mounted) setState(() { _completedUploads++; _currentFileProgress = 0.0; });
                                }
                                for (final it in sanctionTechPhotoItems) {
                                  final dest = 'projects/$projectId/sanction/technical_approval_photos/${DateTime.now().millisecondsSinceEpoch}_${_safeName(it.name)}';
                                  final label = 'Photo: Technical Approval ${it.name}';
                                  // Compress JPEGs to reduce bandwidth/cost; keep non-JPEG as-is
                                  final photoBytes = (() {
                                    try {
                                      if ((it.contentType).toLowerCase().startsWith('image/jpeg')) {
                                        return image_utils.ImageUtils.compressJpeg(it.bytes, maxWidth: 1600, maxHeight: 1600, quality: 80);
                                      }
                                    } catch (_) {}
                                    return it.bytes;
                                  })();
                                  final path = await uploadWithRetry(label, () => uploadBytesWithProgress(
                                    label: label,
                                    path: dest,
                                    bytes: photoBytes,
                                    metadata: fs.SettableMetadata(
                                      contentType: 'image/jpeg',
                                      customMetadata: {'uploaderId': auth.uid},
                                    ),
                                    statusKey: it.id,
                                    statusMap: _photoStatus,
                                    progMap: _photoProgress,
                                  ));
                                  if (path != null) sanctionUrls.add(path);
                                  if (mounted) setState(() { _completedUploads++; _currentFileProgress = 0.0; });
                                }
                                for (final it in sanctionAdminDocItems) {
                                  final dest = 'projects/$projectId/sanction/admin_approval_docs/${DateTime.now().millisecondsSinceEpoch}_${_safeName(it.name)}';
                                  final label = 'Document: Admin Approval ${it.name}';
                                  final path = await uploadWithRetry(label, () => uploadBytesWithProgress(
                                    label: label,
                                    path: dest,
                                    bytes: it.bytes,
                                    metadata: fs.SettableMetadata(
                                      contentType: 'application/pdf',
                                      customMetadata: {'uploaderId': auth.uid},
                                    ),
                                    statusKey: it.id,
                                    statusMap: _docStatus,
                                    progMap: _docProgress,
                                  ));
                                  if (path != null) sanctionUrls.add(path);
                                  if (mounted) setState(() { _completedUploads++; _currentFileProgress = 0.0; });
                                }

                                final photoUrls = <String>[];
                                int photoFailures = 0;
                                for (final it in workPhotos) {
                                  final dest = 'projects/$projectId/photos/${DateTime.now().millisecondsSinceEpoch}_${_safeName(it.name)}';
                                  final label = 'Photo: ${it.name}';
                                  // Compress JPEGs; other formats unchanged
                                  final photoBytes = (() {
                                    try {
                                      if ((it.contentType).toLowerCase().startsWith('image/jpeg')) {
                                        return image_utils.ImageUtils.compressJpeg(it.bytes, maxWidth: 1600, maxHeight: 1600, quality: 80);
                                      }
                                    } catch (_) {}
                                    return it.bytes;
                                  })();
                                  final path = await uploadWithRetry(label, () => uploadBytesWithProgress(
                                    label: label,
                                    path: dest,
                                    bytes: photoBytes,
                                    metadata: fs.SettableMetadata(
                                      contentType: 'image/jpeg',
                                      customMetadata: {'uploaderId': auth.uid},
                                    ),
                                    statusKey: it.id,
                                    statusMap: _photoStatus,
                                    progMap: _photoProgress,
                                  ));
                                  if (path != null) {
                                    photoUrls.add(path);
                                  } else {
                                    photoFailures++;
                                    setState(() { _photoStatus[it.id] = 'fail'; });
                                  }
                                  if (mounted) setState(() { _completedUploads++; _currentFileProgress = 0.0; });
                                }
                                final docUrls = <String>[];
                                int docFailures = 0;
                                for (final it in workDocs) {
                                  final dest = 'projects/$projectId/docs/${DateTime.now().millisecondsSinceEpoch}_${_safeName(it.name)}';
                                  final label = 'Document: ${it.name}';
                                  final ct = it.contentType;
                                  final path = await uploadWithRetry(label, () => uploadBytesWithProgress(
                                    label: label,
                                    path: dest,
                                    bytes: it.bytes,
                                    metadata: fs.SettableMetadata(
                                      contentType: ct,
                                      customMetadata: {'uploaderId': auth.uid},
                                    ),
                                    statusKey: it.id,
                                    statusMap: _docStatus,
                                    progMap: _docProgress,
                                  ));
                                  if (path != null) {
                                    docUrls.add(path);
                                  } else {
                                    docFailures++;
                                    setState(() { _docStatus[it.id] = 'fail'; });
                                  }
                                  if (mounted) setState(() { _completedUploads++; _currentFileProgress = 0.0; });
                                }
                                // videos removed per requirements

                                // Section 4 categorized uploads
                                final mbUrls = <String>[];
                                for (final it in mbDocItems) {
                                  final dest = 'projects/$projectId/work/measurement_books/${DateTime.now().millisecondsSinceEpoch}_${_safeName(it.name)}';
                                  final label = 'Document: MB ${it.name}';
                                  final path = await uploadWithRetry(label, () => uploadBytesWithProgress(
                                    label: label,
                                    path: dest,
                                    bytes: it.bytes,
                                    metadata: fs.SettableMetadata(
                                      contentType: it.contentType,
                                      customMetadata: {'uploaderId': auth.uid},
                                    ),
                                    statusKey: it.id,
                                    statusMap: _docStatus,
                                    progMap: _docProgress,
                                  ));
                                  if (path != null) mbUrls.add(path);
                                  if (mounted) setState(() { _completedUploads++; _currentFileProgress = 0.0; });
                                }
                                final testUrls = <String>[];
                                for (final it in testDocItems) {
                                  final dest = 'projects/$projectId/work/test_reports/${DateTime.now().millisecondsSinceEpoch}_${_safeName(it.name)}';
                                  final label = 'Document: Test ${it.name}';
                                  final path = await uploadWithRetry(label, () => uploadBytesWithProgress(
                                    label: label,
                                    path: dest,
                                    bytes: it.bytes,
                                    metadata: fs.SettableMetadata(
                                      contentType: it.contentType,
                                      customMetadata: {'uploaderId': auth.uid},
                                    ),
                                    statusKey: it.id,
                                    statusMap: _docStatus,
                                    progMap: _docProgress,
                                  ));
                                  if (path != null) testUrls.add(path);
                                  if (mounted) setState(() { _completedUploads++; _currentFileProgress = 0.0; });
                                }
                                final workRepUrls = <String>[];
                                for (final it in workRepDocItems) {
                                  final dest = 'projects/$projectId/work/work_reports/${DateTime.now().millisecondsSinceEpoch}_${_safeName(it.name)}';
                                  final label = 'Document: Work Report ${it.name}';
                                  final path = await uploadWithRetry(label, () => uploadBytesWithProgress(
                                    label: label,
                                    path: dest,
                                    bytes: it.bytes,
                                    metadata: fs.SettableMetadata(
                                      contentType: it.contentType,
                                      customMetadata: {'uploaderId': auth.uid},
                                    ),
                                    statusKey: it.id,
                                    statusMap: _docStatus,
                                    progMap: _docProgress,
                                  ));
                                  if (path != null) workRepUrls.add(path);
                                  if (mounted) setState(() { _completedUploads++; _currentFileProgress = 0.0; });
                                }
                                final certUrls = <String>[];
                                for (final it in certDocItems) {
                                  final dest = 'projects/$projectId/work/certificates/${DateTime.now().millisecondsSinceEpoch}_${_safeName(it.name)}';
                                  final label = 'Document: Certificate ${it.name}';
                                  final path = await uploadWithRetry(label, () => uploadBytesWithProgress(
                                    label: label,
                                    path: dest,
                                    bytes: it.bytes,
                                    metadata: fs.SettableMetadata(
                                      contentType: it.contentType,
                                      customMetadata: {'uploaderId': auth.uid},
                                    ),
                                    statusKey: it.id,
                                    statusMap: _docStatus,
                                    progMap: _docProgress,
                                  ));
                                  if (path != null) certUrls.add(path);
                                  if (mounted) setState(() { _completedUploads++; _currentFileProgress = 0.0; });
                                }

                                // map snapshot (optional)
                                String? mapSnapshotUrl;
                                try {
                                  final boundary = _mapKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                                  if (boundary != null) {
                                    final image = await boundary.toImage(pixelRatio: 2.0);
                                    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                                    final bytesPng = byteData?.buffer.asUint8List();
                                    if (bytesPng != null) {
                                      // Convert to JPEG to satisfy Storage photo rules
                                      final decoded = image_lib.decodeImage(bytesPng);
                                      if (decoded != null) {
                                        final bytesJpg = image_lib.encodeJpg(decoded, quality: 85);
                                        final refPath = 'projects/$projectId/photos/map_snapshot_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                        setState(() {
                                          _currentLabel = 'Map snapshot';
                                          _currentFileProgress = 0.0;
                                        });
                                        final uploaded = await uploadWithRetry('map_snapshot.jpg', () => storage.uploadBytes(
                                          path: refPath,
                                          bytes: bytesJpg,
                                          metadata: fs.SettableMetadata(
                                            contentType: 'image/jpeg',
                                            customMetadata: {'uploaderId': auth.uid},
                                          ),
                                        ));
                                        if (uploaded != null) {
                                          mapSnapshotUrl = uploaded;
                                        } else {
                                          debugPrint('Map snapshot upload ultimately failed');
                                        }
                                        if (mounted) {
                                          setState(() {
                                            _completedUploads++;
                                          });
                                        }
                                      }
                                    }
                                  }
                                } catch (_) {}

                                // Fail hard if mandatory uploads are missing after attempts
                                if (sanctionUrls.isEmpty) {
                                  throw Exception('Technical/Admin approval files failed to upload.');
                                }
                                // Build the final project object with URLs
                                final finalProject = draft.copyWith(
                                  id: projectId,
                                  photoUrls: photoUrls,
                                  documentUrls: docUrls,
                                  originalPhotoUrls: List.of(photoUrls),
                                  mapSnapshotUrl: mapSnapshotUrl,
                                  updatedAt: DateTime.now(),
                                ).copyWith(
                                  sanctionCompliance: draft.sanctionCompliance.copyWith(
                                    approvalDocumentUrls: sanctionUrls,
                                  ),
                                  workDescription: draft.workDescription.copyWith(
                                    measurementBookUrls: mbUrls,
                                    testReportUrls: testUrls,
                                    workReportUrls: workRepUrls,
                                    certificateUrls: certUrls,
                                  ),
                                );
                                // Create document now that uploads have succeeded
                                // Prepare ownerDetails snapshot for quick access
                                Map<String, dynamic> ownerDetails = {};
                                try {
                                  final snap = await FirebaseFirestore.instance.collection('users').doc(finalProject.ownerId).get();
                                  final d = snap.data() ?? const <String, dynamic>{};
                                  ownerDetails = {
                                    'displayName': d['displayName'],
                                    'email': d['email'],
                                    'phone': d['phone'],
                                    'whatsapp': d['whatsapp'],
                                    'address': d['address'],
                                    'aadhar': d['aadhar'],
                                  }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
                                } catch (_) {}
                                await repo.createAt(projectId, finalProject, extra: {
                                  if (projectCode != null) 'projectCode': projectCode,
                                  if (ownerDetails.isNotEmpty) 'ownerDetails': ownerDetails,
                                });
                                // Fire updates feed entries (owner + nodals)
                                try {
                                  final updatesRepo = ref.read(updatesRepositoryProvider);
                                  await updatesRepo.addEventForOwner(
                                    projectId: projectId,
                                    projectName: finalProject.name,
                                    ownerId: finalProject.ownerId,
                                    blockId: finalProject.blockId,
                                    actorId: auth.uid,
                                    actorRole: auth.role.key,
                                    action: 'created',
                                  );
                                  await updatesRepo.addEventForNodals(
                                    projectId: projectId,
                                    projectName: finalProject.name,
                                    ownerId: finalProject.ownerId,
                                    blockId: finalProject.blockId,
                                    actorId: auth.uid,
                                    actorRole: auth.role.key,
                                    action: 'created',
                                  );
                                } catch (_) {}
                                // Post an "updated" event
                                try {
                                  final updatesRepo = ref.read(updatesRepositoryProvider);
                                  await updatesRepo.addEventForOwner(
                                    projectId: projectId,
                                    projectName: finalProject.name,
                                    ownerId: finalProject.ownerId,
                                    blockId: finalProject.blockId,
                                    actorId: auth.uid,
                                    actorRole: auth.role.key,
                                    action: 'updated',
                                  );
                                  await updatesRepo.addEventForNodals(
                                    projectId: projectId,
                                    projectName: finalProject.name,
                                    ownerId: finalProject.ownerId,
                                    blockId: finalProject.blockId,
                                    actorId: auth.uid,
                                    actorRole: auth.role.key,
                                    action: 'updated',
                                  );
                                } catch (_) {}

                                // inform if any uploads failed
                final failed = photoFailures + docFailures;
                                if (failed > 0 && mounted) {
                                  toastification.show(
                                    context: context,
                                    title: const Text('Saved with some issues'),
                  description: Text('${photoUrls.length} photos, ${docUrls.length} docs • $failed failed'),
                                    type: ToastificationType.warning,
                                    style: ToastificationStyle.fillColored,
                                    autoCloseDuration: const Duration(seconds: 4),
                                    showProgressBar: true,
                                    icon: const Icon(CupertinoIcons.exclamationmark_triangle_fill),
                                  );
                                }

                                if (!mounted) return;
                                // Clear local draft, media, and form on success
                                await _clearDraftLocally();
                                await _mediaStore?.clear();
                                await _resetForm();
                                // Notify parent to show success popup
                                widget.onCreated?.call(
                                  finalProject.copyWith(id: projectId),
                                  projectCode: projectCode,
                                );
          } catch (e) {
                                if (mounted) {
                                  toastification.show(
                                    context: context,
            title: const Text('Save failed'),
                                    description: Text(_lastUploadError == null ? '$e' : '$e\n$_lastUploadError'),
                                    type: ToastificationType.error,
                                    style: ToastificationStyle.fillColored,
                                    autoCloseDuration: const Duration(seconds: 4),
                                    showProgressBar: true,
                                    icon: const Icon(CupertinoIcons.exclamationmark_triangle),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _saving = false);
                              }
              }
            : null,
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(CupertinoIcons.plus_circle_fill),
          label: const Text('Create Project', textAlign: TextAlign.center,),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            alignment: Alignment.center,
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              height: 1.0,
              leadingDistribution: TextLeadingDistribution.even,
              textBaseline: TextBaseline.alphabetic,
            ),
          ),
                  );
                  if (!narrow) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [resetBtn, saveBtn],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      resetBtn,
                      const SizedBox(height: 8),
                      saveBtn,
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Find the first FormField with an error in the widget tree
  
}

// _CreateProjectCard removed: creation handled via dedicated tab

class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onOpen;
  const _ProjectCard({required this.project, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        cs.primary.withValues(alpha: 0.20),
        cs.primaryContainer.withValues(alpha: 0.60),
      ],
    );
    return InkWell(
      onTap: onOpen,
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
          ),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.building_2_fill, color: cs.onPrimaryContainer, size: 36),
                const SizedBox(height: 8),
                Text(
                  project.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text('#${project.id}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Builder(builder: (context) {
                  final statusLabel = project.status.name;
                  Color statusColor; IconData statusIcon;
                  switch (project.status) {
                    case ProjectStatus.completed:
                      statusColor = Colors.green; statusIcon = CupertinoIcons.check_mark_circled_solid; break;
                    case ProjectStatus.cancelled:
                      statusColor = Colors.grey; statusIcon = CupertinoIcons.xmark_circle_fill; break;
                    case ProjectStatus.in_progress:
                      statusColor = Colors.amber; statusIcon = CupertinoIcons.clock_solid; break;
                  }
                  final deadlineVal = project.financials['deadline'];
                  final isLate = _isLate(deadlineVal);
                  return Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _StatusChip(label: statusLabel, inverted: true, color: statusColor, icon: statusIcon),
                      if (project.phase > 0) _StatusChip(label: 'Financial Phase ${project.phase}', inverted: true, color: Colors.white70, icon: CupertinoIcons.number),
                      if (deadlineVal != null)
                        _StatusChip(label: 'Due ${_fmtDeadline(deadlineVal)}', inverted: true, color: isLate ? Colors.redAccent : Colors.white70, icon: CupertinoIcons.calendar),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool inverted;
  final Color? color;
  final IconData? icon;
  const _StatusChip({required this.label, this.inverted = false, this.color, this.icon});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = color ?? (inverted ? Colors.white : cs.primary);
    final bg = inverted ? Colors.white.withValues(alpha: 0.16) : base.withValues(alpha: 0.12);
    final border = inverted ? Colors.white24 : base.withValues(alpha: 0.24);
    final fg = inverted ? Colors.white : base;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  height: 1.0,
                  leadingDistribution: TextLeadingDistribution.even,
                  textBaseline: TextBaseline.alphabetic,
                ),
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: true,
              applyHeightToLastDescent: true,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtDeadline(dynamic v) {
  if (v == null) return '';
  try {
    if (v is Timestamp) {
      final d = v.toDate();
      return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    }
    if (v is DateTime) {
      return '${v.year}-${v.month.toString().padLeft(2,'0')}-${v.day.toString().padLeft(2,'0')}';
    }
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    }
    if (v is Map && v['seconds'] != null) {
      final secs = (v['seconds'] as num).toInt();
      final d = DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true).toLocal();
      return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    }
  } catch (_) {}
  return '';
}

bool _isLate(dynamic v) {
  try {
    if (v == null) {
      return false;
    }
    DateTime? d;
    if (v is Timestamp) {
      d = v.toDate();
    } else if (v is DateTime) {
      d = v;
    } else if (v is String) {
      d = DateTime.tryParse(v);
    }
    else if (v is Map && v['seconds'] != null) {
      final secs = (v['seconds'] as num).toInt();
      d = DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true).toLocal();
    }
    if (d == null) {
      return false;
    }
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return d.isBefore(startOfToday);
  } catch (_) { return false; }
}

class _ProjectListTile extends StatelessWidget {
  final Project project;
  final VoidCallback onOpen;
  const _ProjectListTile({required this.project, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ld = project.landDetails;
    final block = (ld['blockName'] ?? '') as String?;
    final village = (ld['villageName'] ?? '') as String?;
    final location = [block, village].where((e) => (e ?? '').toString().trim().isNotEmpty).join(' • ');
  final statusLabel = project.status.name;
    Color statusColor; IconData statusIcon;
    switch (project.status) {
      case ProjectStatus.completed:
        statusColor = Colors.green; statusIcon = CupertinoIcons.check_mark_circled_solid; break;
      case ProjectStatus.cancelled:
        statusColor = Colors.grey; statusIcon = CupertinoIcons.xmark_circle_fill; break;
      case ProjectStatus.in_progress:
        statusColor = Colors.amber; statusIcon = CupertinoIcons.clock_solid; break;
    }
  final deadlineVal = project.financials['deadline'];
  final isLate = _isLate(deadlineVal);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onOpen,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(CupertinoIcons.building_2_fill, color: cs.primary),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Text('#${project.id}', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (location.isNotEmpty) Text(location, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _StatusChip(label: statusLabel, color: statusColor, icon: statusIcon),
              if (project.phase > 0) _StatusChip(label: 'Financial Phase ${project.phase}', color: Theme.of(context).colorScheme.primary, icon: CupertinoIcons.number),
              if (deadlineVal != null) _StatusChip(label: 'Due ${_fmtDeadline(deadlineVal)}', color: isLate ? Colors.redAccent : Theme.of(context).colorScheme.secondary, icon: CupertinoIcons.calendar),
            ]),
          ]),
        ),
        trailing: const Icon(CupertinoIcons.forward),
      ),
    );
  }
}

class _ProjectsSearchBar extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _ProjectsSearchBar({required this.onChanged});
  @override
  State<_ProjectsSearchBar> createState() => _ProjectsSearchBarState();
}

class _ProjectsSearchBarState extends State<_ProjectsSearchBar> {
  final _ctrl = TextEditingController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _ctrl,
        onChanged: widget.onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search Projects',
          prefixIcon: const Icon(CupertinoIcons.search, size: 18),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.primary)),
        ),
      ),
    );
  }
}

class _PageScaffold extends StatelessWidget {
  const _PageScaffold({required this.title, required this.child, required this.onMenu});
  final String title;
  final Widget child;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 48 + (Theme.of(context).platform == TargetPlatform.android ? 4 : 0),
        leading: Row(
          children: [
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(CupertinoIcons.bars),
              onPressed: onMenu,
              tooltip: 'Sidebar',
            ),
            if (Theme.of(context).platform == TargetPlatform.android)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
        automaticallyImplyLeading: false,
        title: Theme.of(context).platform == TargetPlatform.android ? const SizedBox.shrink() : Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        centerTitle: false,
      ),
      body: child,
    );
  }
}

