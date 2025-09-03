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
import '../../dashboard/presentation/projects_charts.dart';
import '../../../shared/widgets/app_sidebar.dart';
import '../../../shared/ui/toast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xls;
import '../../auth/data/auth_repository.dart';
import '../../../services/functions_service.dart';
import 'admin_theme.dart';
import '../../profile/presentation/profile_page.dart';
import '../../../shared/widgets/no_data.dart';

class ProdAdminDashboardPage extends ConsumerStatefulWidget {
  const ProdAdminDashboardPage({super.key});

  @override
  ConsumerState<ProdAdminDashboardPage> createState() => _ProdAdminDashboardPageState();
}

class _ProdAdminDashboardPageState extends ConsumerState<ProdAdminDashboardPage> with SingleTickerProviderStateMixin {
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
    final user = ref.watch(authStateProvider).value;
    final isCompact = MediaQuery.of(context).size.width < 720;
    return Theme(
      data: AdminTheme.amoledDark,
      child: Scaffold(
        body: Row(
          children: [
            if (!isCompact) ...[
              SizedBox(
                width: 256,
                child: AppSidebar(
                  selectedIndex: _sideIndex,
                  onSelect: (i) => setState(() { _sideIndex = i; _tab.index = i; }),
                ),
              ),
              VerticalDivider(width: 1, color: Colors.white.withValues(alpha: 0.06)),
            ],
            Expanded(
              child: Column(
                children: [
                  _AdminTopBar(email: user?.email ?? ''),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
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
                        ProfilePage(),
                      ],
                      ),
                    ),
                  ),
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
                  BottomNavigationBarItem(icon: Icon(CupertinoIcons.square_grid_2x2), label: 'Stats'),
                  BottomNavigationBarItem(icon: Icon(CupertinoIcons.group), label: 'Users'),
                  BottomNavigationBarItem(icon: Icon(CupertinoIcons.folder), label: 'Projects'),
                  BottomNavigationBarItem(icon: Icon(CupertinoIcons.person), label: 'Profile'),
                ],
              )
            : null,
      ),
    );
  }
}

void _showSnack(BuildContext context, String message, {IconData icon = CupertinoIcons.info, bool error = false}) =>
  showToast(context, message, icon: icon, error: error);

// Replaced custom _AdminSidebar with SidebarX

class _AdminTopBar extends StatelessWidget {
  final String email;
  const _AdminTopBar({required this.email});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        const Spacer(),
  IconButton(onPressed: () {}, icon: const Icon(CupertinoIcons.bell)),
        const SizedBox(width: 4),
        CircleAvatar(radius: 14, child: Text(email.isNotEmpty ? email[0].toUpperCase() : '?')),
      ]),
    );
  }
}

