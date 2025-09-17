import 'package:flutter/material.dart';
import '../../../shared/utils/date_parse.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gap/gap.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:timelines_plus/timelines_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../../shared/utils/file_open_helper.dart';
// removed map imports after redesign cleanup
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../data/project_repository.dart';
import '../domain/project.dart';
// import '../../../services/functions_service.dart';
import '../../../core/providers/firebase_providers.dart';
import 'project_edit_page.dart' as editor;
import '../../../shared/widgets/scroll_safe_dialog.dart';
import '../domain/project_update.dart';
// removed unused updates_repository import after refactor
// storage_service is provided indirectly via provider in attachments tab usage
import '../../../shared/widgets/attachment_button.dart';
import 'project_update_form_page.dart';
// import '../../../core/widgets/branding_footer.dart';
// import '../../../shared/ui/toast.dart';
// import '../../auth/data/auth_repository.dart';
// import '../../auth/domain/app_user.dart';

class ProjectDetailPage extends ConsumerWidget {
  final Project project;
  final bool tabbed;
  const ProjectDetailPage({super.key, required this.project, this.tabbed = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Persist a compact snapshot for instant re-open
    ref.read(diskCacheProvider).setJson(
      'project:detail:${project.id}',
      {
        'id': project.id,
        'name': project.name,
        'description': project.description,
        'ownerId': project.ownerId,
        'blockId': project.blockId,
        'villageId': project.villageId,
        'status': project.status.name,
        'phase': project.phase,
        'createdAt': project.createdAt.millisecondsSinceEpoch,
        'updatedAt': project.updatedAt.millisecondsSinceEpoch,
      },
      ttl: const Duration(hours: 12),
    );
  // Streams/services resolved lazily where needed to avoid unused variables
    // final cs = Theme.of(context).colorScheme; // not used currently
  // final user = ref.watch(authStateProvider).value;
  final user = ref.watch(authStateProvider).value;
  final isOwner = user != null && user.uid == project.ownerId;

  Widget header(Project project) {
    // Header numbers are computed from live project
    final budget = project.sanctionCompliance.approvedAmount ?? 0;
    final paid = (project.allotmentDetails.installment1?.receivedAmount ?? 0) +
        (project.allotmentDetails.installment2?.receivedAmount ?? 0) +
        (project.allotmentDetails.installment3?.receivedAmount ?? 0);
    final due = _computeOverdueAmount(project);
    final cs = Theme.of(context).colorScheme;
  final isCompleted = project.status == ProjectStatus.completed;
  final workCompleted = project.workDescription.stage == WorkStage.completed;
  final isDevAdmin = user?.role == UserRole.devAdmin;
    final infoChips = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _statusChip(context, project.status),
        if (project.phase > 0) _chip(context, CupertinoIcons.number, 'Phase ${project.phase}'),
        _moneyChipInr(context, 'Budget', budget),
        _moneyChipInr(context, 'Paid', paid),
        if (budget > 0) _moneyChipInr(context, 'Due', due),
      ],
    );
    ButtonStyle outlinedPill(ColorScheme cs) => OutlinedButton.styleFrom(
          foregroundColor: cs.primary,
          backgroundColor: Colors.transparent,
          side: BorderSide(color: cs.primary.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          alignment: Alignment.center,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                height: 1.0,
                leadingDistribution: TextLeadingDistribution.even,
                textBaseline: TextBaseline.alphabetic,
              ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          style: outlinedPill(cs),
          onPressed: () => _exportProjectWithProgress(context, ref, project),
          icon: const Icon(CupertinoIcons.arrow_down_doc),
          label: const Text('Export'),
        ),
        if (isOwner && _hasAnyLateInstallments(project))
          OutlinedButton.icon(
            style: outlinedPill(cs),
            onPressed: () => _reportLateInstallments(context, ref, project),
            icon: const Icon(CupertinoIcons.exclamationmark_triangle),
            label: const Text('Report late'),
          ),
        if (user != null && !isCompleted && ((user.role == UserRole.devAdmin) || (user.role == UserRole.superNodal) || (user.role == UserRole.subNodal) || (user.role == UserRole.projectOwner && user.uid == project.ownerId)))
          OutlinedButton.icon(
            style: outlinedPill(cs),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await navigator.push(MaterialPageRoute(builder: (_) => editor.ProjectEditorPage(projectId: project.id)));
            },
            icon: const Icon(CupertinoIcons.pencil),
            label: const Text('Edit'),
          ),
        if (!isCompleted && ((isOwner && workCompleted) || isDevAdmin == true))
          OutlinedButton.icon(
            style: outlinedPill(cs),
            onPressed: () => _confirmMarkAsDone(context, ref, project, user, override: isDevAdmin == true && !workCompleted),
            icon: const Icon(CupertinoIcons.check_mark_circled),
            label: Text(isDevAdmin == true && !workCompleted ? 'Mark as Done (Override)' : 'Mark as Done'),
          ),
        
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: cs.surface, border: Border(bottom: BorderSide(color: cs.outlineVariant))),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, c) {
          final compact = c.maxWidth < 720;
          final titleBlock = Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              GestureDetector(
                onLongPress: () async {
                  await Clipboard.setData(ClipboardData(text: project.id));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project ID copied')));
                },
                child: Text('#${project.id}', style: Theme.of(context).textTheme.labelSmall),
              ),
            ]),
          );
          if (!compact) {
            return Row(
              children: [
                IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(CupertinoIcons.back)),
                const Gap(4),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(CupertinoIcons.building_2_fill, color: cs.primary),
                ),
                const Gap(8),
                titleBlock,
                const Gap(8),
                Flexible(child: Align(alignment: Alignment.centerRight, child: infoChips)),
                const Gap(8),
                actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(CupertinoIcons.back)),
                  const Gap(4),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Icon(CupertinoIcons.building_2_fill, color: cs.primary, size: 18),
                  ),
                  const Gap(8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('#${project.id}', style: Theme.of(context).textTheme.labelSmall),
                    ]),
                  ),
                ],
              ),
              const Gap(8),
              infoChips,
              const Gap(8),
              actions,
            ],
          );
        }),
      ),
    );
  }

  // tabsBuilder removed in unified scroll refactor

  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('projects').doc(project.id).snapshots(),
    builder: (context, snap) {
  final pj = (snap.data != null && snap.data!.data() != null) ? Project.fromDoc(snap.data!) : project;
      // Unified scroll: header + stages + tabs scroll together; TabBar pinned
      final workCompleted = pj.workDescription.stage == WorkStage.completed;
      final canUpdate = (user != null) && (pj.status != ProjectStatus.completed) && !workCompleted && (
        (user.role == UserRole.devAdmin) || (user.role == UserRole.superNodal) || (user.role == UserRole.subNodal) || (user.role == UserRole.projectOwner && user.uid == pj.ownerId)
      );
      return DefaultTabController(
        length: canUpdate ? 5 : 4,
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: NestedScrollView(
            headerSliverBuilder: (context, innerScrolled) => [
              SliverToBoxAdapter(child: header(pj)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: _stagesComposite(context, pj),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedTabBarDelegate(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    child: TabBar(
                      isScrollable: true,
                      tabs: [
                        const Tab(text: 'Details (विवरण)', icon: Icon(CupertinoIcons.doc_plaintext, size: 16)),
                        const Tab(text: 'Attachments (संलग्नक)', icon: Icon(CupertinoIcons.paperclip, size: 16)),
                        const Tab(text: 'Updates (टिप्पणियाँ)', icon: Icon(CupertinoIcons.bubble_left_bubble_right, size: 16)),
                        if (canUpdate) const Tab(text: 'Update (अद्यतन)', icon: Icon(CupertinoIcons.pencil, size: 16)),
                        const Tab(text: 'Owner (स्वामी)', icon: Icon(CupertinoIcons.person, size: 16)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            body: TabBarView(
              children: [
                ListView(
                  key: const PageStorageKey('tab:details'),
                  padding: const EdgeInsets.all(12),
                  children: [
                    _sectionTitle(context, 'Details (विवरण)'),
                    const Gap(8),
                    _detailsSections(context, pj),
                    const Gap(24),
                  ],
                ),
                _AttachmentsTab(project: pj, user: user),
                _UpdatesTab(project: pj, user: user),
                if (canUpdate)
                  ProjectUpdateFormPage(
                    key: const PageStorageKey('tab:update'),
                    project: pj,
                    embedded: true,
                  ),
                ListView(
                  key: const PageStorageKey('tab:owner'),
                  padding: const EdgeInsets.all(12),
                  children: [
                    _sectionTitle(context, 'Owner (स्वामी)'),
                    const Gap(8),
                    Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: _ownerInfo(context, pj),
                      ),
                    ),
                    const Gap(24),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// legacy chips removed in redesign
}

// --- Dialog helpers (restored clean versions using ScrollSafeDialog) ---
Future<void> _confirmMarkAsDone(BuildContext context, WidgetRef ref, Project project, AppUser? user, {bool override = false}) async {
    if (project.status == ProjectStatus.completed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already completed')));
      return;
    }
    final ok = await showScrollSafeDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mark project as done?', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(override
              ? 'You are overriding the completion requirement. Proceed? This will lock the project.'
              : 'This will lock the project. You will not be able to edit details afterwards.'),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark Done')),
          ])
        ],
      ),
    );
    if (ok != true) return;
    try {
      final db = FirebaseFirestore.instance;
      // Update project status
      await db.collection('projects').doc(project.id).update({
        'status': ProjectStatus.completed.name,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      // Add audit update/system comment
      final actor = user?.uid ?? 'system';
      final comment = '[SYSTEM] Project marked as completed by $actor${override ? ' (override)' : ''}';
      await db.collection('projects').doc(project.id).collection('updates').add({
        'phase': 0,
        'comment': comment,
        'photos': <String>[],
        'documents': <String>[],
        'updatedBy': actor,
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(const SnackBar(content: Text('Project marked as completed')));
      }
    } catch (e) {
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

// (Removed unused add note / attach file helpers during repair)

// --- Restored Attachments & Updates Tabs ---

class _AttachmentsTab extends ConsumerWidget {
  final Project project;
  final AppUser? user;
  const _AttachmentsTab({required this.project, required this.user});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    // Project model after repair may have categorized lists directly; adapt gracefully
    final List<_AttachmentEntry> files = [];
    void addList(String label, List<String>? list) {
      if (list == null) return;
      for (final f in list) {
        if (f.isEmpty) continue;
        files.add(_AttachmentEntry(label: label, path: f));
      }
    }
  // Generic top-level media (legacy)
  addList('Photos', project.photoUrls);
  addList('Documents', project.documentUrls);
  // Section 4 categorized documents
  addList('Measurement Books', project.workDescription.measurementBookUrls);
  addList('Test Reports', project.workDescription.testReportUrls);
  addList('Work Reports', project.workDescription.workReportUrls);
  addList('Certificates', project.workDescription.certificateUrls);

    return ListView(
      key: const PageStorageKey('tab:attachments'),
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle(context, 'Attachments (संलग्नक)'),
        const Gap(8),
        if (files.isEmpty)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('No attachments uploaded', style: Theme.of(context).textTheme.bodyMedium),
            ),
          )
        else
          ...files.map((e) => Card(
                elevation: 0,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: _attachmentIcon(context, e.path),
                  title: Text(e.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  // Removed subtitle (labels) per request
                  trailing: AttachmentButton(
                    fileName: e.fileName,
                    resolveUrl: () async => storage.getDownloadURL(e.path),
                  ),
                ),
              )),
        const Gap(80),
      ],
    );
  }
}

class _AttachmentEntry {
  final String label;
  final String path;
  _AttachmentEntry({required this.label, required this.path});
  String get fileName => path.split('/').last;
}

Widget _attachmentIcon(BuildContext context, String path) {
  final lower = path.toLowerCase();
  final cs = Theme.of(context).colorScheme;
  IconData icon;
  Color bg;
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.svg')) {
    icon = CupertinoIcons.photo_on_rectangle;
    bg = cs.primary.withValues(alpha: 0.10);
  } else if (lower.endsWith('.pdf')) {
    icon = Icons.picture_as_pdf_outlined;
    bg = Colors.red.withValues(alpha: 0.12);
  } else if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
    icon = Icons.description_outlined;
    bg = cs.secondary.withValues(alpha: 0.12);
  } else if (lower.endsWith('.xls') || lower.endsWith('.xlsx') || lower.endsWith('.csv')) {
    icon = Icons.grid_on_outlined;
    bg = Colors.green.withValues(alpha: 0.12);
  } else if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) {
    icon = Icons.archive_outlined;
    bg = cs.outlineVariant.withValues(alpha: 0.20);
  } else {
    icon = CupertinoIcons.doc_text;
    bg = cs.outlineVariant.withValues(alpha: 0.16);
  }
  return Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: bg.withValues(alpha: 0.4), width: 1),
    ),
    child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
  );
}

