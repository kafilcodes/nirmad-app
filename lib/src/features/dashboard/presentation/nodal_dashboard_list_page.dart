import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../projects/domain/project.dart';
import '../../projects/presentation/project_detail_page.dart';
import '../../projects/data/project_repository.dart';
// import 'package:url_launcher/url_launcher.dart';
// import '../../../services/functions_service.dart';
// import '../../../shared/ui/toast.dart';
import '../../../shared/widgets/no_data.dart';
import '../../../shared/data/blocks_provider.dart';
import '../../../shared/widgets/project_card.dart';
import '../state/projects_snapshot_provider.dart';
import '../../../shared/utils/date_parse.dart';
import '../../../shared/ui/progress.dart';

final nodalStatusFilterProvider = StateProvider<ProjectStatus?>((_) => null);
// Overdue-days filter (e.g., 30 or 60). Null means no overdue filter.
final nodalOverdueDaysFilterProvider = StateProvider<int?>((_) => null);
// Stage filter (derived from workDescription.stage, coerced to lowercase). Null => all stages.
final nodalStageFilterProvider = StateProvider<String?>((_) => null);
// Client-side paging: how many items are visible. Avoids resubscribing streams.
final _visibleCountProvider = StateProvider<int>((_) => 25);
final _accumulatedProvider = StateProvider<List<Project>>((_) => const []);
final _viewGridProvider = StateProvider<bool>((_) => true);
// Make search autoDispose so it resets when leaving the dashboard route entirely.
final _searchProvider = StateProvider.autoDispose<String>((_) => '');
// Exposed (not private) so dashboard shell can reset this on tab changes.
final blockFilterProvider = StateProvider<String?>((_) => null);
// New: Gram Panchayat filter (only used for sub-nodal role). Value stored lowercase & trimmed.
final gramPanchayatFilterProvider = StateProvider<String?>((_) => null);
enum _SortBy { updatedDesc, updatedAsc, nameAsc, nameDesc, status }
final _sortProvider = StateProvider<_SortBy>((_) => _SortBy.updatedDesc);
final _pageSize = 25;

