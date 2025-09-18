import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:printing/printing.dart';
import 'package:flutter/cupertino.dart';
import 'package:animations/animations.dart';
import '../../../shared/widgets/app_sidebar.dart';
import '../../../shared/ui/toast.dart';
import '../../../shared/utils/file_open_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xls;
import '../../auth/data/auth_repository.dart';
import '../../../services/functions_service.dart';
import '../../projects/presentation/project_edit_page.dart' as editor;
// Admin pages use the global app theme; removed custom AdminTheme for consistency
import '../../../shared/widgets/no_data.dart';
import '../../../shared/widgets/scroll_safe_dialog.dart';
import '../../../shared/ui/progress.dart';

class ProdAdminDashboardPage extends ConsumerStatefulWidget {
  const ProdAdminDashboardPage({super.key});

  @override
  ConsumerState<ProdAdminDashboardPage> createState() => _ProdAdminDashboardPageState();
}

class _ProdAdminDashboardPageState extends ConsumerState<ProdAdminDashboardPage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _sideIndex = 0;
  bool _sidebarOpen = false;
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
  // 3 tabs: Dashboard, Users, Projects (Profile removed for dev_admin)
  _tab = TabController(length: 3, vsync: this);
    _sideIndex = _tab.index;
    _tab.addListener(() {
      if (_sideIndex != _tab.index) {
        setState(() => _sideIndex = _tab.index);
      }
    });
    // Ensure dev_admin claims for whitelisted admin and refresh token (fixes Firestore rule 400s on web)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final appUser = ref.read(authStateProvider).value;
        if (appUser != null && appUser.role.key == 'dev_admin') {
          await ref.read(functionsServiceProvider).ensureDevAdminForWhitelisted();
          await fb.FirebaseAuth.instance.currentUser?.getIdToken(true);
          if (mounted) setState(() {});
        }
      } catch (_) {
        // ignore if not whitelisted or already has claims
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
  final isCompact = MediaQuery.of(context).size.width < 900;
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              if (!isCompact) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  width: _sidebarCollapsed ? 72 : 256,
                  child: AppSidebar(
                    selectedIndex: _sideIndex,
                    collapsed: _sidebarCollapsed,
                    onSelect: (i) => setState(() { _sideIndex = i; _tab.index = i; }),
                  ),
                ),
                // Remove divider entirely per updated sidebar design
              ],
              Expanded(
                child: Column(
                  children: [
                    // Top utility bar (no title) with sidebar/menu controls only
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          if (isCompact)
                            IconButton(
                              icon: const Icon(CupertinoIcons.bars),
                              tooltip: 'Menu',
                              onPressed: () => setState(() => _sidebarOpen = true),
                            )
                          else
                            IconButton(
                              icon: Icon(_sidebarCollapsed ? CupertinoIcons.sidebar_right : CupertinoIcons.sidebar_left),
                              tooltip: _sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
                              onPressed: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
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
                          children: const [
                            _AdminStatsTab(),
                            _ManageUsersTab(),
                            _ManageProjectsTab(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    );
  }
}

void _showSnack(BuildContext context, String message, {IconData icon = CupertinoIcons.info, bool error = false}) =>
  showToast(context, message, icon: icon, error: error);

// Replaced custom _AdminSidebar with SidebarX

// Top bar removed; header icons are not needed.


class _AdminStatsTab extends ConsumerWidget {
  const _AdminStatsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('projects').snapshots(),
      builder: (context, snap) {
        final docs = (snap.hasData) ? snap.data!.docs : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final total = docs.length;
        final completed = docs.where((d) => d.data()['status'] == 'completed').length;
        final inProgress = docs.where((d) => d.data()['status'] == 'in_progress').length;
        final cancelled = docs.where((d) => d.data()['status'] == 'cancelled').length;

        return LayoutBuilder(
          builder: (context, c) {
            final isWide = c.maxWidth > 900;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 12, vertical: 12),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Charts removed per requirement; keep a single consolidated stats section
                  StreamBuilder(
                    stream: FirebaseFirestore.instance.collection('users').snapshots(),
                    builder: (context, usnap) {
                      final u = (usnap.hasData) ? (usnap.data as QuerySnapshot<Map<String, dynamic>>).docs : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                      // final uTotal = u.length; // excluded dev_admin from totals below
                      final owners = u.where((d)=> d.data()['role'] == 'project_owner').length;
                      final nodals = u.where((d)=> d.data()['role'] == 'sub_nodal').length;
                      final supers = u.where((d)=> d.data()['role'] == 'super_nodal').length;
          // Exclude dev_admin from totals
          final nonAdmins = u.where((d) => (d.data()['role'] as String?) != 'dev_admin').toList();
          return LayoutBuilder(builder: (ctx, lc) {
            final w = lc.maxWidth;
            final gap = isWide ? 12.0 : 8.0;
            final cols = w > 1280 ? 4 : w > 960 ? 3 : w > 640 ? 2 : 1;
            final tileW = (w - (gap * (cols - 1))) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                _BentoMetricTile(label: 'Total Projects', value: total, color: Colors.blue, icon: CupertinoIcons.folder, width: tileW),
                _BentoMetricTile(label: 'In Progress', value: inProgress, color: Colors.orange, icon: CupertinoIcons.arrow_2_circlepath, width: tileW),
                _BentoMetricTile(label: 'Completed', value: completed, color: Colors.green, icon: CupertinoIcons.check_mark_circled, width: tileW),
                _BentoMetricTile(label: 'Cancelled', value: cancelled, color: Colors.redAccent, icon: CupertinoIcons.xmark_octagon, width: tileW),
                _BentoMetricTile(label: 'Total Users', value: nonAdmins.length, color: Colors.cyan, icon: CupertinoIcons.group, width: tileW),
                _BentoMetricTile(label: 'Owners', value: owners, color: Colors.teal, icon: CupertinoIcons.person_crop_rectangle, width: tileW),
                _BentoMetricTile(label: 'Nodals', value: nodals, color: Colors.indigo, icon: CupertinoIcons.tree, width: tileW),
                _BentoMetricTile(label: 'Super Nodals', value: supers, color: Colors.purple, icon: CupertinoIcons.check_mark_circled, width: tileW),
              ],
            );
          });
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _BentoMetricTile extends StatefulWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final double width;
  const _BentoMetricTile({required this.label, required this.value, required this.color, required this.icon, required this.width});

  @override
  State<_BentoMetricTile> createState() => _BentoMetricTileState();
}

class _BentoMetricTileState extends State<_BentoMetricTile> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: _hover ? 1.02 : 1.0,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: widget.color.withValues(alpha: 0.18))),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [widget.color.withValues(alpha: 0.12), widget.color.withValues(alpha: 0.04)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(widget.icon, color: widget.color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.label),
                        const SizedBox(height: 6),
                        Text('${widget.value}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ManageUsersTab extends ConsumerWidget {
  const _ManageUsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = FirebaseFirestore.instance;
  final fns = ref.read(functionsServiceProvider);
  return _UsersTabContent(db: db, fns: fns);
  }
}

class _ManageProjectsTab extends StatelessWidget {
  const _ManageProjectsTab();

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return _ProjectsTabContent(db: db);
  }
}

// --- Users Tab Content ---
class _UsersTabContent extends StatefulWidget {
  final FirebaseFirestore db;
  final FunctionsService fns;
  const _UsersTabContent({required this.db, required this.fns});

  @override
  State<_UsersTabContent> createState() => _UsersTabContentState();
}

class _UsersTabContentState extends State<_UsersTabContent> {
  bool grid = false;
  final selected = <String>{};
  String search = '';
  Timer? _searchDebounce;

  @override
  Widget build(BuildContext context) {
    final q = widget.db.collection('users').orderBy('createdAt', descending: true);
    return Column(
      children: [
        PageTransitionSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, a, sa) => FadeThroughTransition(animation: a, secondaryAnimation: sa, child: child),
          child: _UsersToolbar(
          grid: grid,
          selectedCount: selected.length,
          onToggleView: () => setState(() => grid = !grid),
          onSearch: (v) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 300), () {
              if (!mounted) return;
              setState(() => search = v.trim().toLowerCase());
            });
          },
          onBulkDelete: selected.isEmpty ? null : () async {
            final ids = selected.toList();
            final confirm = await showScrollSafeDialog<bool>(
              context: context,
              builder: (ctx) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Delete selected users?', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  const Text('This will remove users from Firebase Auth and Firestore.'),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      const SizedBox(width: 8),
                      FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(CupertinoIcons.delete), label: const Text('Delete')),
                    ],
                  )
                ],
              ),
            );
            if (confirm != true) return;
            if (!context.mounted) return;
            try {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const AlertDialog(
                  content: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(height: 20, width: 20, child: AppLoadingIndicator(size: 20)), 
                      SizedBox(width: 12),
                      Text('Deleting users…'),
                    ]),
                  ),
                ),
              );
              final nav = Navigator.of(context, rootNavigator: true);
              final results = await widget.fns.adminBulkDeleteUsers(ids);
              if (!context.mounted) return;
              nav.pop();
              final ok = results.where((r) => r['ok'] == true).length;
              final fail = results.length - ok;
              if (!context.mounted) return;
              _showSnack(context, 'Deleted: $ok ok, $fail failed', icon: CupertinoIcons.delete, error: fail > 0);
            } catch (e) {
              if (!context.mounted) return;
              // Pop progress dialog if visible
              Navigator.of(context, rootNavigator: true).maybePop();
              if (!context.mounted) return;
              _showSnack(context, 'Bulk delete failed: $e', icon: CupertinoIcons.exclamationmark_triangle, error: true);
            } finally {
              if (mounted) setState(() => selected.clear());
            }
          },
          onCreateSingle: () => _createSingleUser(context),
          onCreateBulk: () => _showBulkInfo(context),
          ),
        ),
  Divider(height: 1, color: Theme.of(context).dividerColor),
        Expanded(
          child: StreamBuilder(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: AppLoadingIndicator());
              }
              if (!snap.hasData) return const NoData(message: 'No data');
              var docs = (snap.data as QuerySnapshot<Map<String, dynamic>>).docs;
              if (search.isNotEmpty) {
                docs = docs.where((d) {
                  final e = (d.data()['email'] as String? ?? '').toLowerCase();
                  final n = (d.data()['displayName'] as String? ?? '').toLowerCase();
                  return e.contains(search) || n.contains(search);
                }).toList();
              }
              if (docs.isEmpty) return const _EmptyState(message: 'No users');
              final listWidget = grid
                  ? GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 420, childAspectRatio: 3.2, crossAxisSpacing: 8, mainAxisSpacing: 8),
                      itemCount: docs.length,
                      itemBuilder: (context, i) => _UserTile(
                        doc: docs[i],
                        selected: selected.contains(docs[i].id),
                        onTap: () => _openUser(context, docs[i]),
                        onSelectToggle: () => setState(() {
                          final id = docs[i].id; if (selected.contains(id)) {
                            selected.remove(id);
                          } else {
                            selected.add(id);
                          }
                        }),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: docs.length,
                      itemBuilder: (context, i) => _UserRow(
                        doc: docs[i],
                        selected: selected.contains(docs[i].id),
                        onTap: () => _openUser(context, docs[i]),
                        onSelectToggle: () => setState(() {
                          final id = docs[i].id; if (selected.contains(id)) {
                            selected.remove(id);
                          } else {
                            selected.add(id);
                          }
                        }),
                      ),
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                    );
              return PageTransitionSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, a, sa) => FadeThroughTransition(animation: a, secondaryAnimation: sa, child: child),
                child: KeyedSubtree(key: ValueKey('users_${grid ? 'grid' : 'list'}_${docs.length}_$search'), child: listWidget),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _showBulkInfo(BuildContext context) async {
    final proceed = await showScrollSafeDialog<bool>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bulk Create Users', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const Text('Prepare a CSV or Excel file with the following columns:'),
          const SizedBox(height: 8),
          const _Bullet(text: 'email *'),
          const _Bullet(text: 'role (optional: project_owner, super_nodal, sub_nodal; defaults to project_owner)'),
          const _Bullet(text: 'block (required for project_owner and sub_nodal; one of: dhamtari, kurud, magarload, nagri)'),
          const SizedBox(height: 12),
          const Text('Notes:'),
          const SizedBox(height: 6),
          const _Bullet(text: 'Passwords are auto-generated and added back to your file in a generated_password column.'),
          const _Bullet(text: 'Each row will get status and message columns indicating success or any error.'),
          const _Bullet(text: 'Rows missing required block for project_owner or sub_nodal are skipped.'),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(CupertinoIcons.square_stack_3d_up), label: const Text('Pick file')),
            ],
          ),
        ],
      ),
    );
    if (proceed == true) {
      if (!context.mounted) return;
      await _createBulkUsers(context);
    }
  }

  Future<void> _openUser(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d) async {
    await showDialog(context: context, builder: (_) => _UserDialog(doc: d, db: widget.db, fns: widget.fns));
  }

  String _genPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789@#%&';
    final rnd = Random.secure();
    return List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _createSingleUser(BuildContext context) async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String roleCategory = 'project_owner';
    String nodalType = 'super_nodal';
    const blockOptions = ['dhamtari', 'kurud', 'magarload', 'nagri'];
    String? selectedBlock;
    String? genPass;
    bool createdOk = false;
    bool creating = false;

    await showScrollSafeDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget fieldSpacing() => const SizedBox(height: 12);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create User', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              fieldSpacing(),
              if (creating) const LinearProgressIndicator(minHeight: 3),
              if (creating) const SizedBox(height: 12),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
              fieldSpacing(),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              fieldSpacing(),
              Align(alignment: Alignment.centerLeft, child: Text('Role', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF9A9A9A)))),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: roleCategory,
                decoration: const InputDecoration(labelText: 'User type'),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'project_owner', child: Text('Project Owner')),
                  DropdownMenuItem(value: 'nodal_officer', child: Text('Nodal Officer')),
                ],
                onChanged: (v) => setLocal(() => roleCategory = v ?? 'project_owner'),
              ),
              if (roleCategory == 'nodal_officer') ...[
                fieldSpacing(),
                Align(alignment: Alignment.centerLeft, child: Text('Nodal type', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF9A9A9A)))),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: nodalType,
                  decoration: const InputDecoration(labelText: 'Nodal type'),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'super_nodal', child: Text('Super Nodal')),
                    DropdownMenuItem(value: 'sub_nodal', child: Text('Sub Nodal')),
                  ],
                  onChanged: (v) => setLocal(() => nodalType = v ?? 'super_nodal'),
                ),
              ],
              if (roleCategory == 'project_owner' || (roleCategory == 'nodal_officer' && nodalType == 'sub_nodal')) ...[
                fieldSpacing(),
                Align(alignment: Alignment.centerLeft, child: Text('Block', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF9A9A9A)))),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedBlock,
                  decoration: const InputDecoration(labelText: 'Block'),
                  isExpanded: true,
                  items: [
                    ...blockOptions.map((b) => DropdownMenuItem(value: b, child: Text(b[0].toUpperCase() + b.substring(1))))
                  ],
                  onChanged: (v) => setLocal(() => selectedBlock = v),
                ),
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: Text('Required for Project Owner and Sub Nodal', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF9A9A9A)))),
              ],
              if (createdOk && genPass != null) ...[
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Credentials', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Row(children: [const Icon(CupertinoIcons.envelope, size: 16), const SizedBox(width: 6), Expanded(child: Text(emailCtrl.text.trim(), overflow: TextOverflow.ellipsis))]),
                        const SizedBox(height: 6),
                        Row(children: [const Icon(CupertinoIcons.lock, size: 16), const SizedBox(width: 6), Expanded(child: SelectableText(genPass!))]),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          Chip(label: Text('Role: ${roleCategory == 'nodal_officer' ? nodalType : 'project_owner'}')),
                          if (selectedBlock != null) Chip(label: Text('Block: ${selectedBlock![0].toUpperCase()}${selectedBlock!.substring(1)}')),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                  TextButton(
                    onPressed: () async {
                      if (creating) return;
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty) return;
                      final displayName = nameCtrl.text.trim();
                      final roleToUse = roleCategory == 'nodal_officer' ? nodalType : 'project_owner';
                      final needsBlock = roleToUse == 'project_owner' || roleToUse == 'sub_nodal';
                      if (needsBlock && (selectedBlock == null || selectedBlock!.isEmpty)) {
                        if (context.mounted) _showSnack(context, 'Please select a block', icon: CupertinoIcons.exclamationmark_triangle, error: true);
                        return;
                      }
                      genPass = _genPassword();
                      try {
                        setLocal(() => creating = true);
                        final created = await widget.fns.createAuthUser(
                          email: email,
                          password: genPass!,
                          role: roleToUse,
                          displayName: displayName,
                          blockId: (selectedBlock != null && selectedBlock!.isNotEmpty) ? selectedBlock! : null,
                        );
                        final uid = created['uid'] as String?;
                        if (uid != null && uid.isNotEmpty) {
                          createdOk = true;
                          if (selectedBlock != null && (roleToUse == 'project_owner' || roleToUse == 'sub_nodal')) {
                            await widget.db.collection('users').doc(uid).set({'blockId': selectedBlock}, SetOptions(merge: true));
                          }
                          if (context.mounted) _showSnack(context, 'User created', icon: Icons.check_circle_outline);
                        }
                      } catch (e) {
                        if (context.mounted) _showSnack(context, 'Create failed: $e', icon: Icons.error_outline, error: true);
                      } finally {
                        setLocal(() => creating = false);
                      }
                    },
                    child: creating
                        ? const Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(height: 16, width: 16, child: AppLoadingIndicator(size: 16)), SizedBox(width: 8), Text('Creating…')])
                        : const Text('Create'),
                  ),
                  if (createdOk && genPass != null) ...[
                    TextButton(
                      onPressed: () async {
                        final email = emailCtrl.text.trim();
                        await Clipboard.setData(ClipboardData(text: 'Email: $email\nPassword: $genPass'));
                        if (!ctx.mounted) return;
                        _showSnack(ctx, 'Copied', icon: Icons.copy_all_outlined);
                      },
                      child: const Text('Copy'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _exportCredentials(emailCtrl.text.trim(), genPass!, toPdf: false);
                        if (!mounted) return;
                      },
                      child: const Text('Export TXT'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _exportCredentials(emailCtrl.text.trim(), genPass!, toPdf: true);
                        if (!mounted) return;
                      },
                      child: const Text('Export PDF'),
                    ),
                    FilledButton.tonal(
                      onPressed: () {
                        setLocal(() {
                          emailCtrl.clear();
                          nameCtrl.clear();
                          roleCategory = 'project_owner';
                          nodalType = 'super_nodal';
                          selectedBlock = null;
                          genPass = null;
                          createdOk = false;
                        });
                      },
                      child: const Text('Create another'),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportCredentials(String email, String password, {required bool toPdf}) async {
    final content = 'Email: $email\nPassword: $password\n';
    if (!toPdf) {
      final bytes = utf8.encode(content);
      try {
        await FileOpenHelper.saveAndOpen(bytes: bytes, fileName: 'credentials_$email.txt');
      } catch (_) {
        // Fallback for Web/unsupported
        await FileSaver.instance.saveFile(name: 'credentials_$email', bytes: bytes, ext: 'txt', mimeType: MimeType.text);
      }
    } else {
      final doc = pw.Document();
      doc.addPage(pw.Page(build: (c) => pw.Center(child: pw.Text(content))));
      final bytes = await doc.save();
      try {
        await FileOpenHelper.saveAndOpen(bytes: bytes, fileName: 'credentials_$email.pdf');
      } catch (_) {
        // Fallback share if native open/save not available (e.g., Web)
        await Printing.sharePdf(bytes: bytes, filename: 'credentials_$email.pdf');
      }
    }
  }

  Future<void> _createBulkUsers(BuildContext context) async {
    // Pick a CSV or Excel file, generate passwords, write back an added column and return file.
  final result = await FilePicker.platform.pickFiles(type: FileType.custom, withData: true, allowedExtensions: ['csv', 'xlsx', 'xls']);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final name = file.name;
    final ext = name.split('.').last.toLowerCase();
    try {
      if (ext == 'csv') {
        final content = utf8.decode(file.bytes ?? []);
        final rows = const CsvToListConverter().convert(content);
        if (rows.isEmpty) return;
        final header = rows.first.map((e) => e.toString()).toList();
        int emailIdx = header.indexWhere((h) => h.toLowerCase() == 'emails' || h.toLowerCase() == 'email');
        final roleIdx = header.indexWhere((h) => h.toLowerCase() == 'role' || h.toLowerCase() == 'roles');
        final blockIdx = header.indexWhere((h) => h.toLowerCase() == 'block' || h.toLowerCase() == 'blocks');
        if (emailIdx < 0) {
          if (context.mounted) _showSnack(context, 'CSV must have an "emails" column', icon: Icons.error_outline, error: true);
          return;
        }
        final out = <List<dynamic>>[];
  final payload = <Map<String, dynamic>>[];
        final newHeader = List<String>.from(header);
        newHeader.add('generated_password');
        newHeader.add('status');
        newHeader.add('message');
        out.add(newHeader);
        final payloadRowPositions = <int>[]; // indices in 'out' that correspond to payload entries
        for (var i = 1; i < rows.length; i++) {
          final row = List<dynamic>.from(rows[i]);
          final email = row[emailIdx]?.toString().trim() ?? '';
          if (email.isEmpty) continue;
          final pass = _genPassword();
          final roleRaw = roleIdx >= 0 ? (row[roleIdx]?.toString().trim().toLowerCase() ?? '') : '';
          final role = roleRaw.isNotEmpty ? roleRaw : 'project_owner';
          final block = blockIdx >= 0 ? (row[blockIdx]?.toString().trim().toLowerCase() ?? '') : '';
          final needsBlock = role == 'project_owner' || role == 'sub_nodal';
          row.add(pass);
          // placeholders for status & message
          String status = 'pending';
          String message = '';
          if (needsBlock && block.isEmpty) {
            status = 'skipped';
            message = 'block required for $role';
            out.add([...row, status, message]);
            continue;
          }
          out.add([...row, status, message]);
          final entry = <String, dynamic>{'email': email, 'password': pass, 'role': role};
          if (block.isNotEmpty) entry['blockId'] = block;
          payload.add(entry);
          payloadRowPositions.add(out.length - 1);
        }
        // Call bulk create Auth users
        try {
          // Show progress dialog
          if (!context.mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const AlertDialog(
              content: Padding(
                padding: EdgeInsets.all(12.0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(height: 20, width: 20, child: AppLoadingIndicator(size: 20)), 
                  SizedBox(width: 12),
                  Text('Creating users…'),
                ]),
              ),
            ),
          );
          final nav = Navigator.of(context, rootNavigator: true);
          final results = await widget.fns.bulkCreateAuthUsers(payload);
          if (!context.mounted) return;
          nav.pop();
          final ok = results.where((r) => r['ok'] == true).length;
          final fail = results.length - ok;
          // annotate rows with results
          for (var j = 0; j < results.length && j < payloadRowPositions.length; j++) {
            final r = results[j];
            final idx = payloadRowPositions[j];
            final row = out[idx];
            row[row.length - 2] = (r['ok'] == true) ? 'ok' : 'error';
            row[row.length - 1] = r['error']?.toString() ?? '';
          }
          if (!context.mounted) return;
          _showSnack(context, 'Bulk: $ok ok, $fail failed', icon: Icons.file_upload_outlined);
        } catch (e) {
          if (!context.mounted) return;
          // progress dialog may still be open
          Navigator.of(context, rootNavigator: true).maybePop();
          if (!context.mounted) return;
          _showSnack(context, 'Bulk failed: $e', icon: Icons.error_outline, error: true);
        }
        final csvOut = const ListToCsvConverter().convert(out);
        final bytes = utf8.encode(csvOut);
        try {
          await FileOpenHelper.saveAndOpen(bytes: bytes, fileName: 'bulk_credentials.csv');
        } catch (_) {
          await FileSaver.instance.saveFile(name: 'bulk_credentials', bytes: bytes, ext: 'csv', mimeType: MimeType.csv);
        }
      } else if (ext == 'xlsx') {
        if (file.bytes == null) return;
        final book = xls.Excel.decodeBytes(file.bytes!);
        if (book.tables.isEmpty) {
          if (context.mounted) _showSnack(context, 'No sheets found in workbook', icon: Icons.error_outline, error: true);
          return;
        }
        final sheetName = book.tables.keys.first;
        final sheet = book.tables[sheetName]!;
        if (sheet.rows.isEmpty) {
          if (context.mounted) _showSnack(context, 'Sheet is empty', icon: Icons.error_outline, error: true);
          return;
        }
        final header = sheet.rows.first.map((c) => (c?.value ?? '').toString()).toList();
        int emailIdx = header.indexWhere((h) => h.toLowerCase() == 'emails' || h.toLowerCase() == 'email');
        int roleIdx = header.indexWhere((h) => h.toLowerCase() == 'role' || h.toLowerCase() == 'roles');
        int blockIdx = header.indexWhere((h) => h.toLowerCase() == 'block' || h.toLowerCase() == 'blocks');
        if (emailIdx < 0) {
          if (context.mounted) _showSnack(context, 'Sheet must have an "emails" column', icon: Icons.error_outline, error: true);
          return;
        }
        int pwdIdx = header.indexWhere((h) => h.toLowerCase() == 'generated_password');
        if (pwdIdx < 0) {
          pwdIdx = header.length;
          sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: pwdIdx, rowIndex: 0)).value = xls.TextCellValue('generated_password');
        }
        int statusIdx = header.indexWhere((h) => h.toLowerCase() == 'status');
        if (statusIdx < 0) {
          statusIdx = (pwdIdx + 1);
          sheet.insertColumn(statusIdx);
          sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: statusIdx, rowIndex: 0)).value = xls.TextCellValue('status');
        }
        int messageIdx = header.indexWhere((h) => h.toLowerCase() == 'message');
        if (messageIdx < 0) {
          messageIdx = (statusIdx + 1);
          sheet.insertColumn(messageIdx);
          sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: messageIdx, rowIndex: 0)).value = xls.TextCellValue('message');
        }
  final payload = <Map<String, dynamic>>[];
        final payloadRowIndices = <int>[]; // excel row indices for payload
        for (var i = 1; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          final email = ((row.length > emailIdx ? row[emailIdx]?.value : '') ?? '').toString().trim();
          if (email.isEmpty) continue;
          final pass = _genPassword();
          sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: pwdIdx, rowIndex: i)).value = xls.TextCellValue(pass);
          final role = (roleIdx >= 0 && row.length > roleIdx)
              ? (row[roleIdx]?.value?.toString().trim().toLowerCase() ?? 'project_owner')
              : 'project_owner';
          final block = (blockIdx >= 0 && row.length > blockIdx) ? (row[blockIdx]?.value?.toString().trim().toLowerCase() ?? '') : '';
          final needsBlock = role == 'project_owner' || role == 'sub_nodal';
          if (needsBlock && block.isEmpty) {
            sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: statusIdx, rowIndex: i)).value = xls.TextCellValue('skipped');
            sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: messageIdx, rowIndex: i)).value = xls.TextCellValue('block required for $role');
            continue;
          }
          final entry = <String, dynamic>{'email': email, 'password': pass, 'role': role};
          if (block.isNotEmpty) entry['blockId'] = block;
          payload.add(entry);
          payloadRowIndices.add(i);
        }
        // Bulk create via function
        try {
          if (!context.mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const AlertDialog(
              content: Padding(
                padding: EdgeInsets.all(12.0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(height: 20, width: 20, child: AppLoadingIndicator(size: 20)), 
                  SizedBox(width: 12),
                  Text('Creating users…'),
                ]),
              ),
            ),
          );
          final nav = Navigator.of(context, rootNavigator: true);
          final results = await widget.fns.bulkCreateAuthUsers(payload);
          if (!context.mounted) return;
          nav.pop();
          final ok = results.where((r) => r['ok'] == true).length;
          final fail = results.length - ok;
          for (var j = 0; j < results.length && j < payloadRowIndices.length; j++) {
            final r = results[j];
            final rowIdx = payloadRowIndices[j];
            sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: statusIdx, rowIndex: rowIdx)).value = xls.TextCellValue((r['ok'] == true) ? 'ok' : 'error');
            sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: messageIdx, rowIndex: rowIdx)).value = xls.TextCellValue(r['error']?.toString() ?? '');
          }
          if (!context.mounted) return;
          _showSnack(context, 'Bulk: $ok ok, $fail failed', icon: Icons.file_upload_outlined);
        } catch (e) {
          if (!context.mounted) return;
          Navigator.of(context, rootNavigator: true).maybePop();
          if (!context.mounted) return;
          _showSnack(context, 'Bulk failed: $e', icon: Icons.error_outline, error: true);
        }
        final outBytes = book.encode();
        if (outBytes != null) {
          try {
            await FileOpenHelper.saveAndOpen(bytes: outBytes, fileName: 'bulk_credentials.xlsx');
          } catch (_) {
            await FileSaver.instance.saveFile(
              name: 'bulk_credentials',
              bytes: Uint8List.fromList(outBytes),
              ext: 'xlsx',
              mimeType: MimeType.other,
            );
          }
        }
      } else if (ext == 'xls') {
        if (context.mounted) { _showSnack(context, 'Legacy .xls is not supported. Please convert to .xlsx or .csv', icon: Icons.error_outline); }
        return;
      } else {
        if (context.mounted) { _showSnack(context, 'Unsupported file type: .$ext', icon: Icons.error_outline); }
        return;
      }
      if (context.mounted) _showSnack(context, 'Bulk processed', icon: Icons.check_circle_outline);
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Failed: $e', icon: Icons.error_outline, error: true);
    }
  }
}