class _UpdatesTab extends ConsumerWidget {
  final Project project;
  final AppUser? user;
  const _UpdatesTab({required this.project, required this.user});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(projectRepositoryProvider);
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ProjectUpdate>>(
            stream: repo.watchUpdates(project.id),
            builder: (context, snap) {
              final list = snap.data ?? const <ProjectUpdate>[];
              if (snap.connectionState == ConnectionState.waiting && list.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (list.isEmpty) {
                return Center(
                  child: Text('No updates yet', style: Theme.of(context).textTheme.bodyMedium),
                );
              }
              return ListView.builder(
                key: const PageStorageKey('tab:updates'),
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final u = list[i];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(CupertinoIcons.bubble_left_bubble_right, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(u.comment?.trim().isNotEmpty == true ? u.comment!.trim() : '(No comment)',
                                style: const TextStyle(fontWeight: FontWeight.w500), maxLines: 4, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            Wrap(spacing: 12, runSpacing: 4, children: [
                              _metaChip(context, '#${u.phase}'),
                              _metaChip(context, _fmtDateTime(u.createdAt) ?? '—'),
                            ]),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
  if (user != null && (user!.role == UserRole.superNodal || user!.role == UserRole.subNodal || user!.role == UserRole.devAdmin))
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: FloatingActionButton.extended(
                  heroTag: 'addUpdate',
                  onPressed: () => _showAddCommentDialog(context, ref, project, user!),
                  icon: const Icon(CupertinoIcons.add),
                  label: const Text('Add Comment'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Widget _metaChip(BuildContext context, String text) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: cs.outlineVariant),
    ),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );
}

Future<void> _showAddCommentDialog(BuildContext context, WidgetRef ref, Project project, AppUser user) async {
  final controller = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showScrollSafeDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New Comment', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(hintText: 'Enter comment...'),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ])
        ],
      ),
    ),
  );
  if (ok == true && controller.text.trim().isNotEmpty) {
    try {
      final repo = ref.read(projectRepositoryProvider);
      final update = ProjectUpdate(
        id: 'temp',
        projectId: project.id,
        phase: project.phase,
        comment: controller.text.trim(),
        updatedBy: user.uid,
        createdAt: DateTime.now(),
      );
      await repo.addUpdate(project.id, update);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
  controller.dispose();
}

String? _fmtDateTime(DateTime? dt) {
  if (dt == null) return null;
  return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// (Removed unused _updatesList during repair)

// New details sections containerized per block for clear visual rhythm inside the Details tab
Widget _detailsSections(BuildContext context, Project project) {
  final cs = Theme.of(context).colorScheme;
  Widget section(String title, List<Widget> children) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const Gap(10),
            ...children,
          ]),
        ),
      );