class _AdminStatsTab extends StatelessWidget {
  const _AdminStatsTab();

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('projects').snapshots(),
      builder: (context, snap) {
        final docs = (snap.hasData) ? (snap.data as QuerySnapshot<Map<String, dynamic>>).docs : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
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
                  Wrap(
                    spacing: isWide ? 12 : 8,
                    runSpacing: isWide ? 12 : 8,
                    children: [
                      ...() {
                        final gap = isWide ? 12.0 : 8.0;
                        final w = c.maxWidth;
                        final cols = w > 1280 ? 4 : w > 960 ? 3 : w > 640 ? 2 : 1;
                        final tileW = (w - (gap * (cols - 1))) / cols;
                        return [
                          _metric('Total Projects', total, Colors.blue, CupertinoIcons.folder, tileW),
                          _metric('In Progress', inProgress, Colors.orange, CupertinoIcons.arrow_2_circlepath, tileW),
                          _metric('Completed', completed, Colors.green, CupertinoIcons.check_mark_circled, tileW),
                          _metric('Cancelled', cancelled, Colors.redAccent, CupertinoIcons.xmark_octagon, tileW),
                        ];
                      }(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ChartsSection(completed: completed, inProgress: inProgress, cancelled: cancelled, isWide: isWide),
                  const SizedBox(height: 16),
                  StreamBuilder(
                    stream: db.collection('users').snapshots(),
                    builder: (context, usnap) {
                      final u = (usnap.hasData) ? (usnap.data as QuerySnapshot<Map<String, dynamic>>).docs : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                      // final uTotal = u.length; // excluded dev_admin from totals below
                      final owners = u.where((d)=> d.data()['role'] == 'project_owner').length;
                      final nodals = u.where((d)=> d.data()['role'] == 'sub_nodal').length;
                      final supers = u.where((d)=> d.data()['role'] == 'super_nodal').length;
          // Exclude dev_admin from totals
          final nonAdmins = u.where((d) => (d.data()['role'] as String?) != 'dev_admin').toList();
          return Wrap(
                        spacing: isWide ? 12 : 8,
                        runSpacing: isWide ? 12 : 8,
                        children: (){
                          final gap = isWide ? 12.0 : 8.0;
                          final w = c.maxWidth;
                          final cols = w > 1280 ? 4 : w > 960 ? 3 : w > 640 ? 2 : 1;
                          final tileW = (w - (gap * (cols - 1))) / cols;
                          return [
            _metric('Total Users', nonAdmins.length, Colors.cyan, CupertinoIcons.group, tileW),
            _metric('Owners', owners, Colors.teal, CupertinoIcons.person_crop_rectangle, tileW),
            _metric('Nodals', nodals, Colors.indigo, CupertinoIcons.tree, tileW),
            _metric('Super Nodals', supers, Colors.purple, CupertinoIcons.check_mark_circled, tileW),
                          ];
                        }(),
                      );
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

  Widget _metric(String label, int value, Color color, IconData icon, double width) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0.04)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label),
                    const SizedBox(height: 6),
                    Text('$value', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ],
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
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete selected users?'),
                content: const Text('This will remove users from Firebase Auth and Firestore.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(CupertinoIcons.delete), label: const Text('Delete')),
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
                      SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
  Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
        Expanded(
          child: StreamBuilder(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
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
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Create Users'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Prepare a CSV or Excel file with the following columns:'),
              SizedBox(height: 8),
              _Bullet(text: 'email (required)'),
              _Bullet(text: 'role (optional: project_owner, super_nodal, sub_nodal; defaults to project_owner)'),
              _Bullet(text: 'block (required for project_owner and sub_nodal; one of: dhamtari, kurud, magarload, nagri)'),
              SizedBox(height: 12),
              Text('Notes:'),
              SizedBox(height: 6),
              _Bullet(text: 'Passwords are auto-generated and added back to your file in a generated_password column.'),
              _Bullet(text: 'Each row will get status and message columns indicating success or any error.'),
              _Bullet(text: 'Rows missing required block for project_owner or sub_nodal are skipped.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(CupertinoIcons.square_stack_3d_up), label: const Text('Pick file')),
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
  String roleCategory = 'project_owner'; // 'project_owner' | 'nodal_officer'
  String nodalType = 'super_nodal'; // when nodal_officer
  const blockOptions = ['dhamtari', 'kurud', 'magarload', 'nagri'];
  String? selectedBlock;
  String? genPass;
  bool createdOk = false;
    bool creating = false;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Create User'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (creating) const LinearProgressIndicator(minHeight: 3),
                if (creating) const SizedBox(height: 12),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 12),
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
                  onChanged: (v) => setLocal(() { roleCategory = v ?? 'project_owner'; }),
                ),
                if (roleCategory == 'nodal_officer') ...[
                  const SizedBox(height: 12),
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
                    onChanged: (v) => setLocal(() { nodalType = v ?? 'super_nodal'; }),
                  ),
                ],
                if (roleCategory == 'project_owner' || (roleCategory == 'nodal_officer' && nodalType == 'sub_nodal')) ...[
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: Text('Block', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF9A9A9A)))),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedBlock,
                    decoration: const InputDecoration(labelText: 'Block'),
                    isExpanded: true,
                    items: [
                      ...blockOptions.map((b) => DropdownMenuItem(value: b, child: Text(b[0].toUpperCase() + b.substring(1))))
                    ],
                    onChanged: (v) => setLocal(() { selectedBlock = v; }),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Required for Project Owner and Sub Nodal',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF9A9A9A)),
                    ),
                  ),
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
                          Row(children:[const Icon(CupertinoIcons.envelope, size: 16), const SizedBox(width: 6), Expanded(child: Text(emailCtrl.text.trim(), overflow: TextOverflow.ellipsis))]),
                          const SizedBox(height: 6),
                          Row(children:[const Icon(CupertinoIcons.lock, size: 16), const SizedBox(width: 6), Expanded(child: SelectableText(genPass!))]),
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
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            TextButton(
              onPressed: () async {
                if (creating) return;
                final email = emailCtrl.text.trim();
                if (email.isEmpty) return;
                final displayName = nameCtrl.text.trim();
                // Resolve final role and validate required block when needed
                final roleToUse = roleCategory == 'nodal_officer' ? nodalType : 'project_owner';
                final needsBlock = roleToUse == 'project_owner' || roleToUse == 'sub_nodal';
                if (needsBlock && (selectedBlock == null || selectedBlock!.isEmpty)) {
                  if (context.mounted) _showSnack(context, 'Please select a block', icon: CupertinoIcons.exclamationmark_triangle, error: true);
                  return;
                }
                genPass = _genPassword();
                try {
                  setLocal(() => creating = true);
                  // Create Auth user via Cloud Function
                  final created = await widget.fns.createAuthUser(email: email, password: genPass!, role: roleToUse, displayName: displayName);
                  final uid = created['uid'] as String?;
                  if (uid != null && uid.isNotEmpty) {
                    // Firestore doc is written server-side by the Cloud Function.
                    createdOk = true;
                    // Attach selected block for PO or sub nodal
                    if (selectedBlock != null && (roleToUse == 'project_owner' || roleToUse == 'sub_nodal')) {
                      await widget.db.collection('users').doc(uid).set({'blocks': [selectedBlock]}, SetOptions(merge: true));
                    }
                    if (context.mounted) _showSnack(context, 'User created', icon: Icons.check_circle_outline);
                  }
                } catch (e) {
                  if (context.mounted) { _showSnack(context, 'Create failed: $e', icon: Icons.error_outline, error: true); }
                } finally {
                  setLocal(() => creating = false);
                }
              },
              child: creating
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('Creating…')])
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
      ),
    );
  }

  Future<void> _exportCredentials(String email, String password, {required bool toPdf}) async {
    final content = 'Email: $email\nPassword: $password\n';
    if (!toPdf) {
      final bytes = utf8.encode(content);
      await FileSaver.instance.saveFile(name: 'credentials_$email', bytes: bytes, ext: 'txt', mimeType: MimeType.text);
    } else {
      final doc = pw.Document();
      doc.addPage(pw.Page(build: (c) => pw.Center(child: pw.Text(content))));
      final bytes = await doc.save();
      await Printing.sharePdf(bytes: bytes, filename: 'credentials_$email.pdf');
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
        final payload = <Map<String, String>>[];
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
          payload.add({'email': email, 'password': pass, 'role': role});
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
                  SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
        await FileSaver.instance.saveFile(name: 'bulk_credentials', bytes: bytes, ext: 'csv', mimeType: MimeType.csv);
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
        final payload = <Map<String, String>>[];
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
          payload.add({'email': email, 'password': pass, 'role': role});
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
                  SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
          await FileSaver.instance.saveFile(
            name: 'bulk_credentials',
            bytes: Uint8List.fromList(outBytes),
            ext: 'xlsx',
            mimeType: MimeType.other,
          );
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
                await FileSaver.instance.saveFile(name: 'sample_users', bytes: bytes, ext: 'csv', mimeType: MimeType.csv);
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
    final blocks = ((data['blocks'] as List?) ?? const []).whereType<String>().toList();
    final photoUrl = (data['photoUrl'] as String?) ?? '';
    final email = (data['email'] as String?) ?? '';
    final display = (data['displayName'] as String?) ?? email;
    return ListTile(
      onTap: onTap,
      leading: Row(mainAxisSize: MainAxisSize.min, children:[
        Checkbox(value: selected, onChanged: (_) => onSelectToggle()),
        const SizedBox(width: 6),
  CircleAvatar(radius: 16, backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null, child: photoUrl.isEmpty ? const Icon(CupertinoIcons.person, size: 18) : null),
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
          if (blocks.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children:[const Icon(CupertinoIcons.square_grid_2x2, size: 14), const SizedBox(width: 4), Text(blocks.join(', '), overflow: TextOverflow.ellipsis)]),
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
    final photoUrl = (data['photoUrl'] as String?) ?? '';
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
                  CircleAvatar(radius: 20, backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null, child: photoUrl.isEmpty ? const Icon(CupertinoIcons.person) : null),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children:[
                        const Icon(CupertinoIcons.person, size: 16), const SizedBox(width: 6),
                        Expanded(child: Text((data['displayName'] ?? email) as String, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                      ]),
                      const SizedBox(height: 6),
                      Row(children:[
                        Icon(_roleIcon(role), size: 14, color: _roleColor(role)), const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _roleColor(role).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: _roleColor(role).withValues(alpha: 0.24)),
                          ),
                          child: Text(role, style: TextStyle(color: _roleColor(role), fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        const Spacer(),
                        Row(children:[const Icon(CupertinoIcons.envelope, size: 14), const SizedBox(width: 4), Text(email, style: const TextStyle(fontSize: 12))]),
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
  late final TextEditingController roleCtrl;
  late final TextEditingController blocksCtrl;

  @override
  void initState() {
    super.initState();
    final data = widget.doc.data();
    nameCtrl = TextEditingController(text: (data['displayName'] as String?) ?? '');
    roleCtrl = TextEditingController(text: (data['role'] as String?) ?? 'project_owner');
    final blocks = ((data['blocks'] as List?) ?? const []).whereType<String>().toList().join(',');
    blocksCtrl = TextEditingController(text: blocks);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    roleCtrl.dispose();
    blocksCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('User'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
      _UserAvatarPreview(doc: widget.doc),
      const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Display name')), 
            const SizedBox(height: 12),
            TextField(controller: roleCtrl, decoration: const InputDecoration(labelText: 'Role')), 
            const SizedBox(height: 12),
            TextField(controller: blocksCtrl, decoration: const InputDecoration(labelText: 'Blocks (comma-separated)')), 
            const SizedBox(height: 12),
      const Text('Email, password, and avatar are immutable'),
          ],
        ),
      ),
      actions: [
  Tooltip(message: 'Close', child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(CupertinoIcons.xmark))),
  Tooltip(message: 'Delete user & projects', child: IconButton(onPressed: _confirmDelete, icon: const Icon(CupertinoIcons.delete, color: Colors.redAccent))),
  FilledButton.icon(onPressed: _save, icon: const Icon(CupertinoIcons.floppy_disk), label: const Text('Save')),
      ],
    );
  }

  Future<void> _save() async {
    try {
      final blocks = blocksCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  await widget.doc.reference.set({'displayName': nameCtrl.text.trim(), 'role': roleCtrl.text.trim(), if (blocks.isNotEmpty) 'blocks': blocks, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
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
              SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
    final photoUrl = (data['photoUrl'] as String?) ?? '';
    return Column(
      children: [
        CircleAvatar(radius: 32, backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null, child: photoUrl.isEmpty ? const Icon(Icons.person, size: 28) : null),
        const SizedBox(height: 6),
        const Text('Avatar (immutable)')
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
  @override
  Widget build(BuildContext context) {
    final q = widget.db.collection('projects');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(
            width: 360,
            child: TextField(
              onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
              decoration: const InputDecoration(hintText: 'Search projects', prefixIcon: Icon(CupertinoIcons.search)),
            ),
          ),
        ),
  Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
        Expanded(
          child: StreamBuilder(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
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
              if (docs.isEmpty) return const NoData(message: 'No projects');
              final list = ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final data = d.data();
                  final status = (data['status'] as String?) ?? 'draft';
                  return ListTile(
                    title: Text((data['name'] as String?) ?? d.id),
                    subtitle: Text('Status: $status • Block: ${(data['blockId'] as String?) ?? '-'}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      PopupMenuButton<String>(
                        tooltip: 'Change status',
                        onSelected: (v) async {
                          if (v.startsWith('status:')) {
                            final newStatus = v.split(':')[1];
                            await d.reference.update({'status': newStatus, 'updatedAt': FieldValue.serverTimestamp()});
                            if (!context.mounted) return;
                            _showSnack(context, 'Status updated', icon: Icons.edit);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'status:draft', child: Text('Mark Draft')),
                          PopupMenuItem(value: 'status:in_progress', child: Text('Mark In Progress')),
                          PopupMenuItem(value: 'status:completed', child: Text('Mark Completed')),
                          PopupMenuItem(value: 'status:cancelled', child: Text('Mark Cancelled')),
                        ],
                        child: const Icon(CupertinoIcons.pencil, size: 20),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Delete project',
                        icon: const Icon(CupertinoIcons.delete),
                        onPressed: () async {
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
                            await d.reference.delete();
                            if (!context.mounted) return;
                            _showSnack(context, 'Project deleted', icon: CupertinoIcons.delete);
                          }
                        },
                      ),
                    ]),
                  );
                },
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
              );
              return PageTransitionSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, a, sa) => FadeThroughTransition(animation: a, secondaryAnimation: sa, child: child),
                child: KeyedSubtree(key: ValueKey('projects_${docs.length}_$search'), child: list),
              );
            },
          ),
        ),
      ],
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

class _ChartsSection extends StatelessWidget {
  final int completed;
  final int inProgress;
  final int cancelled;
  final bool isWide;
  const _ChartsSection({required this.completed, required this.inProgress, required this.cancelled, required this.isWide});

  @override
  Widget build(BuildContext context) {
    return ProjectsCharts(
      completed: completed,
      inProgress: inProgress,
      cancelled: cancelled,
      isWide: isWide,
    );
  }
}

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