class _UsersToolbar extends StatelessWidget {
  final bool grid;
  final int selectedCount;
  final VoidCallback onToggleView;
  final ValueChanged<String> onSearch;
  final VoidCallback? onBulkDelete;
  final VoidCallback onCreateSingle;
  final VoidCallback onCreateBulk;
  const _UsersToolbar({
    required this.grid,
    required this.selectedCount,
    required this.onToggleView,
    required this.onSearch,
    required this.onBulkDelete,
    required this.onCreateSingle,
    required this.onCreateBulk,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 0),
          child: Row(children: [
            Tooltip(message: grid ? 'List view' : 'Grid view', child: IconButton(onPressed: onToggleView, icon: Icon(grid ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2))),
            const SizedBox(width: 8),
            SizedBox(
              width: 360,
              child: TextField(
                textAlignVertical: TextAlignVertical.center,
                onChanged: onSearch,
                decoration: const InputDecoration(hintText: 'Search users', prefixIcon: Icon(CupertinoIcons.search)),
              ),
            ),
            const SizedBox(width: 8),
            if (selectedCount > 0) Text('$selectedCount selected'),
            const SizedBox(width: 8),
            Tooltip(message: 'Delete selected', child: IconButton(onPressed: onBulkDelete, icon: const Icon(CupertinoIcons.delete)) ),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: onCreateSingle, icon: const Icon(CupertinoIcons.person_crop_circle_badge_plus), label: const Text('Create User')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: onCreateBulk, icon: const Icon(CupertinoIcons.square_stack_3d_up), label: const Text('Bulk Create')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final rows = [
                  ['email', 'role', 'block'],
                  ['po1@example.com', 'project_owner', 'dhamtari'],
                  ['sn1@example.com', 'super_nodal', ''],
                  ['sub1@example.com', 'sub_nodal', 'kurud'],
                ];
                final csvOut = const ListToCsvConverter().convert(rows);
                final bytes = utf8.encode(csvOut);
                try {
                  await FileOpenHelper.saveAndOpen(bytes: bytes, fileName: 'sample_users.csv');
                } catch (_) {
                  await FileSaver.instance.saveFile(name: 'sample_users', bytes: bytes, ext: 'csv', mimeType: MimeType.csv);
                }
                if (!context.mounted) return;
                _showSnack(context, 'Sample CSV saved', icon: CupertinoIcons.square_arrow_down_on_square);
              },
              icon: const Icon(CupertinoIcons.square_arrow_down),
              label: const Text('Sample CSV'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onTap;
  final VoidCallback onSelectToggle;
  final bool selected;
  const _UserRow({required this.doc, required this.onTap, required this.onSelectToggle, required this.selected});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
  final role = (data['role'] as String?) ?? 'project_owner';
  final blockId = (data['blockId'] as String?) ?? '';
  final email = (data['email'] as String?) ?? '';
  final display = (data['displayName'] as String?) ?? email;
  final initial = ((display.trim().isNotEmpty ? display.trim() : email).characters.first.toUpperCase());
    return ListTile(
      onTap: onTap,
      leading: Row(mainAxisSize: MainAxisSize.min, children:[
        Checkbox(value: selected, onChanged: (_) => onSelectToggle()),
        const SizedBox(width: 6),
  CircleAvatar(
          radius: 16,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            initial,
            textAlign: TextAlign.center,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: true,
              applyHeightToLastDescent: true,
              leadingDistribution: TextLeadingDistribution.even,
            ),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
              height: 1.0,
              leadingDistribution: TextLeadingDistribution.even,
              textBaseline: TextBaseline.alphabetic,
            ),
          )),
      ]),
      title: Row(children:[
  const Icon(CupertinoIcons.person, size: 16), const SizedBox(width: 6),
        Expanded(child: Text(display, overflow: TextOverflow.ellipsis)),
      ]),
      subtitle: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children:[const Icon(CupertinoIcons.envelope, size: 14), const SizedBox(width: 4), Text(email)]),
          Row(mainAxisSize: MainAxisSize.min, children:[Icon(_roleIcon(role), size: 14, color: _roleColor(role)), const SizedBox(width: 4), Text(role)]),
          if (blockId.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children:[const Icon(CupertinoIcons.square_grid_2x2, size: 14), const SizedBox(width: 4), Text(blockId, overflow: TextOverflow.ellipsis)]),
        ],
      ),
  trailing: const Icon(CupertinoIcons.chevron_right),
    );
  }
}