  // Reuse the existing row helpers to build fields
  final prelim = <Widget>[
    _kv(context, CupertinoIcons.building_2_fill, 'Gram Panchayat (ग्राम पंचायत)', project.preliminaryDescription.gramPanchayat),
    _kv(context, CupertinoIcons.location, 'Address (पता)', project.address),
    _kvPhone(context, 'Sarpanch (सरपंच)', project.preliminaryDescription.sarpanchName, project.preliminaryDescription.sarpanchMobile),
    _kvPhone(context, 'Secretary (सचिव)', project.preliminaryDescription.secretaryName, project.preliminaryDescription.secretaryMobile),
    _kvPhone(context, 'Sub Engineer (उप अभियंता)', project.preliminaryDescription.subEngineerName, project.preliminaryDescription.subEngineerMobile),
  ];

  final sanction = <Widget>[
    _kv(context, CupertinoIcons.checkmark_seal, 'Sanction Dept. (स्वीकृत विभाग)', project.sanctionCompliance.sanctioningDepartmentName),
    _kv(context, CupertinoIcons.square_list, 'Scheme / Plan (योजना / मद)', _joined([project.sanctionCompliance.schemeName, project.sanctionCompliance.planHeadName])),
    _kv(context, CupertinoIcons.doc_text, 'Work Name (कार्य का नाम)', project.sanctionCompliance.itemName),
    _kv(context, CupertinoIcons.number, 'Tech Approval No. (तकनीकी स्वीकृति क्रमांक)', project.sanctionCompliance.technicalApprovalNo),
    _kv(context, CupertinoIcons.calendar, 'Tech Approval Date (तकनीकी स्वीकृति तिथि)', _fmtDate(project.sanctionCompliance.technicalApprovalDate)),
    _kv(context, CupertinoIcons.checkmark_shield, 'Admin Approval No. (प्रशासनिक स्वीकृति क्रमांक)', project.sanctionCompliance.adminApprovalNo),
    _kv(context, CupertinoIcons.calendar, 'Admin Approval Date (प्रशासनिक स्वीकृति तिथि)', _fmtDate(project.sanctionCompliance.adminApprovalDate)),
    if (project.sanctionCompliance.approvedAmount != null)
      _kv(context, Icons.currency_rupee, 'Approved Amount (स्वीकृत राशि)', _fmtMoneyInr(project.sanctionCompliance.approvedAmount)),
    if (project.sanctionCompliance.approvedAmount != null)
      Padding(
        padding: const EdgeInsets.only(left: 36.0, bottom: 6.0),
        child: Text('${_fmtMoneyInr(project.sanctionCompliance.approvedAmount)}  •  ${_rupeesInWords((project.sanctionCompliance.approvedAmount ?? 0).round())}', style: Theme.of(context).textTheme.labelSmall),
      ),
  ];

  final allot = <Widget>[
  if (_hasInstallmentData(project.allotmentDetails.installment1)) _installmentRow(context, 'Installment 1 (किस्त 1)', project.allotmentDetails.installment1),
  if (_hasInstallmentData(project.allotmentDetails.installment2)) _installmentRow(context, 'Installment 2 (किस्त 2)', project.allotmentDetails.installment2),
  if (_hasInstallmentData(project.allotmentDetails.installment3)) _installmentRow(context, 'Installment 3 (किस्त 3)', project.allotmentDetails.installment3),
    _kv(context, CupertinoIcons.building_2_fill, 'Bank (बैंक)', _bank(project.allotmentDetails.bankDetails)),
  ];

  final work = <Widget>[
    _kv(context, CupertinoIcons.calendar_today, 'Start Date (आरंभ तिथि)', _fmtDate(project.workDescription.startDate ?? project.createdAt)),
    _kv(context, CupertinoIcons.calendar, 'End Date (समाप्ति तिथि)', _fmtDate(project.workDescription.endDate) ?? '(Not Entered)'),
  _kv(context, CupertinoIcons.cube_box, 'Current stage (वर्तमान चरण)', project.workDescription.stage?.name),
    _mapRow(context, project),
  ];

  return LayoutBuilder(builder: (context, c) {
    final twoCol = c.maxWidth > 900; // slightly larger threshold for better breathing space
    final left = [
      section('Preliminary (प्राथमिक)', prelim),
      const Gap(12),
      section('Sanction & Compliance (स्वीकृति एवं अनुपालन)', sanction),
      const Gap(12),
      section('Allotment (आवंटन)', allot),
      const Gap(12),
      section('Work (कार्य)', work),
    ];
    final right = [
      section('Financials (वित्तीय)', [
        _financialCard(context, project),
      ]),
    ];
    if (twoCol) {
      // On large screens, move Allotment below Financials on the right
      final leftWide = [
        section('Preliminary (प्राथमिक)', prelim),
        const Gap(12),
        section('Sanction & Compliance (स्वीकृति एवं अनुपालन)', sanction),
        const Gap(12),
        section('Work (कार्य)', work),
      ];
      final rightWide = [
        section('Financials (वित्तीय)', [
          _financialCard(context, project),
        ]),
        const Gap(12),
        section('Allotment (आवंटन)', allot),
      ];
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(children: leftWide)),
        const Gap(16),
        Expanded(child: Column(children: rightWide)),
      ]);
    }
    // Mobile-first: keep natural order with Allotment after Sanction & Compliance
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...left, const Gap(12), ...right]);
  });
}

Widget _ownerInfo(BuildContext context, Project project) {
  final db = FirebaseFirestore.instance;
  return FutureBuilder(
    future: db.collection('users').doc(project.ownerId).get(),
    builder: (context, snap) {
      final fallback = (snap.data?.data() ?? const <String, dynamic>{});
      final map = {
        ...fallback,
        ...project.ownerDetails, // prefer embedded snapshot when available
      };
      final displayName = (map['displayName'] as String?)?.trim();
      final email = (map['email'] as String?)?.trim();
      final phone = (map['phone'] as String?)?.trim();
      final whatsapp = (map['whatsapp'] as String?)?.trim();
      final address = (map['address'] as String?)?.trim();
      final aadhar = (map['aadhar'] as String?)?.trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(context, CupertinoIcons.person, 'Owner ID', project.ownerId),
          _kv(context, CupertinoIcons.profile_circled, 'Name', displayName?.isEmpty == true ? null : displayName ?? '(empty)'),
          _kv(context, CupertinoIcons.mail, 'Email', email?.isEmpty == true ? null : email ?? '(empty)'),
          _kvPhone(context, 'Phone', displayName, phone),
          _kvWhatsApp(context, 'WhatsApp', whatsapp),
          _kv(context, CupertinoIcons.location, 'Address', (address == null || address.isEmpty) ? '(empty)' : address),
          _kv(context, CupertinoIcons.person_crop_square, 'Aadhaar', (aadhar == null || aadhar.isEmpty) ? '(empty)' : aadhar),
        ],
      );
    },
  );
}