class NodalDashboardListPage extends ConsumerWidget {
  const NodalDashboardListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  final status = ref.watch(nodalStatusFilterProvider);
  final overdueDays = ref.watch(nodalOverdueDaysFilterProvider);
    final auth = ref.watch(authStateProvider).value;
  final isGrid = ref.watch(_viewGridProvider);
  final search = ref.watch(_searchProvider);
  final blockFilter = ref.watch(blockFilterProvider);
  final gpFilter = ref.watch(gramPanchayatFilterProvider); // may be null unless sub-nodal interaction
  return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        titleSpacing: 8,
        title: CupertinoSearchTextField(
          placeholder: 'Search projects',
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          onChanged: (v) {
            ref.read(_searchProvider.notifier).state = v.trim();
            _resetPagination(ref);
          },
        ),
        actions: [
          // Keep only view toggle on very narrow screens; move filters below
          if (MediaQuery.of(context).size.width >= 480) ...[
            IconButton(
              tooltip: 'Sort',
              icon: const Icon(CupertinoIcons.arrow_up_arrow_down_square),
              onPressed: () => _openSortSheet(context, ref),
            ),
            _withDot(
              active: status != null,
              child: IconButton(
                tooltip: 'Status',
                icon: const Icon(CupertinoIcons.checkmark_seal),
                onPressed: () async {
                  final sel = await _pickStatus(context);
                  ref.read(nodalStatusFilterProvider.notifier).state = sel;
                  _resetPagination(ref);
                },
              ),
            ),
            _withDot(
              active: overdueDays != null,
              child: IconButton(
                tooltip: 'Overdue',
                icon: const Icon(CupertinoIcons.calendar),
                onPressed: () async {
                  final sel = await _pickOverdueDays(context);
                  ref.read(nodalOverdueDaysFilterProvider.notifier).state = sel;
                  _resetPagination(ref);
                },
              ),
            ),
            if (auth != null && (auth.role == UserRole.superNodal || auth.role == UserRole.devAdmin))
              _withDot(
                active: blockFilter != null && blockFilter.isNotEmpty,
                child: IconButton(
                  tooltip: 'Block',
                  icon: const Icon(CupertinoIcons.map_pin_ellipse),
                  onPressed: () async {
                    final sel = await _pickBlock(context, ref);
                    ref.read(blockFilterProvider.notifier).state = sel;
                    _resetPagination(ref);
                  },
                ),
              ),
          ],
          IconButton(
            tooltip: isGrid ? 'Grid view' : 'List view',
            onPressed: () => ref.read(_viewGridProvider.notifier).state = !isGrid,
            icon: Icon(isGrid ? CupertinoIcons.square_grid_2x2 : CupertinoIcons.list_bullet),
          ),
          const SizedBox(width: 4),
        ],
        bottom: MediaQuery.of(context).size.width < 480
            ? PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 4,
                    children: [
                      // Sort
                      IconButton(
                        tooltip: 'Sort',
                        icon: const Icon(CupertinoIcons.arrow_up_arrow_down_square),
                        onPressed: () => _openSortSheet(context, ref),
                      ),
                      // Status
                      _withDot(
                        active: status != null,
                        child: IconButton(
                          tooltip: 'Status',
                          icon: const Icon(CupertinoIcons.checkmark_seal),
                          onPressed: () async {
                            final sel = await _pickStatus(context);
                            ref.read(nodalStatusFilterProvider.notifier).state = sel;
                            _resetPagination(ref);
                          },
                        ),
                      ),
                      // Overdue
                      _withDot(
                        active: overdueDays != null,
                        child: IconButton(
                          tooltip: 'Overdue',
                          icon: const Icon(CupertinoIcons.calendar),
                          onPressed: () async {
                            final sel = await _pickOverdueDays(context);
                            ref.read(nodalOverdueDaysFilterProvider.notifier).state = sel;
                            _resetPagination(ref);
                          },
                        ),
                      ),
                      if (auth != null && (auth.role == UserRole.superNodal || auth.role == UserRole.devAdmin))
                        _withDot(
                          active: blockFilter != null && blockFilter.isNotEmpty,
                          child: IconButton(
                            tooltip: 'Block',
                            icon: const Icon(CupertinoIcons.map_pin_ellipse),
                            onPressed: () async {
                              final sel = await _pickBlock(context, ref);
                              ref.read(blockFilterProvider.notifier).state = sel;
                              _resetPagination(ref);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
        children: [
          // No extra controls here; kept compact via AppBar actions
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notif) {
                if (notif.metrics.pixels + 200 >= notif.metrics.maxScrollExtent) {
                  final current = ref.read(_visibleCountProvider);
                  ref.read(_visibleCountProvider.notifier).state = current + _pageSize;
                }
                return false;
              },
              child: Consumer(
                builder: (context, ref, _) {
                  final diskFirst = ref.watch(nodalFirstPageDiskFirstProvider).maybeWhen(data: (v) => v, orElse: () => const <Project>[]);
                  final asyncSnap = ref.watch(dashboardProjectsStreamProvider);
                  return asyncSnap.when(
                    data: (snap) {
                      // Map to models
                      var items = snap.docs.map(Project.fromDoc).toList();
                      // Defensive: if user is sub nodal, enforce alias-aware block filter client-side too
                      if (auth?.role == UserRole.subNodal) {
                        final keys = blockQueryKeys(auth?.blockId).map((e) => e.toLowerCase()).toSet();
                        if (keys.isNotEmpty) {
                          items = items.where((p) => keys.contains(p.blockId.toLowerCase())).toList();
                        } else {
                          items = const [];
                        }
                      }
                      // Optional block filter for super/admin (client-side)
                      if (blockFilter != null && blockFilter.isNotEmpty && (auth?.role == UserRole.superNodal || auth?.role == UserRole.devAdmin)) {
                        final keys = blockQueryKeys(blockFilter).map((e) => e.toLowerCase()).toSet();
                        items = items.where((p) => keys.contains(p.blockId.toLowerCase())).toList();
                      }
                      // Gram Panchayat filter (only if sub-nodal selected via charts)
                      if (gpFilter != null && gpFilter.isNotEmpty && auth?.role == UserRole.subNodal) {
                        final target = gpFilter.toLowerCase();
                        items = items.where((p) => (p.preliminaryDescription.gramPanchayat?.trim().toLowerCase() ?? '') == target).toList();
                      }
                      // Apply search/status/sort
                      final shown = _applyFiltersAndSort(ref, items, search);
                      // Persist accumulated for error fallback
                      Future.microtask(() {
                        try { ref.read(_accumulatedProvider.notifier).state = shown; } catch (_) {}
                      });
                      // Client-side paging
                      final visible = ref.watch(_visibleCountProvider);
                      final toShow = shown.take(visible).toList();
                      if (toShow.isEmpty) {
                        // Scoped empty-state: show within list area only, preserving toolbar & filters header.
                        return _ListContainer(
                          child: _NoResultsScoped(
                            hasAny: items.isNotEmpty,
                            isSearching: search.trim().isNotEmpty,
                          ),
                        );
                      }
                      return _buildList(context, ref, toShow, isGrid, search);
                    },
                    loading: () {
                      final placeholder = ref.watch(_accumulatedProvider);
                      if (placeholder.isNotEmpty) return _buildList(context, ref, placeholder, isGrid, search);
                      if (diskFirst.isNotEmpty) return _buildList(context, ref, diskFirst, isGrid, search);
                      return const Center(child: AppLoadingIndicator());
                    },
                    error: (_, __) {
                      final placeholder = ref.watch(_accumulatedProvider);
                      final list = placeholder.isNotEmpty ? placeholder : (diskFirst.isNotEmpty ? diskFirst : const <Project>[]);
                      if (list.isNotEmpty) return _buildList(context, ref, list, isGrid, search);
                      return const _ListContainer(child: Center(child: NoData(message: 'Failed to load projects', asset: 'assets/server_error.svg')));
                    },
                  );
                },
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  void _resetPagination(WidgetRef ref) {
    ref.read(_visibleCountProvider.notifier).state = _pageSize;
    ref.read(_accumulatedProvider.notifier).state = const [];
  }

  Widget _buildList(BuildContext context, WidgetRef ref, List<Project> items, bool isGrid, String search) {
  // Always work on a mutable copy; some sources return unmodifiable lists in web builds
  var filtered = List<Project>.from(items);
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = items.where((p) {
        final sarpanch = p.preliminaryDescription.sarpanchName?.toLowerCase() ?? '';
        final gram = p.preliminaryDescription.gramPanchayat?.toLowerCase() ?? '';
        final secretary = p.preliminaryDescription.secretaryName?.toLowerCase() ?? '';
        return p.name.toLowerCase().contains(q) ||
            p.blockId.toLowerCase().contains(q) ||
            sarpanch.contains(q) ||
            gram.contains(q) ||
            secretary.contains(q);
      }).toList();
    }
    // Apply status filter client-side to avoid composite index stalls
  final statusFilter = ref.read(nodalStatusFilterProvider);
    if (statusFilter != null) {
      filtered = filtered.where((p) => p.status == statusFilter).toList();
    }
    // Apply overdue-days filter (deadline older than N days from today)
    final days = ref.read(nodalOverdueDaysFilterProvider);
    if (days != null) {
      filtered = filtered.where((p) => _isOverdueByDays(p, days)).toList();
    }
    // Apply stage filter (workDescription.stage coerced to lowercase; completed projects stage coerced to 'completed').
    final stageFilter = ref.read(nodalStageFilterProvider);
    if (stageFilter != null && stageFilter.isNotEmpty) {
      filtered = filtered.where((p) {
        var stage = p.workDescription.stage?.name.toLowerCase() ?? 'unknown';
        if (p.status == ProjectStatus.completed) stage = 'completed';
        return stage == stageFilter;
      }).toList();
    }
    // Apply client-side sort when user changed preference
    switch (ref.read(_sortProvider)) {
      case _SortBy.updatedDesc:
        filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case _SortBy.updatedAsc:
        filtered.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        break;
      case _SortBy.nameAsc:
        filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _SortBy.nameDesc:
        filtered.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case _SortBy.status:
        filtered.sort((a, b) => a.status.name.compareTo(b.status.name));
        break;
    }
    final list = isGrid ? _buildGrid(filtered) : _buildListView(filtered, ref, context);
    return _ListContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActiveFiltersBar(onClearAll: () {
            ref.read(nodalStatusFilterProvider.notifier).state = null;
            ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
            ref.read(blockFilterProvider.notifier).state = null;
            ref.read(nodalStageFilterProvider.notifier).state = null;
            ref.read(gramPanchayatFilterProvider.notifier).state = null;
          }),
          Expanded(child: list),
        ],
      ),
    );
  }

  Widget _buildGrid(List<Project> filtered) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        final isSmall = maxW < 420;
        final itemMin = isSmall ? 300.0 : 340.0; // denser on small screens
        final columns = (maxW / itemMin).floor().clamp(1, 4);
        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: isSmall ? 1.1 : 1.25,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final p = filtered[i];
            return ProjectCard(project: p, onOpen: () => _openDetails(context, p, tabbed: true));
          },
        );
      },
    );
  }

  Widget _buildListView(List<Project> filtered, WidgetRef ref, BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final p = filtered[index];
        final cs = Theme.of(context).colorScheme;
        IconData sIcon;
        Color sColor;
        switch (p.status) {
          case ProjectStatus.completed:
            sIcon = CupertinoIcons.checkmark_seal_fill;
            sColor = Colors.green;
            break;
          case ProjectStatus.in_progress:
            sIcon = CupertinoIcons.clock_fill;
            sColor = Colors.orange;
            break;
          case ProjectStatus.cancelled:
            sIcon = CupertinoIcons.xmark_circle_fill;
            sColor = Colors.redAccent;
            break;
        }
        // Gradient card to match owner list style
        final gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.55),
            cs.primary.withValues(alpha: 0.85),
          ],
        );
        final deadlineVal = p.financials['deadline'];
        final isLate = _isOverdueByDays(p, 1); // late if before today
        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Ink(
            decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () => _openDetails(context, p, tabbed: true),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(CupertinoIcons.building_2_fill, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            const SizedBox(width: 8),
                            Text('#${p.id}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70)),
                          ]),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            StatusChip(label: p.status.name, inverted: true, color: sColor, icon: sIcon),
                            if (p.phase > 0) StatusChip(label: 'Phase ${p.phase}', inverted: true, color: Colors.white70, icon: CupertinoIcons.number),
                            if (deadlineVal != null)
                              StatusChip(
                                label: 'Due ${_fmtShortDate(_deadlineOf(deadlineVal) ?? DateTime.now())}',
                                inverted: true,
                                color: isLate ? Colors.redAccent : Colors.white70,
                                icon: CupertinoIcons.calendar,
                              ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(CupertinoIcons.chevron_right, size: 18, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Filters + sort applied client-side over the unified stream
  List<Project> _applyFiltersAndSort(WidgetRef ref, List<Project> items, String search) {
  // Always work on a mutable copy; some sources return unmodifiable lists in web builds
  var filtered = List<Project>.from(items);
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = items.where((p) {
        final sarpanch = p.preliminaryDescription.sarpanchName?.toLowerCase() ?? '';
        final gram = p.preliminaryDescription.gramPanchayat?.toLowerCase() ?? '';
        final secretary = p.preliminaryDescription.secretaryName?.toLowerCase() ?? '';
        return p.name.toLowerCase().contains(q) ||
            p.blockId.toLowerCase().contains(q) ||
            sarpanch.contains(q) ||
            gram.contains(q) ||
            secretary.contains(q);
      }).toList();
    }
  final statusFilter = ref.read(nodalStatusFilterProvider);
    if (statusFilter != null) {
      filtered = filtered.where((p) => p.status == statusFilter).toList();
    }
    final days = ref.read(nodalOverdueDaysFilterProvider);
    if (days != null) {
      filtered = filtered.where((p) => _isOverdueByDays(p, days)).toList();
    }
    final stageFilter = ref.read(nodalStageFilterProvider);
    if (stageFilter != null && stageFilter.isNotEmpty) {
      filtered = filtered.where((p) {
        var stage = p.workDescription.stage?.name.toLowerCase() ?? 'unknown';
        if (p.status == ProjectStatus.completed) stage = 'completed';
        return stage == stageFilter;
      }).toList();
    }
    switch (ref.read(_sortProvider)) {
      case _SortBy.updatedDesc:
        filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case _SortBy.updatedAsc:
        filtered.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        break;
      case _SortBy.nameAsc:
        filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _SortBy.nameDesc:
        filtered.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case _SortBy.status:
        filtered.sort((a, b) => a.status.name.compareTo(b.status.name));
        break;
    }
    return filtered;
  }

  void _openDetails(BuildContext context, Project p, {bool tabbed = false}) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailPage(project: p, tabbed: tabbed)));
  }

  // Humanized updated time (kept for potential future use)
  // ignore: unused_element
  String _fmtWhen(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  // Picker sheets
  Future<ProjectStatus?> _pickStatus(BuildContext context) async {
    return showModalBottomSheet<ProjectStatus?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in ProjectStatus.values)
              ListTile(
                leading: Icon(
                  s == ProjectStatus.completed
                      ? Icons.check_circle
                      : s == ProjectStatus.in_progress
                          ? Icons.timelapse
                          : Icons.cancel,
                ),
                title: Text(s.name),
                onTap: () => Navigator.of(ctx).pop(s),
              ),
            ListTile(
              leading: const Icon(CupertinoIcons.clear_thick),
              title: const Text('Clear'),
              onTap: () => Navigator.of(ctx).pop(null),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _pickOverdueDays(BuildContext context) async {
    return showModalBottomSheet<int?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.calendar_badge_minus),
              title: const Text('Overdue 30 days'),
              onTap: () => Navigator.of(ctx).pop(30),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.calendar_badge_minus),
              title: const Text('Overdue 60 days'),
              onTap: () => Navigator.of(ctx).pop(60),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.clear_thick),
              title: const Text('Clear'),
              onTap: () => Navigator.of(ctx).pop(null),
            ),
          ],
        ),
      ),
    );
  }

  bool _isOverdueByDays(Project p, int days) {
    if (p.status == ProjectStatus.completed) return false;
    final d = parseAnyDate(p.financials['deadline']);
    if (d == null) return false;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final cutoff = startOfToday.subtract(Duration(days: days));
    return d.isBefore(cutoff);
  }

  DateTime? _deadlineOf(dynamic v) => parseAnyDate(v);

  Future<String?> _pickBlock(BuildContext context, WidgetRef ref) async {
    return showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final b in ref.read(blocksListProvider))
              ListTile(title: Text(b), onTap: () => Navigator.of(ctx).pop(b)),
            ListTile(
              leading: const Icon(CupertinoIcons.clear_thick),
              title: const Text('Clear'),
              onTap: () => Navigator.of(ctx).pop(null),
            ),
          ],
        ),
      ),
    );
  }

  void _openSortSheet(BuildContext context, WidgetRef ref) async {
    final current = ref.read(_sortProvider);
    final selected = await showModalBottomSheet<_SortBy>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sortTile(ctx, 'Newest', CupertinoIcons.sort_down, _SortBy.updatedDesc, current),
            _sortTile(ctx, 'Oldest', CupertinoIcons.sort_up, _SortBy.updatedAsc, current),
            _sortTile(ctx, 'A–Z', CupertinoIcons.textformat_abc, _SortBy.nameAsc, current),
            _sortTile(ctx, 'Z–A', CupertinoIcons.textformat_abc_dottedunderline, _SortBy.nameDesc, current),
            _sortTile(ctx, 'Status', CupertinoIcons.checkmark_seal, _SortBy.status, current),
          ],
        ),
      ),
    );
    if (selected != null) {
      ref.read(_sortProvider.notifier).state = selected;
  _resetPagination(ref);
    }
  }

  ListTile _sortTile(BuildContext ctx, String title, IconData icon, _SortBy value, _SortBy current) {
    final selected = value == current;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: selected ? const Icon(CupertinoIcons.check_mark) : null,
      onTap: () => Navigator.of(ctx).pop(value),
    );
  }

  // Small active indicator dot
  Widget _withDot({required bool active, required Widget child}) {
    if (!active) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ],
    );
  }
}