class _UserTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onTap;
  final VoidCallback onSelectToggle;
  final bool selected;
  const _UserTile({required this.doc, required this.onTap, required this.onSelectToggle, required this.selected});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
  final role = (data['role'] as String?) ?? 'project_owner';
  final email = (data['email'] as String?) ?? '';
  final display = (data['displayName'] as String?) ?? email;
  final initial = ((display.trim().isNotEmpty ? display.trim() : email).characters.first.toUpperCase());
    return InkWell(
      onTap: onTap,
      child: Card(
        elevation: 0,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(value: selected, onChanged: (_) => onSelectToggle()),
                  const SizedBox(width: 8),
                  CircleAvatar(
                      radius: 20,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        initial,
                        textAlign: TextAlign.center,
                        textHeightBehavior: const TextHeightBehavior(
                          applyHeightToFirstAscent: true,
                          applyHeightToLastDescent: true,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          leadingDistribution: TextLeadingDistribution.even,
                          textBaseline: TextBaseline.alphabetic,
                        ),
                      )),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(CupertinoIcons.person, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            (data['displayName'] ?? email) as String,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(_roleIcon(role), size: 14, color: _roleColor(role)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _roleColor(role).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: _roleColor(role).withValues(alpha: 0.24)),
                          ),
                          child: Text(
                            role,
                            style: TextStyle(color: _roleColor(role), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(CupertinoIcons.envelope, size: 14),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                email,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(CupertinoIcons.info, size: 14), const SizedBox(width: 6),
                  Expanded(child: Text('Tap to view and edit details', style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)), overflow: TextOverflow.ellipsis)),
                  const Icon(CupertinoIcons.chevron_right, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserDialog extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final FirebaseFirestore db;
  final FunctionsService fns;
  const _UserDialog({required this.doc, required this.db, required this.fns});

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  late final TextEditingController nameCtrl;
  // Profile-like fields
  late final TextEditingController phoneCtrl;
  late final TextEditingController whatsappCtrl;
  late final TextEditingController aadharCtrl;
  late final TextEditingController occupationCtrl;
  late final TextEditingController addressCtrl;
  DateTime? dob;
  String gender = '';
  String roleSelected = 'project_owner';
  String? selectedBlockId;

  @override
  void initState() {
    super.initState();
    final data = widget.doc.data();
    nameCtrl = TextEditingController(text: (data['displayName'] as String?) ?? '');
    roleSelected = (data['role'] as String?) ?? 'project_owner';
    selectedBlockId = (data['blockId'] as String?)?.trim();
    phoneCtrl = TextEditingController(text: (data['phone'] as String?) ?? '');
    whatsappCtrl = TextEditingController(text: (data['whatsapp'] as String?) ?? '');
    aadharCtrl = TextEditingController(text: (data['aadhar'] as String?) ?? '');
    occupationCtrl = TextEditingController(text: (data['occupation'] as String?) ?? '');
    addressCtrl = TextEditingController(text: (data['address'] as String?) ?? '');
    final d = data['dob'];
    if (d is Timestamp) dob = d.toDate();
    gender = (data['gender'] as String?) ?? '';
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    whatsappCtrl.dispose();
    aadharCtrl.dispose();
    occupationCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final email = (data['email'] as String?) ?? '';
    // Build field widgets; show non-empty first, with optional expander for empty ones
    final nonEmptyFields = <Widget>[];
    final emptyFields = <Widget>[];

    void addField({required String key, required Widget field, required bool isEmpty}) {
      (isEmpty ? emptyFields : nonEmptyFields).add(field);
    }

    addField(
      key: 'displayName',
  field: TextField(controller: nameCtrl, textAlignVertical: TextAlignVertical.center, decoration: const InputDecoration(labelText: 'Display name', prefixIcon: Icon(CupertinoIcons.person))),
      isEmpty: nameCtrl.text.trim().isEmpty,
    );
    // Role and Block controls (role dropdown, block when required)
    final roleWidget = DropdownButtonFormField<String>(
      initialValue: roleSelected,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(CupertinoIcons.shield)),
      items: const [
        DropdownMenuItem(value: 'project_owner', child: Text('Project Owner')),
        DropdownMenuItem(value: 'super_nodal', child: Text('Super Nodal')),
        DropdownMenuItem(value: 'sub_nodal', child: Text('Sub Nodal')),
      ],
      onChanged: (v) => setState(() => roleSelected = v ?? roleSelected),
    );
    addField(key: 'role', field: roleWidget, isEmpty: false);

    final needsBlock = roleSelected == 'project_owner' || roleSelected == 'sub_nodal';
    final blockWidget = DropdownButtonFormField<String>(
      initialValue: selectedBlockId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Block', prefixIcon: Icon(CupertinoIcons.map_pin_ellipse)),
      items: const [
        DropdownMenuItem(value: 'dhamtari', child: Text('Dhamtari')),
        DropdownMenuItem(value: 'kurud', child: Text('Kurud')),
        DropdownMenuItem(value: 'magarload', child: Text('Magarlod')),
        DropdownMenuItem(value: 'nagri', child: Text('Nagri')),
      ],
      onChanged: (v) => setState(() => selectedBlockId = v),
    );
    addField(key: 'blockId', field: blockWidget, isEmpty: (selectedBlockId ?? '').isEmpty && !needsBlock);

    addField(
      key: 'phone',
      field: TextField(
        textAlignVertical: TextAlignVertical.center,
        controller: phoneCtrl,
        decoration: const InputDecoration(labelText: 'Phone (India)', prefixText: '+91 ', prefixIcon: Icon(CupertinoIcons.phone)),
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
      ),
      isEmpty: phoneCtrl.text.trim().isEmpty,
    );
    addField(
      key: 'whatsapp',
      field: TextField(
        textAlignVertical: TextAlignVertical.center,
        controller: whatsappCtrl,
        decoration: const InputDecoration(labelText: 'WhatsApp (India)', prefixText: '+91 ', prefixIcon: Icon(CupertinoIcons.chat_bubble_text)),
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
      ),
      isEmpty: whatsappCtrl.text.trim().isEmpty,
    );
    addField(
      key: 'aadhar',
      field: TextField(
        textAlignVertical: TextAlignVertical.center,
        controller: aadharCtrl,
        decoration: const InputDecoration(labelText: 'Aadhaar', prefixIcon: Icon(CupertinoIcons.person_crop_square)),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
      ),
      isEmpty: aadharCtrl.text.trim().isEmpty,
    );
    addField(
      key: 'dob',
      field: InputDatePickerFormField(
        firstDate: DateTime(1900, 1, 1),
        lastDate: DateTime.now(),
        initialDate: dob ?? DateTime(2000, 1, 1),
        onDateSubmitted: (d) => setState(() => dob = d),
        onDateSaved: (d) => dob = d,
      ),
      isEmpty: dob == null,
    );
    addField(
      key: 'gender',
      field: DropdownButtonFormField<String>(
        initialValue: gender.isEmpty ? null : gender,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(CupertinoIcons.person_2)),
        items: const [
          DropdownMenuItem(value: 'Male', child: Text('Male')),
          DropdownMenuItem(value: 'Female', child: Text('Female')),
          DropdownMenuItem(value: 'Non-binary', child: Text('Non-binary')),
          DropdownMenuItem(value: 'Prefer not to say', child: Text('Prefer not to say')),
        ],
        onChanged: (v) => setState(() => gender = v ?? ''),
      ),
      isEmpty: gender.trim().isEmpty,
    );
    addField(
      key: 'occupation',
  field: TextField(controller: occupationCtrl, textAlignVertical: TextAlignVertical.center, decoration: const InputDecoration(labelText: 'Occupation', prefixIcon: Icon(CupertinoIcons.briefcase))),
      isEmpty: occupationCtrl.text.trim().isEmpty,
    );
    addField(
      key: 'address',
  field: TextField(controller: addressCtrl, textAlignVertical: TextAlignVertical.center, maxLines: 3, decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(CupertinoIcons.house))),
      isEmpty: addressCtrl.text.trim().isEmpty,
    );

    Widget fieldsWrap(List<Widget> items) => LayoutBuilder(builder: (context, c) {
          final isWide = c.maxWidth > 560;
          final w = isWide ? (c.maxWidth - 12) / 2 : c.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final f in items) SizedBox(width: w, child: f)],
          );
        });

    return AlertDialog(
      title: Row(children:[const Icon(CupertinoIcons.person_crop_circle, size: 20), const SizedBox(width: 8), const Text('User')]),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _UserAvatarPreview(doc: widget.doc),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children:[const Icon(CupertinoIcons.envelope, size: 14), const SizedBox(width: 6), Expanded(child: Text(email, overflow: TextOverflow.ellipsis))]),
                      const SizedBox(height: 2),
                      const Text('Email and avatar are immutable', style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A))),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              fieldsWrap(nonEmptyFields.isEmpty ? emptyFields : nonEmptyFields),
              if (nonEmptyFields.isNotEmpty && emptyFields.isNotEmpty) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  title: const Text('More fields'),
                  children: [Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: fieldsWrap(emptyFields))],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        Tooltip(message: 'Delete user & projects', child: IconButton(onPressed: _confirmDelete, icon: const Icon(CupertinoIcons.delete, color: Colors.redAccent))),
        FilledButton.icon(onPressed: _save, icon: const Icon(CupertinoIcons.floppy_disk), label: const Text('Save')),
      ],
    );
  }

  Future<void> _save() async {
    try {
      // Validate minimal constraints
      final needsBlock = roleSelected == 'project_owner' || roleSelected == 'sub_nodal';
      if (needsBlock && (selectedBlockId == null || selectedBlockId!.isEmpty)) {
        if (mounted) _showSnack(context, 'Block is required for $roleSelected', icon: CupertinoIcons.exclamationmark_triangle, error: true);
        return;
      }
      if (phoneCtrl.text.trim().isNotEmpty && phoneCtrl.text.trim().length != 10) {
        if (mounted) _showSnack(context, 'Phone must be 10 digits', icon: CupertinoIcons.phone, error: true);
        return;
      }
      if (whatsappCtrl.text.trim().isNotEmpty && whatsappCtrl.text.trim().length != 10) {
        if (mounted) _showSnack(context, 'WhatsApp must be 10 digits', icon: CupertinoIcons.chat_bubble_text, error: true);
        return;
      }
      if (aadharCtrl.text.trim().isNotEmpty && aadharCtrl.text.trim().length != 12) {
        if (mounted) _showSnack(context, 'Aadhaar must be 12 digits', icon: CupertinoIcons.person_crop_square, error: true);
        return;
      }

      await widget.doc.reference.set({
        'displayName': nameCtrl.text.trim(),
        'role': roleSelected.trim(),
        'blockId': selectedBlockId,
        'phone': phoneCtrl.text.trim(),
        'whatsapp': whatsappCtrl.text.trim(),
        'aadhar': aadharCtrl.text.trim(),
        if (dob != null) 'dob': Timestamp.fromDate(dob!),
        'gender': gender.trim(),
        'occupation': occupationCtrl.text.trim(),
        'address': addressCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
  if (!mounted) return;
  _showSnack(context, 'Saved', icon: CupertinoIcons.floppy_disk);
    } catch (e) {
  if (!mounted) return;
  _showSnack(context, 'Failed: $e', icon: CupertinoIcons.exclamationmark_triangle, error: true);
    }
  }

  Future<void> _deleteUserAndProjects() async {
    final id = widget.doc.id;
    try {
      // Use Cloud Function to delete from Firebase Auth and Firestore (and related data server-side)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Padding(
            padding: EdgeInsets.all(12.0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 20, width: 20, child: AppLoadingIndicator(size: 20)), 
              SizedBox(width: 12),
              Text('Deleting user…'),
            ]),
          ),
        ),
      );
      await widget.fns.adminDeleteUser(uid: id);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      Navigator.pop(context);
      _showSnack(context, 'User deleted from Auth and Firestore', icon: CupertinoIcons.delete);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSnack(context, 'Delete failed: $e', icon: CupertinoIcons.exclamationmark_triangle, error: true);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
  title: const Text('Delete user completely?'),
  content: const Text('This will remove the user from Firebase Auth and Firestore (and related data). This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(CupertinoIcons.delete), label: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await _deleteUserAndProjects();
    }
  }
}