Widget _kvWhatsApp(BuildContext context, String label, String? whatsapp) {
  final v = (whatsapp ?? '').trim();
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
      children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), shape: BoxShape.circle), child: Icon(CupertinoIcons.chat_bubble_text, size: 16, color: cs.primary)),
        const SizedBox(width: 8),
        SizedBox(width: 160, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(width: 8),
        Expanded(child: Text(v.isEmpty ? '(empty)' : '+91 $v', style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
        if (v.length == 10)
          IconButton(
            tooltip: 'WhatsApp',
            icon: const Icon(CupertinoIcons.chat_bubble_2_fill, size: 18),
            onPressed: () async {
              final uri = Uri.parse('https://wa.me/91$v');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
      ],
    ),
  );
}

// Section label helper
Widget _sectionTitle(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
  child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
  );
}

// Compact info chip helpers
Widget _chip(BuildContext context, IconData icon, String label) {
  final cs = Theme.of(context).colorScheme;
  return LayoutBuilder(builder: (context, c) {
    final narrow = c.maxWidth < 160;
    final content = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                height: 1.0,
                leadingDistribution: TextLeadingDistribution.even,
                textBaseline: TextBaseline.alphabetic,
              ),
          overflow: TextOverflow.ellipsis,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: true,
            applyHeightToLastDescent: true,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
      ),
    ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: narrow ? FittedBox(fit: BoxFit.scaleDown, child: content) : content,
    );
  });
}

Widget _chipColored(BuildContext context, IconData icon, String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: true,
          applyHeightToLastDescent: true,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    ]),
  );
}

// Helpers for details layout

Widget _kv(BuildContext context, IconData icon, String key, String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return const SizedBox.shrink();
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
      children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), shape: BoxShape.circle), child: Icon(icon, size: 16, color: cs.primary)),
        const SizedBox(width: 8),
        SizedBox(width: 160, child: Text(key, style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onLongPress: () async {
              await Clipboard.setData(ClipboardData(text: v));
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
            },
            child: Text(v, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    ),
  );
}

Widget _kvPhone(BuildContext context, String label, String? name, String? phone) {
  final display = _namePhone(name, phone);
  if ((display ?? '').isEmpty) return const SizedBox.shrink();
  final cs = Theme.of(context).colorScheme;
  final phoneDigits = (phone ?? '').trim();
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
      children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), shape: BoxShape.circle), child: Icon(CupertinoIcons.phone_fill, size: 16, color: cs.primary)),
        const SizedBox(width: 8),
        SizedBox(width: 160, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(width: 8),
        Expanded(child: Text(display!, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
        if (phoneDigits.length == 10)
          IconButton(
            tooltip: 'Call',
            icon: const Icon(CupertinoIcons.phone_solid, size: 18),
            onPressed: () async {
              final uri = Uri.parse('tel:+91$phoneDigits');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
          ),
      ],
    ),
  );
}

// Installment row with received indicator (down arrow when received)
Widget _installmentRow(BuildContext context, String label, Installment? i) {
  final cs = Theme.of(context).colorScheme;
  final amount = i?.amount;
  final date = i?.date;
  final rec = i?.receivedAmount;
  final recDate = i?.receivedDate;
  String primaryLine = '';
  if (amount != null) primaryLine += 'Amt: ${_fmtMoneyInr(amount)}';
  if (date != null) primaryLine += '${primaryLine.isEmpty ? '' : '  •  '}Date: ${_fmtDate(date)}';
  final now = DateTime.now();
  final isLate = (rec == null) && (date != null) && date.isBefore(DateTime(now.year, now.month, now.day));
  final lateDays = isLate ? DateTime(now.year, now.month, now.day).difference(DateTime(date.year, date.month, date.day)).inDays : 0;
  final receivedWidget = rec == null
      ? Text('(not received)', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7)))
      : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.arrow_down_circle_fill, size: 16, color: Colors.green),
            const SizedBox(width: 6),
            Text('${_fmtMoneyInr(rec)} on ${_fmtDate(recDate)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.green.shade700)),
          ],
        );
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 520;
      final icon = Container(width: 28, height: 28, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), shape: BoxShape.circle), child: Icon(CupertinoIcons.creditcard, size: 16, color: cs.primary));
      final left = SizedBox(width: 160, child: Text(label, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis));
      final right = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (primaryLine.isNotEmpty) Text(primaryLine, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
        Row(children:[
          receivedWidget,
          if (isLate) ...[
            const SizedBox(width: 8),
            _chipColored(context, CupertinoIcons.exclamationmark_triangle_fill, 'Late by $lateDays days', Colors.orange),
          ]
        ]),
      ]);
      if (narrow) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [icon, const SizedBox(width: 8), Expanded(child: left)]),
          const SizedBox(height: 6),
          right,
        ]);
      }
      return Row(children: [icon, const SizedBox(width: 8), left, const SizedBox(width: 8), Expanded(child: right)]);
    }),
  );
}

bool _hasInstallmentData(Installment? i) {
  if (i == null) return false;
  return (i.amount != null && (i.amount ?? 0) > 0) || i.date != null || (i.receivedAmount != null && (i.receivedAmount ?? 0) > 0) || i.receivedDate != null;
}

String _joined(List<String?> parts) => parts.whereType<String>().where((e) => e.trim().isNotEmpty).join(' / ');

String? _namePhone(String? name, String? phone) {
  final n = (name ?? '').trim();
  final p = (phone ?? '').trim();
  if (n.isEmpty && p.isEmpty) return null;
  if (n.isEmpty) return p;
  if (p.isEmpty) return n;
  return '$n • +91 $p';
}

String? _installment(Installment? i) {
  if (i == null) return null;
  final a = i.amount?.toString();
  final d = i.date;
  final ar = i.receivedAmount?.toString();
  final dr = i.receivedDate;
  final parts = <String>[];
  if (a != null) parts.add('Amt: $a');
  if (d != null) parts.add('Date: ${fmtYmd(d.toLocal())}');
  if (ar != null) parts.add('Rec: $ar');
  if (dr != null) parts.add('Rec on: ${fmtYmd(dr.toLocal())}');
  return parts.isEmpty ? null : parts.join('  •  ');
}

String? _bank(BankDetails? b) {
  if (b == null) return null;
  final parts = [b.bankName, b.branch, b.ifsc];
  return _joined(parts);
}

// Build and share/export a PDF with all text details
// old single PDF export removed in favor of progress-based exporter

// Modern status chip
Widget _statusChip(BuildContext context, ProjectStatus status) {
  Color c; IconData ic; String text;
  switch (status) {
    case ProjectStatus.completed:
      c = Colors.green; ic = CupertinoIcons.check_mark_circled_solid; text = 'Completed'; break;
    case ProjectStatus.cancelled:
      c = Colors.grey; ic = CupertinoIcons.xmark_circle_fill; text = 'Cancelled'; break;
    case ProjectStatus.in_progress:
      c = Colors.orange; ic = CupertinoIcons.clock_solid; text = 'In progress'; break;
  }
  return _chipColored(context, ic, text, c);
}