/// Container used to provide consistent padding around list & empty states.
class _ListContainer extends StatelessWidget {
  final Widget child;
  const _ListContainer({required this.child});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: child,
    );
  }
}

class _NoResultsScoped extends StatelessWidget {
  final bool hasAny;
  final bool isSearching;
  const _NoResultsScoped({required this.hasAny, required this.isSearching});
  @override
  Widget build(BuildContext context) {
    if (!hasAny) {
      return const Center(child: NoData(message: 'No projects yet', asset: 'assets/no_projects.svg'));
    }
    if (isSearching) {
      return const Center(child: NoData(message: 'No matching projects', asset: 'assets/search_projects.svg'));
    }
    return const Center(child: NoData(message: 'No projects', asset: 'assets/no_projects.svg'));
  }
}

class _ActiveFiltersBar extends ConsumerWidget {
  final VoidCallback onClearAll;
  const _ActiveFiltersBar({required this.onClearAll});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(nodalStatusFilterProvider);
    final overdue = ref.watch(nodalOverdueDaysFilterProvider);
    final block = ref.watch(blockFilterProvider);
    final stage = ref.watch(nodalStageFilterProvider);
  final gp = ref.watch(gramPanchayatFilterProvider);
    final chips = <Widget>[];
    void add(String label, VoidCallback onRemove) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 4),
        child: InputChip(label: Text(label), onDeleted: onRemove),
      ));
    }
    if (status != null) {
      add('Status: ${status.name}', () => ref.read(nodalStatusFilterProvider.notifier).state = null);
    }
    if (overdue != null) {
      add('Overdue: $overdue d', () => ref.read(nodalOverdueDaysFilterProvider.notifier).state = null);
    }
    if (block != null && block.isNotEmpty) {
      add('Block: $block', () => ref.read(blockFilterProvider.notifier).state = null);
    }
    if (gp != null && gp.isNotEmpty) {
      add('Gram Panchayat: ${_titleCase(gp)}', () => ref.read(gramPanchayatFilterProvider.notifier).state = null);
    }
    if (stage != null && stage.isNotEmpty) {
      add('Stage: $stage', () => ref.read(nodalStageFilterProvider.notifier).state = null);
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        children: [
          ...chips,
          TextButton(onPressed: onClearAll, child: const Text('Clear all')),
        ],
      ),
    );
  }

  String _titleCase(String input) {
    return input
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
        .join(' ');
  }
}

// Small location badge with icon and ellipsis-safe label.
// Removed unused _LocBadge and _MiniChip (legacy visual experiments) to reduce lint noise.

String _fmtShortDate(DateTime d) => '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}';