class _UserAvatarPreview extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _UserAvatarPreview({required this.doc});
  @override
  Widget build(BuildContext context) {
    final data = doc.data();
  final email = (data['email'] as String?) ?? '';
  final display = (data['displayName'] as String?) ?? email;
  final initial = ((display.trim().isNotEmpty ? display.trim() : email).characters.first.toUpperCase());
    return Column(
      children: [
    CircleAvatar(
      radius: 32,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(
        initial,
        textAlign: TextAlign.center,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: true,
          applyHeightToLastDescent: true,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
          height: 1.0,
          leadingDistribution: TextLeadingDistribution.even,
          textBaseline: TextBaseline.alphabetic,
        ),
      ),
    ),
        const SizedBox(height: 6),
    const Text('User')
      ],
    );
  }
}

// --- Projects Tab Content ---
class _ProjectsTabContent extends StatefulWidget {
  final FirebaseFirestore db;
  const _ProjectsTabContent({required this.db});

  @override
  State<_ProjectsTabContent> createState() => _ProjectsTabContentState();
}

class _ProjectsTabContentState extends State<_ProjectsTabContent> {
  String search = '';
  bool grid = false;
  final selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final q = widget.db.collection('projects');
    return Column(
      children: [
        PageTransitionSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, a, sa) => FadeThroughTransition(animation: a, secondaryAnimation: sa, child: child),
          child: _ProjectsToolbar(
            key: ValueKey('projects_toolbar_${grid ? 'grid' : 'list'}_${selected.length}') ,
            grid: grid,
            selectedCount: selected.length,
            onToggleView: () => setState(() => grid = !grid),
            onSearch: (v) => setState(() => search = v.trim().toLowerCase()),
            onBulkDelete: selected.isEmpty ? null : () async {
              final ids = selected.toList();
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete selected projects?'),
                  content: const Text('This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(CupertinoIcons.delete), label: const Text('Delete')),
                  ],
                ),
              );
              if (confirm == true) {
                for (final id in ids) {
                  try { await widget.db.collection('projects').doc(id).delete(); } catch (_) {}
                }
                if (mounted) setState(() => selected.clear());
                if (context.mounted) _showSnack(context, 'Deleted ${ids.length} projects', icon: CupertinoIcons.delete);
              }
            },
          ),
        ),
        const Divider(height: 1, color: Colors.transparent),
        Expanded(
          child: StreamBuilder(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: AppLoadingIndicator());
              }
              if (!snap.hasData) return const NoData(message: 'No data');
              var docs = (snap.data as QuerySnapshot<Map<String, dynamic>>).docs;
              // Local sort by updatedAt desc
              docs.sort((a,b){
                final at = (a.data()['updatedAt'] as Timestamp?);
                final bt = (b.data()['updatedAt'] as Timestamp?);
                if (at != null && bt != null) return bt.compareTo(at);
                return 0;
              });
              if (search.isNotEmpty) {
                docs = docs.where((d) {
                  final n = (d.data()['name'] as String? ?? '').toLowerCase();
                  final id = d.id.toLowerCase();
                  return n.contains(search) || id.contains(search);
                }).toList();
              }
              if (docs.isEmpty) return const NoData(message: 'No projects', asset: 'assets/no_projects.svg');
              final listWidget = grid
          ? GridView.builder(
                      padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 480, childAspectRatio: 2.6, crossAxisSpacing: 10, mainAxisSpacing: 10),
                      itemCount: docs.length,
                      itemBuilder: (context, i) => _ProjectTile(
                        doc: docs[i],
                        selected: selected.contains(docs[i].id),
                        onOpen: () => _openEditor(context, docs[i].id),
                        onToggleSelect: () => setState(() {
                          final id = docs[i].id; if (selected.contains(id)) { selected.remove(id); } else { selected.add(id); }
                        }),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: docs.length,
                      itemBuilder: (context, i) => _ProjectRow(
                        doc: docs[i],
                        selected: selected.contains(docs[i].id),
                        onOpen: () => _openEditor(context, docs[i].id),
                        onToggleSelect: () => setState(() {
                          final id = docs[i].id; if (selected.contains(id)) { selected.remove(id); } else { selected.add(id); }
                        }),
                        onDelete: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete project?'),
                              content: const Text('This cannot be undone.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(CupertinoIcons.delete), label: const Text('Delete')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await docs[i].reference.delete();
                            if (!context.mounted) return;
                            _showSnack(context, 'Project deleted', icon: CupertinoIcons.delete);
                          }
                        },
                      ),
                    );
              return PageTransitionSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, a, sa) => FadeThroughTransition(animation: a, secondaryAnimation: sa, child: child),
                child: KeyedSubtree(key: ValueKey('projects_${grid ? 'grid' : 'list'}_${docs.length}_$search'), child: listWidget),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openEditor(BuildContext context, String projectId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => editor.ProjectEditorPage(projectId: projectId),
    ));
  }
}