// Money chip with accent border outline (Budget/Paid/Due)
Widget _moneyChipInr(BuildContext context, String label, num value) {
  final s = _fmtMoneyInr(value);
  final cs = Theme.of(context).colorScheme;
  final content = Row(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.currency_rupee, size: 14),
    const SizedBox(width: 6),
    Text(
      '$label: $s',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(height: 1.0, leadingDistribution: TextLeadingDistribution.even, textBaseline: TextBaseline.alphabetic),
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
        leadingDistribution: TextLeadingDistribution.even,
      ),
    ),
  ]);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest, // keep same fill as other chips
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.primary.withValues(alpha: 0.6)), // accent outline
    ),
    child: content,
  );
}

String _fmtMoneyInr(num? n) {
  if (n == null) return '₹0';
  // Indian numbering format short units
  final v = n.abs();
  String sign = n < 0 ? '-' : '';
  if (v >= 10000000) return '₹$sign${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹$sign${(v / 100000).toStringAsFixed(2)} L';
  // For smaller values, show full Indian digit-grouping (12,34,567)
  final grouped = _formatIndianGrouping(v.round());
  return '₹$sign$grouped';
}

String _formatIndianGrouping(int value) {
  final s = value.toString();
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  String rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

String _rupeesInWords(int n) {
  if (n == 0) return 'zero rupees';
  String two(int x) {
    const ones = ['zero','one','two','three','four','five','six','seven','eight','nine','ten','eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen'];
    const tens = ['', '', 'twenty','thirty','forty','fifty','sixty','seventy','eighty','ninety'];
    if (x < 20) return ones[x];
    final t = x ~/ 10, o = x % 10;
    return tens[t] + (o > 0 ? '-${ones[o]}' : '');
  }
  String three(int x) {
    final h = x ~/ 100; final r = x % 100;
    if (h == 0) return two(r);
    final head = '${two(h)} hundred';
    if (r == 0) return head;
    return '$head ${two(r)}';
  }
  final crore = n ~/ 10000000;
  final lakh = (n % 10000000) ~/ 100000;
  final thousand = (n % 100000) ~/ 1000;
  final hundred = n % 1000;
  final parts = <String>[];
  if (crore > 0) parts.add('${two(crore)} crore');
  if (lakh > 0) parts.add('${two(lakh)} lakh');
  if (thousand > 0) parts.add('${two(thousand)} thousand');
  if (hundred > 0) parts.add(three(hundred));
  return '${parts.join(' ')} rupees';
}

num _computeOverdueAmount(Project project) {
  // Overdue = sum of installment amounts whose due date is past, not yet received
  num total = 0;
  void addIfLate(Installment? i) {
    if (i == null) return;
    if (i.receivedAmount != null && (i.receivedAmount ?? 0) > 0) return;
    final d = i.date;
    if (d == null) return;
    final today = DateTime.now();
    if (DateTime(d.year, d.month, d.day).isBefore(DateTime(today.year, today.month, today.day))) {
      total += (i.amount ?? 0);
    }
  }
  addIfLate(project.allotmentDetails.installment1);
  addIfLate(project.allotmentDetails.installment2);
  addIfLate(project.allotmentDetails.installment3);
  return total;
}

// ---------------- Stages Timeline (extracted working version) ----------------
Widget _stagesComposite(BuildContext context, Project project) {
  final cs = Theme.of(context).colorScheme;
  return Card(
    elevation: 0,
    color: Colors.transparent,
    child: Padding(
      padding: const EdgeInsets.all(14.0),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 720;
        Widget dateBox({required IconData icon, required String label, required DateTime? date}) => Container(
              constraints: const BoxConstraints(minWidth: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.06),
                border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 22, color: cs.primary),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.primary)),
                  Text(
                    date == null ? '(not entered)' : _fmtDate(date)!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ]),
              ]),
            );
        final timeline = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: _stageTimeline(context, project.workDescription.stage),
        );
        final left = dateBox(icon: Icons.event, label: 'Start', date: project.workDescription.startDate ?? project.createdAt);
        final right = dateBox(icon: Icons.event_available, label: 'End (planned)', date: project.workDescription.endDate);
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            left,
            const SizedBox(height: 12),
            timeline,
            const SizedBox(height: 12),
            right,
          ]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
          children: [
            left,
            const SizedBox(width: 14),
            Expanded(child: Align(alignment: Alignment.center, child: timeline)),
            const SizedBox(width: 14),
            right,
          ],
        );
      }),
    ),
  );
}

Widget _stageTimeline(BuildContext context, WorkStage? current) => _StageTimeline(current: current);

class _StageTimeline extends StatefulWidget {
  final WorkStage? current;
  const _StageTimeline({required this.current});
  @override
  State<_StageTimeline> createState() => _StageTimelineState();
}

class _StageTimelineState extends State<_StageTimeline> {
  static const double _itemExtent = 90.0;
  static const Duration _step = Duration(milliseconds: 240);
  int _revealed = 0; // how many steps are revealed
  int _gen = 0; // cancellation token
  bool _reduceMotion = false;

  int get _idx => widget.current == null ? -1 : WorkStage.values.indexOf(widget.current!);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void initState() {
    super.initState();
    _kick();
  }

  @override
  void didUpdateWidget(covariant _StageTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current) {
      _kick();
    }
  }

  Future<void> _kick() async {
    final idx = _idx;
    final my = ++_gen;
    if (idx < 0) {
      setState(() => _revealed = 0);
      return;
    }
    if (_reduceMotion) {
      setState(() => _revealed = idx + 1);
      return;
    }
    setState(() => _revealed = 0);
    for (int i = 0; i <= idx; i++) {
      if (!mounted || _gen != my) return;
      await Future.delayed(_step);
      if (!mounted || _gen != my) return;
      setState(() => _revealed = i + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = WorkStage.values;
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final totalWidth = steps.length * _itemExtent;
      final width = totalWidth > c.maxWidth ? c.maxWidth : totalWidth;
      Color colorFor(int i) {
        if (i == (_revealed - 1) && i == _idx) return cs.primary; // current
        if (i < (_revealed - 1)) return cs.outline; // past
        return cs.outlineVariant; // future
      }
      return SizedBox(
        height: 124,
        child: Center(
          child: SizedBox(
            width: width,
            child: Timeline.tileBuilder(
              theme: TimelineThemeData(
                direction: Axis.horizontal,
                connectorTheme: ConnectorThemeData(thickness: 4, color: cs.outlineVariant),
                indicatorTheme: IndicatorThemeData(size: 36, color: cs.primary),
              ),
              builder: TimelineTileBuilder.connected(
                itemCount: steps.length,
                indicatorBuilder: (context, i) {
                  final icon = Icon(_iconForStage(steps[i]), color: colorFor(i), size: 24);
                  final child = Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (i == _idx) ? colorFor(i).withValues(alpha: 0.12) : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: colorFor(i)),
                    ),
                    child: icon,
                  );
                  final revealed = i < _revealed;
                  return AnimatedScale(
                    scale: revealed ? 1.0 : 0.6,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: child,
                  );
                },
                connectorBuilder: (context, i, type) {
                  final active = i < (_revealed - 1);
                  return SolidLineConnector(color: active ? cs.primary : cs.outlineVariant);
                },
                contentsBuilder: (context, i) {
                  final label = _labelForStage(steps[i]);
                  final active = (i == _idx) && i < _revealed;
                  return Padding(
                    padding: const EdgeInsets.only(top: 10.0, left: 8, right: 8),
                    child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: active ? cs.primary : null)),
                  );
                },
                nodePositionBuilder: (context, index) => 0.5,
                indicatorPositionBuilder: (_, __) => 0.5,
                itemExtentBuilder: (_, __) => _itemExtent,
              ),
            ),
          ),
        ),
      );
    });
  }
}

IconData _iconForStage(WorkStage s) {
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

String _labelForStage(WorkStage s) {
  switch (s) {
    case WorkStage.layout:
      return 'Layout';
    case WorkStage.plinth:
      return 'Plinth';
    case WorkStage.lintel:
      return 'Lintel';
    case WorkStage.finishing:
      return 'Finishing';
    case WorkStage.completed:
      return 'Completed';
  }
}

// (Removed unused timeline composite during repair)

// (Removed stage icon helper)

// Financial summary card with charts
Widget _financialCard(BuildContext context, Project project) {
  final cs = Theme.of(context).colorScheme;
  final budget = (project.sanctionCompliance.approvedAmount ?? 0).toDouble();
  final i1 = project.allotmentDetails.installment1;
  final i2 = project.allotmentDetails.installment2;
  final i3 = project.allotmentDetails.installment3;
  final paid = ((i1?.receivedAmount ?? 0) + (i2?.receivedAmount ?? 0) + (i3?.receivedAmount ?? 0)).toDouble();
  final remaining = (budget - paid).clamp(0, double.infinity);
  final sections = <PieChartSectionData>[
    if (paid > 0)
      PieChartSectionData(
        color: cs.primary, // accent for paid
        value: paid,
        title: 'Paid',
        radius: 38,
        titleStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
      ),
    if (remaining > 0)
      PieChartSectionData(
        color: Colors.grey, // grey for due
        value: remaining.toDouble(),
        title: 'Due',
        radius: 38,
        titleStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
      ),
  ];

  BarChartGroupData bar(String label, num? planned, num? got, int x) {
    final p = (planned ?? 0).toDouble();
    final g = (got ?? 0).toDouble();
    return BarChartGroupData(x: x, barsSpace: 4, barRods: [
      BarChartRodData(toY: p, color: cs.outlineVariant, width: 8, borderRadius: BorderRadius.circular(2)), // due/plan as grey
      BarChartRodData(toY: g, color: cs.primary, width: 8, borderRadius: BorderRadius.circular(2)), // paid as accent
    ]);
  }

  Widget bars() {
    final items = <MapEntry<String, Installment?>>[];
    if (_hasInstallmentData(i1)) items.add(MapEntry('Installment 1', i1));
    if (_hasInstallmentData(i2)) items.add(MapEntry('Installment 2', i2));
    if (_hasInstallmentData(i3)) items.add(MapEntry('Installment 3', i3));
    if (items.isEmpty) {
      return Center(child: Text('No installment data', style: Theme.of(context).textTheme.labelSmall));
    }
    final groups = <BarChartGroupData>[];
    for (var idx = 0; idx < items.length; idx++) {
      final e = items[idx];
      groups.add(bar(e.key, e.value?.amount, e.value?.receivedAmount, idx));
    }
    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          barGroups: groups,
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= items.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(items[i].key, style: Theme.of(context).textTheme.labelSmall),
              );
            })),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = rodIndex == 1 ? 'Paid' : 'Due';
              final amt = rod.toY;
              return BarTooltipItem('$label\n${_fmtMoneyInr(amt)}\n${_rupeesInWords(amt.round())}', const TextStyle(color: Colors.white));
            }),
          ),
        ),
      ),
    );
  }

  return Card(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
    child: Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title removed: outer section already provides heading
        LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 720;
          Widget legend() => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Paid  •  ${_fmtMoneyInr(paid)}  •  ${_rupeesInWords(paid.round())}', softWrap: true, maxLines: 3, style: Theme.of(context).textTheme.labelSmall)),
                  ]),
                  const SizedBox(height: 4),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Due  •  ${_fmtMoneyInr(remaining)}  •  ${_rupeesInWords(remaining.round())}', softWrap: true, maxLines: 3, style: Theme.of(context).textTheme.labelSmall)),
                  ]),
                ],
              );

          final barsWithBorder = Container(
            height: 150,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: bars(),
          );
          final piePane = SizedBox(
            width: 220,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 160,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: (budget <= 0)
                      ? Center(child: Text('No budget', style: Theme.of(context).textTheme.labelSmall))
                      : PieChart(
                          PieChartData(
                            sections: sections,
                            centerSpaceRadius: 42,
                            sectionsSpace: 2,
                            pieTouchData: PieTouchData(enabled: true),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                legend(),
              ],
            ),
          );

          return narrow
      ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Installments (planned vs received)', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 8),
        barsWithBorder,
                    const SizedBox(height: 16),
                    Row(children: [Icon(CupertinoIcons.chart_pie, size: 16, color: cs.primary), const SizedBox(width: 6), Text('Paid vs Due', style: Theme.of(context).textTheme.labelSmall)]),
                    const SizedBox(height: 8),
                    piePane,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Installments (planned vs received)', style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 8),
          barsWithBorder,
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Flexible(flex: 2, child: piePane),
                  ],
                );
        }),
      ]),
    ),
  );
}

// (Removed stage label helper)

// Full export with progress (PDF + attachments)
class _Link { final String name; final String url; const _Link(this.name, this.url); }

Future<void> _exportProjectWithProgress(BuildContext context, WidgetRef ref, Project project) async {
  final storage = ref.read(storageServiceProvider);
  final controller = ValueNotifier<_ExportProgress>(_ExportProgress(stage: 'Preparing', done: 0, total: 0));

  // Present scroll-safe dialog (non-await so work continues while visible)
  // User may close after completion; progress remains until then.
  // We deliberately do not allow barrier dismiss to avoid accidental cancellation mid-export.
  // (showScrollSafeDialog currently has fixed barrier policy; cancel via Close button only.)
  // If showScrollSafeDialog is not imported yet, ensure import of scroll_safe_dialog.dart exists at file top.
  // ignore: unused_result
  showScrollSafeDialog<void>(
    context: context,
    builder: (ctx) => ValueListenableBuilder<_ExportProgress>(
      valueListenable: controller,
      builder: (ctx, p, _) {
        final donePct = p.total == 0 ? null : (p.done / p.total).clamp(0, 1).toDouble();
        final finished = p.stage.toLowerCase().contains('done');
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Exporting statement', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(p.stage, style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: donePct),
            const SizedBox(height: 8),
            if (p.message != null) Text(p.message!, style: Theme.of(ctx).textTheme.bodySmall),
            if (p.savedPaths.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Saved Files', style: Theme.of(ctx).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140, maxWidth: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: p.savedPaths.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text('• $e', style: Theme.of(ctx).textTheme.labelSmall),
                  )).toList(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: finished ? () => Navigator.of(ctx).pop() : null,
                icon: const Icon(CupertinoIcons.xmark_circle),
                label: Text(finished ? 'Close' : 'Working…'),
              ),
            ),
          ],
        );
      },
    ),
  );

  try {
    // 1) Gather attachments by category and resolve URLs (for PDF hyperlinks only)
    final categories = <String, List<String>>{
      'Documents': List.of(project.documentUrls),
      'Photos': List.of(project.photoUrls),
      'Measurement Books': List.of(project.workDescription.measurementBookUrls),
      'Test Reports': List.of(project.workDescription.testReportUrls),
      'Work Reports': List.of(project.workDescription.workReportUrls),
      'Certificates': List.of(project.workDescription.certificateUrls),
    };
    controller.value = controller.value.copyWith(stage: 'Creating PDF…', total: 1, done: 0);
    final resolved = <String, List<_Link>>{};
    for (final entry in categories.entries) {
      final list = <_Link>[];
      for (final path in entry.value) {
        String url;
        try { url = await storage.getDownloadURL(path); } catch (_) { url = path; }
        final name = path.split('/').last;
        list.add(_Link(name, url));
      }
      resolved[entry.key] = list;
    }

    // Owner name (best effort)
    String? ownerName;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(project.ownerId).get();
      ownerName = (snap.data() ?? const <String, dynamic>{})['displayName'] as String?;
    } catch (_) {}

    final pdfBytes = await _buildProjectPdf(project, resolved, ownerName: ownerName);
    final pdfName = '${project.id}_export';
    final savedPdf = await _saveBytes('$pdfName.pdf', pdfBytes, 'pdf');
    controller.value = controller.value.copyWith(done: 1, message: 'PDF saved to ${savedPdf ?? 'Downloads'}', savedPaths: [...controller.value.savedPaths, savedPdf ?? 'Downloads/$pdfName.pdf']);
  // No attachment downloads; attachments are linked inside the PDF
  controller.value = controller.value.copyWith(stage: 'Done', message: 'Export complete. Attachments are linked inside the PDF; no files were downloaded.');
  } finally {
    // keep dialog open until user closes
  }
}