class _ProjectsToolbar extends StatelessWidget {
  final bool grid;
  final int selectedCount;
  final VoidCallback onToggleView;
  final ValueChanged<String> onSearch;
  final VoidCallback? onBulkDelete;
  const _ProjectsToolbar({super.key, required this.grid, required this.selectedCount, required this.onToggleView, required this.onSearch, required this.onBulkDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Tooltip(message: grid ? 'List view' : 'Grid view', child: IconButton(onPressed: onToggleView, icon: Icon(grid ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2))),
          const SizedBox(width: 8),
          SizedBox(
            width: 360,
            child: TextField(
              textAlignVertical: TextAlignVertical.center,
              onChanged: onSearch,
              decoration: const InputDecoration(hintText: 'Search projects', prefixIcon: Icon(CupertinoIcons.search)),
            ),
          ),
          const SizedBox(width: 8),
          if (selectedCount > 0) Text('$selectedCount selected'),
          const SizedBox(width: 8),
          Tooltip(message: 'Delete selected', child: IconButton(onPressed: onBulkDelete, icon: const Icon(CupertinoIcons.delete)) ),
        ]),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onToggleSelect;
  final VoidCallback onDelete;
  const _ProjectRow({required this.doc, required this.selected, required this.onOpen, required this.onToggleSelect, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final status = ((data['status'] as String?) ?? 'in_progress').replaceAll('draft', 'in_progress');
    final block = (data['blockId'] as String?) ?? '-';
    final ownerId = (data['ownerId'] as String?) ?? '';
    final stage = ((data['workDescription'] as Map<String, dynamic>?)?['stage'] as String?) ?? '';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      child: ListTile(
        onTap: onOpen,
        leading: Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(value: selected, onChanged: (_) => onToggleSelect()),
          const SizedBox(width: 6),
          const Icon(CupertinoIcons.cube_box),
        ]),
        title: Row(children:[const Icon(CupertinoIcons.doc_text, size: 16), const SizedBox(width: 6), Expanded(child: Text((data['name'] as String?) ?? doc.id, overflow: TextOverflow.ellipsis))]),
        subtitle: Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children:[const Icon(CupertinoIcons.flag, size: 14), const SizedBox(width: 4), Text(status)]),
          Row(mainAxisSize: MainAxisSize.min, children:[const Icon(CupertinoIcons.map_pin_ellipse, size: 14), const SizedBox(width: 4), Text(block)]),
          if (stage.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children:[const Icon(CupertinoIcons.hammer, size: 14), const SizedBox(width: 4), Text(stage)]),
          if (ownerId.isNotEmpty)
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance.collection('users').doc(ownerId).get(),
              builder: (context, snap) {
                final ownerName = snap.data?.data()?['displayName'] as String? ?? ownerId;
                return Row(mainAxisSize: MainAxisSize.min, children:[const Icon(CupertinoIcons.person, size: 14), const SizedBox(width: 4), Text(ownerName, overflow: TextOverflow.ellipsis)]);
              },
            ),
        ]),
        trailing: Wrap(spacing: 4, children: [
          IconButton(tooltip: 'Edit', icon: const Icon(CupertinoIcons.pencil), onPressed: onOpen),
          IconButton(tooltip: 'Delete', icon: const Icon(CupertinoIcons.delete), onPressed: onDelete),
        ]),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onToggleSelect;
  const _ProjectTile({required this.doc, required this.selected, required this.onOpen, required this.onToggleSelect});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final status = ((data['status'] as String?) ?? 'in_progress').replaceAll('draft', 'in_progress');
    final block = (data['blockId'] as String?) ?? '-';
    final ownerId = (data['ownerId'] as String?) ?? '';
    final stage = ((data['workDescription'] as Map<String, dynamic>?)?['stage'] as String?) ?? '';
    return InkWell(
      onTap: onOpen,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Checkbox(value: selected, onChanged: (_) => onToggleSelect()),
              const SizedBox(width: 8),
              const Icon(CupertinoIcons.cube_box),
              const SizedBox(width: 8),
              Expanded(child: Text((data['name'] as String?) ?? doc.id, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _chip(status, icon: CupertinoIcons.flag),
              _chip(block, icon: CupertinoIcons.map_pin_ellipse),
              if (stage.isNotEmpty) _chip(stage, icon: CupertinoIcons.hammer),
              if (ownerId.isNotEmpty)
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance.collection('users').doc(ownerId).get(),
                  builder: (context, snap) {
                    final ownerName = snap.data?.data()?['displayName'] as String? ?? ownerId;
                    return _chip(ownerName, icon: CupertinoIcons.person);
                  },
                ),
            ]),
            const SizedBox(height: 8),
            Row(children:[const Icon(CupertinoIcons.info, size: 14), const SizedBox(width: 6), Expanded(child: Text('Tap to edit project', style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)), overflow: TextOverflow.ellipsis))]),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String text, {required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children:[Icon(icon, size: 14), const SizedBox(width: 6), Text(text, overflow: TextOverflow.ellipsis)]),
    );
  }
}

// Helpers for role visual language
IconData _roleIcon(String role) {
  switch (role) {
    case 'dev_admin':
  return CupertinoIcons.lock_shield;
    case 'super_nodal':
  return CupertinoIcons.check_mark_circled;
    case 'sub_nodal':
  return CupertinoIcons.tree;
    case 'project_owner':
    default:
  return CupertinoIcons.person_crop_rectangle;
  }
}

Color _roleColor(String role) {
  switch (role) {
    case 'dev_admin':
      return Colors.purple;
    case 'super_nodal':
      return Colors.blueAccent;
    case 'sub_nodal':
      return Colors.indigo;
    case 'project_owner':
    default:
      return Colors.teal;
  }
}

// Old custom bar chart removed in favor of fl_chart-based widgets.

// Charts removed; keeping dashboard purely metric tiles for performance and simplicity.

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.cube_box, size: 48, color: Color(0xFF6B6B6B)),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: Color(0xFFBFBFBF))),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6.0, right: 8.0),
            child: Icon(CupertinoIcons.circle_fill, size: 6, color: Color(0xFF9A9A9A)),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