Future<Uint8List> _buildProjectPdf(
  Project project,
  Map<String, List<_Link>> linksByCategory, {
  String? ownerName,
}) async {
  // Prepare a Unicode-capable theme using Google Noto fonts (covers Devanagari and ₹)
  pw.Document doc;
  try {
    final theme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.notoSansDevanagariRegular(),
      bold: await PdfGoogleFonts.notoSansDevanagariBold(),
    );
    doc = pw.Document(theme: theme);
  } catch (_) {
    // Fallback to default theme if fonts fail to load (e.g., offline)
    doc = pw.Document();
  }
  // Load app logo once
  Uint8List? logoBytes;
  try {
    final data = await rootBundle.load('assets/logo.png');
    logoBytes = data.buffer.asUint8List();
  } catch (_) {}
  pw.Widget header() => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoBytes != null) pw.Image(pw.MemoryImage(logoBytes), height: 18),
            if (logoBytes != null) pw.SizedBox(width: 8),
            pw.Text('Nirmad - Project Statement', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Spacer(),
            pw.Text('#${project.id}', style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      );

  final pageTheme = pw.PageTheme(
  margin: const pw.EdgeInsets.all(48),
  );

  String? sanitize(String? v) => v?.replaceAll(RegExp(r'[•–—]'), '-');
  pw.Widget kv(String k, String? v) => v == null || v.trim().isEmpty
      ? pw.SizedBox()
      : pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.SizedBox(width: 140, child: pw.Text(k, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Text(sanitize(v)!, style: const pw.TextStyle(fontSize: 11))),
          ]),
        );
  final budget = project.sanctionCompliance.approvedAmount ?? 0;
  final paid = (project.allotmentDetails.installment1?.receivedAmount ?? 0) +
      (project.allotmentDetails.installment2?.receivedAmount ?? 0) +
      (project.allotmentDetails.installment3?.receivedAmount ?? 0);
  final due = _computeOverdueAmount(project);
  // Page 1: Centered logo and summary
  doc.addPage(pw.MultiPage(
    pageTheme: pageTheme,
    build: (c) => [
      if (logoBytes != null) pw.Center(child: pw.Image(pw.MemoryImage(logoBytes), height: 96)),
      pw.SizedBox(height: 8),
      pw.Center(child: pw.Text('Project Statement', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 6),
      pw.Center(child: pw.Text(project.name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 2),
      pw.Center(child: pw.Text('Project ID: ${project.id}', style: const pw.TextStyle(fontSize: 10))),
      pw.SizedBox(height: 14),
      pw.Text('Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      kv('Status', project.status.name),
  kv('Current stage', project.workDescription.stage?.name),
      kv('Financial Phase', project.phase > 0 ? '${project.phase}' : null),
  kv('Budget', budget == 0 ? null : _fmtMoneyInr(budget)),
  kv('Paid', paid == 0 ? null : _fmtMoneyInr(paid)),
  kv('Due', budget == 0 ? null : _fmtMoneyInr(due)),
  kv('Start Date', _fmtDate(project.workDescription.startDate ?? project.createdAt)),
  kv('End Date', _fmtDate(project.workDescription.endDate) ?? '(Not Entered)'),
      pw.SizedBox(height: 10),
      pw.Text('People & Roles', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      kv('Handled by (Owner)', ownerName ?? project.ownerId),
      kv('Verified / Under guidance (Sub Nodal)', '__________________________'),
      kv('Supervision by (Super Nodal)', '__________________________'),
    ],
  ));

  // Page 2: Preliminary + Sanction & Compliance
  doc.addPage(pw.MultiPage(
    pageTheme: pageTheme,
    header: (_) => header(),
    build: (c) => [
      pw.Text('Basic Details', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      kv('Address', project.address),
      kv('Block', project.blockId),
      kv('Village', project.villageId),
      pw.SizedBox(height: 8),
      pw.Text('Preliminary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      kv('Gram Panchayat', project.preliminaryDescription.gramPanchayat),
      kv('Sarpanch', _namePhone(project.preliminaryDescription.sarpanchName, project.preliminaryDescription.sarpanchMobile)),
      kv('Secretary', _namePhone(project.preliminaryDescription.secretaryName, project.preliminaryDescription.secretaryMobile)),
      kv('Sub Engineer', _namePhone(project.preliminaryDescription.subEngineerName, project.preliminaryDescription.subEngineerMobile)),
      pw.SizedBox(height: 8),
      pw.Text('Sanction & Compliance', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      kv('Sanction Dept.', project.sanctionCompliance.sanctioningDepartmentName),
      kv('Scheme / Plan', _joined([project.sanctionCompliance.schemeName, project.sanctionCompliance.planHeadName])),
      kv('Work Name', project.sanctionCompliance.itemName),
      kv('Tech Approval No.', project.sanctionCompliance.technicalApprovalNo),
      kv('Tech Approval Date', _fmtDate(project.sanctionCompliance.technicalApprovalDate)),
      kv('Admin Approval No.', project.sanctionCompliance.adminApprovalNo),
      kv('Admin Approval Date', _fmtDate(project.sanctionCompliance.adminApprovalDate)),
  kv('Approved Amount', _fmtMoneyInr(project.sanctionCompliance.approvedAmount)),
    ],
  ));

  // Page 3: Allotment & Bank
  doc.addPage(pw.MultiPage(
    pageTheme: pageTheme,
    header: (_) => header(),
    build: (c) => [
      pw.Text('Allotment', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
  kv('Installment 1', _installment(project.allotmentDetails.installment1)),
  if (_hasInstallmentData(project.allotmentDetails.installment2)) kv('Installment 2', _installment(project.allotmentDetails.installment2)),
  if (_hasInstallmentData(project.allotmentDetails.installment3)) kv('Installment 3', _installment(project.allotmentDetails.installment3)),
      pw.SizedBox(height: 8),
      pw.Text('Bank', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      kv('Bank', _bank(project.allotmentDetails.bankDetails)),
      pw.SizedBox(height: 8),
  pw.Text('Work', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
  kv('Start Date', _fmtDate(project.workDescription.startDate ?? project.createdAt)),
  kv('End Date', _fmtDate(project.workDescription.endDate) ?? '(Not Entered)'),
  kv('Current stage', project.workDescription.stage?.name),
    ],
  ));

  // Page 4: Attachments (categorized with hyperlinks)
  doc.addPage(pw.MultiPage(
    pageTheme: pageTheme,
    header: (_) => header(),
    build: (c) => [
      pw.Text('Attachments', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      for (final entry in linksByCategory.entries) ...[
        pw.SizedBox(height: 6),
        pw.Text(entry.key, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        if (entry.value.isEmpty) pw.Text('(none)', style: const pw.TextStyle(fontSize: 10)),
        for (final link in entry.value)
          pw.UrlLink(
            destination: link.url,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text('- ${link.name}  (${Uri.parse(link.url).host})', style: const pw.TextStyle(fontSize: 10, color: PdfColors.blue)),
            ),
          ),
      ]
    ],
  ));

  // Last page: Signature and Disclaimer
  doc.addPage(pw.MultiPage(
    pageTheme: pageTheme,
    header: (_) => header(),
    build: (c) => [
      pw.Text('Verification', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 12),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(height: 18),
          pw.Text('Verified by (Name & Signature): ______________________________________'),
          pw.SizedBox(height: 24),
          pw.Text('Date: ______________'),
        ]),
      ),
      pw.SizedBox(height: 24),
      pw.Text('Notes & Disclaimer', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      pw.Text(
        'This document is generated by the Nirmad app and may be digitally signed. It does not by itself represent the true nature of the project and is intended as an internal statement only.',
        style: const pw.TextStyle(fontSize: 11),
      ),
    ],
  ));
  return Uint8List.fromList(await doc.save());
}

Future<String?> _saveBytes(String name, List<int> bytes, String ext) async {
  // Prefer OS-native save/open on devices (Downloads on Android) via FileOpenHelper.
  try {
    final saved = await FileOpenHelper.saveAndOpen(bytes: bytes, fileName: name);
    return saved;
  } catch (_) {
    // Fallbacks: FileSaver (web-friendly) then share dialog
    try {
      final path = await FileSaver.instance.saveFile(name: name, bytes: Uint8List.fromList(bytes), ext: ext);
      return path;
    } catch (_) {
      try {
        await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: name);
        return null;
      } catch (_) {
        return null;
      }
    }
  }
}

class _ExportProgress {
  final String stage;
  final int done;
  final int total;
  final String? message;
  final List<String> savedPaths;
  _ExportProgress({required this.stage, required this.done, required this.total, this.message, this.savedPaths = const []});
  _ExportProgress copyWith({String? stage, int? done, int? total, String? message, List<String>? savedPaths}) => _ExportProgress(
        stage: stage ?? this.stage,
        done: done ?? this.done,
        total: total ?? this.total,
        message: message ?? this.message,
        savedPaths: savedPaths ?? this.savedPaths,
      );
}

class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _PinnedTabBarDelegate({required this.child});
  @override
  double get minExtent => kToolbarHeight - 8; // slightly compact
  @override
  double get maxExtent => kToolbarHeight - 8;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: child,
    );
  }
  @override
  bool shouldRebuild(covariant _PinnedTabBarDelegate oldDelegate) => oldDelegate.child != child;
}

// (Removed unused _attachmentsList during repair)

// (Removed unused _iconForName during repair)

String? _fmtDate(DateTime? d) => d == null ? null : fmtYmd(d.toLocal());

bool _hasAnyLateInstallments(Project project) {
  final now = DateTime.now();
  bool isLate(Installment? i) {
    if (i == null) return false;
    if (i.receivedAmount != null && (i.receivedAmount ?? 0) > 0) return false;
    final dd = i.date; if (dd == null) return false;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(dd.year, dd.month, dd.day).isBefore(today);
  }
  return isLate(project.allotmentDetails.installment1) || isLate(project.allotmentDetails.installment2) || isLate(project.allotmentDetails.installment3);
}

Future<void> _reportLateInstallments(BuildContext context, WidgetRef ref, Project project) async {
  try {
    final db = FirebaseFirestore.instance;
    final todayStr = DateTime.now().toUtc().toIso8601String().substring(0,10);
    final docId = 'system_late_$todayStr';
    final col = db.collection('projects').doc(project.id).collection('updates');
    final exists = await col.doc(docId).get();
    if (exists.exists) {
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(const SnackBar(content: Text('Already reported today')));
      }
      return;
    }
    final parts = <String>[];
    void add(Installment? i, String name) {
      if (i == null) return;
      if (i.receivedAmount != null && (i.receivedAmount ?? 0) > 0) return;
      final d = i.date; if (d == null) return;
      final days = DateTime.now().difference(DateTime(d.year, d.month, d.day)).inDays;
      if (days > 0) {
        parts.add('$name: ${_fmtMoneyInr(i.amount ?? 0)} late by ${days}d');
      }
    }
    add(project.allotmentDetails.installment1, 'I1');
    add(project.allotmentDetails.installment2, 'I2');
    add(project.allotmentDetails.installment3, 'I3');
    if (parts.isEmpty) {
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(const SnackBar(content: Text('No late installments')));
      }
      return;
    }
    final comment = '[SYSTEM] Late installments reported: ${parts.join(' | ')}';
    await col.doc(docId).set({
      'phase': 0,
      'comment': comment,
      'photos': <String>[],
      'documents': <String>[],
      'updatedBy': 'system',
      'createdAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: false));
    if (context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(content: Text('Reported. A system comment was added.')));
    }
  } catch (e) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
  }
}

// (Removed unused _canMessageOwner helper)

// (Removed unused _showCommentDialog during repair)

Widget _mapRow(BuildContext context, Project project) {
  final gp = project.location;
  final addr = (project.address ?? '').trim();
  if (gp == null && addr.isEmpty) return const SizedBox.shrink();
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 360;
      final icon = Container(width: 28, height: 28, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), shape: BoxShape.circle), child: Icon(CupertinoIcons.map, size: 16, color: cs.primary));
      final label = const SizedBox(width: 160, child: Text('Open Map'));
      final action = TextButton.icon(
        icon: const Icon(CupertinoIcons.location_solid, size: 16),
        label: const Text('Open in Maps'),
        onPressed: () async {
          final query = gp != null ? '${gp.latitude},${gp.longitude}' : Uri.encodeComponent(addr);
          // Prefer Google Maps app on Android
          final google = Uri.parse('geo:0,0?q=$query');
          final googleWeb = Uri.parse('https://maps.google.com/?q=$query');
          final apple = Uri.parse('http://maps.apple.com/?q=$query');
          if (await canLaunchUrl(google)) {
            await launchUrl(google, mode: LaunchMode.externalApplication);
          } else if (await canLaunchUrl(googleWeb)) {
            await launchUrl(googleWeb, mode: LaunchMode.externalApplication);
          } else if (await canLaunchUrl(apple)) {
            await launchUrl(apple, mode: LaunchMode.externalApplication);
          }
        },
        style: TextButton.styleFrom(
          alignment: Alignment.center,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                height: 1.0,
                leadingDistribution: TextLeadingDistribution.even,
                textBaseline: TextBaseline.alphabetic,
              ),
        ),
      );
      if (narrow) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [icon, const SizedBox(width: 8), Expanded(child: label)]),
          const SizedBox(height: 6),
          action,
        ]);
      }
      return Row(children: [icon, const SizedBox(width: 8), label, const SizedBox(width: 8), Flexible(child: Align(alignment: Alignment.centerLeft, child: action))]);
    }),
  );
}