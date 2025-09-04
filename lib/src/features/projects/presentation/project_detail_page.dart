import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/data/auth_repository.dart';
import 'project_update_form_page.dart';
import '../data/project_repository.dart';
import '../domain/project.dart';
import '../domain/project_update.dart';
// import 'phase_update_stepper_page.dart';
// import '../../../services/functions_service.dart';
import '../../../services/storage_service.dart';
// import '../../../core/widgets/branding_footer.dart';
// import '../../../shared/ui/toast.dart';
// import '../../auth/data/auth_repository.dart';
// import '../../auth/domain/app_user.dart';

class ProjectDetailPage extends ConsumerWidget {
  final Project project;
  const ProjectDetailPage({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatesStream = ref.read(projectRepositoryProvider).watchUpdates(project.id);
    final storage = ref.read(storageServiceProvider);
    // final cs = Theme.of(context).colorScheme; // not used currently
  // final user = ref.watch(authStateProvider).value;
  final user = ref.watch(authStateProvider).value;
  final isOwner = user != null && user.uid == project.ownerId;
  return Scaffold(
      appBar: AppBar(
        title: Text(project.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (project.status == ProjectStatus.completed)
            IconButton(
              tooltip: 'Export PDF',
              icon: const Icon(CupertinoIcons.doc_plaintext),
              onPressed: () async {
                await _exportProjectPdf(context, project);
              },
            ),
        ],
      ),
  body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Header summary chips
          Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Builder(builder: (context) {
                    final s = project.status == ProjectStatus.draft ? ProjectStatus.in_progress : project.status;
                    Color c; IconData ic; String label;
                    switch (s) {
                      case ProjectStatus.completed:
                        c = Colors.green; ic = CupertinoIcons.check_mark_circled_solid; label = 'Status: completed'; break;
                      case ProjectStatus.cancelled:
                        c = Colors.grey; ic = CupertinoIcons.xmark_circle_fill; label = 'Status: cancelled'; break;
                      case ProjectStatus.in_progress:
                      case ProjectStatus.draft:
                        c = Colors.amber; ic = CupertinoIcons.clock_solid; label = 'Status: in_progress'; break;
                    }
                    return _chipColored(context, ic, label, c);
                  }),
                  if (project.phase > 0) _chip(context, CupertinoIcons.number, 'Phase: ${project.phase}'),
                  if (project.financials['deadline'] != null)
                    _chip(context, CupertinoIcons.calendar, 'Deadline: ${_fmtDeadlineValue(project.financials['deadline'])}'),
                  if (project.location != null)
                    ActionChip(
                      avatar: const Icon(CupertinoIcons.map, size: 16),
                      label: const Text('Map'),
                      onPressed: () => _showMap(context, project),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Details sections
          _sectionTitle(context, 'Details'),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: LayoutBuilder(builder: (context, c) {
                final twoCol = c.maxWidth > 760;
                Widget col(List<Widget> items) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: items);
                final prelim = <Widget>[
                  _kv(context, CupertinoIcons.building_2_fill, 'Gram Panchayat', project.preliminaryDescription.gramPanchayat),
                  _kvPhone(context, 'Sarpanch', project.preliminaryDescription.sarpanchName, project.preliminaryDescription.sarpanchMobile),
                  _kvPhone(context, 'Secretary', project.preliminaryDescription.secretaryName, project.preliminaryDescription.secretaryMobile),
                  _kvPhone(context, 'Sub Engineer', project.preliminaryDescription.subEngineerName, project.preliminaryDescription.subEngineerMobile),
                ];
                final sanction = <Widget>[
                  _kv(context, CupertinoIcons.checkmark_seal, 'Sanction Dept.', project.sanctionCompliance.sanctioningDepartmentName),
                  _kv(context, CupertinoIcons.square_list, 'Scheme / Plan', _joined([project.sanctionCompliance.schemeName, project.sanctionCompliance.planHeadName])),
                  _kv(context, CupertinoIcons.doc_text, 'Work Name', project.sanctionCompliance.itemName),
                  _kv(context, CupertinoIcons.number, 'Tech Approval No.', project.sanctionCompliance.technicalApprovalNo),
                  _kv(context, CupertinoIcons.calendar, 'Tech Approval Date', _fmtDate(project.sanctionCompliance.technicalApprovalDate)),
                  _kv(context, CupertinoIcons.checkmark_shield, 'Admin Approval No.', project.sanctionCompliance.adminApprovalNo),
                  _kv(context, CupertinoIcons.calendar, 'Admin Approval Date', _fmtDate(project.sanctionCompliance.adminApprovalDate)),
                  _kv(context, CupertinoIcons.money_dollar, 'Approved Amount', project.sanctionCompliance.approvedAmount?.toString()),
                ];
                final allot = <Widget>[
                  _kv(context, CupertinoIcons.creditcard, 'Installment 1', _installment(project.allotmentDetails.installment1)),
                  _kv(context, CupertinoIcons.creditcard, 'Installment 2', _installment(project.allotmentDetails.installment2)),
                  _kv(context, CupertinoIcons.creditcard, 'Installment 3', _installment(project.allotmentDetails.installment3)),
                  _kv(context, CupertinoIcons.building_2_fill, 'Bank', _bank(project.allotmentDetails.bankDetails)),
                ];
                final work = <Widget>[
                  _kv(context, CupertinoIcons.calendar_today, 'Start Date', _fmtDate(project.workDescription.startDate)),
                  _kv(context, CupertinoIcons.cube_box, 'Stage', project.workDescription.stage?.name),
                  _kv(context, CupertinoIcons.exclamationmark_shield, 'Apram Status', project.workDescription.apramStatus?.name),
                ];
                final left = [
                  _subTitle(context, 'Preliminary'),
                  ...prelim,
                  const SizedBox(height: 8),
                  _subTitle(context, 'Sanction & Compliance'),
                  ...sanction,
                ];
                final right = [
                  _subTitle(context, 'Allotment'),
                  ...allot,
                  const SizedBox(height: 8),
                  _subTitle(context, 'Work'),
                  ...work,
                ];
                return twoCol
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: col(left)), const SizedBox(width: 16), Expanded(child: col(right))])
                    : col([...left, const SizedBox(height: 16), ...right]);
              }),
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle(context, 'Attachments'),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: _attachmentsList(context, storage, project),
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle(context, 'Updates'),
          Card(
            elevation: 0,
            child: StreamBuilder(
              stream: updatesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final updates = snapshot.data as List<ProjectUpdate>;
                if (updates.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No updates yet'),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: updates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final u = updates[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(CupertinoIcons.chat_bubble_text),
                      title: Text(u.comment?.trim().isNotEmpty == true ? u.comment!.trim() : '(no comment)'),
                      subtitle: Text(u.createdAt.toLocal().toString().split(' ').first),
                      trailing: Wrap(spacing: 8, children: [
                        if (u.photos.isNotEmpty) _chip(context, CupertinoIcons.photo, '${u.photos.length}'),
                        if (u.documents.isNotEmpty) _chip(context, CupertinoIcons.doc_plaintext, '${u.documents.length}'),
                        if (u.phase > 0) _chip(context, CupertinoIcons.number, 'P${u.phase}'),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectUpdateFormPage(project: project)));
              },
              icon: const Icon(CupertinoIcons.pencil),
              label: const Text('Update'),
            )
          : null,
    );
  }

}

// Section label helper
Widget _sectionTitle(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

// Compact info chip helpers
Widget _chip(BuildContext context, IconData icon, String label) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: cs.surfaceVariant,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.outlineVariant),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ]),
  );
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
      Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    ]),
  );
}

// Helpers for details layout
Widget _subTitle(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6.0, top: 4.0),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

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
  final a = i.amount == null ? null : i.amount.toString();
  final d = i.date;
  final ar = i.receivedAmount == null ? null : i.receivedAmount.toString();
  final dr = i.receivedDate;
  final parts = <String>[];
  if (a != null) parts.add('Amt: $a');
  if (d != null) parts.add('Date: ${d.toLocal().toString().split(' ').first}');
  if (ar != null) parts.add('Rec: $ar');
  if (dr != null) parts.add('Rec on: ${dr.toLocal().toString().split(' ').first}');
  return parts.isEmpty ? null : parts.join('  •  ');
}

String? _bank(BankDetails? b) {
  if (b == null) return null;
  final parts = [b.bankName, b.branch, b.ifsc];
  return _joined(parts);
}

// Build and share/export a PDF with all text details
Future<void> _exportProjectPdf(BuildContext context, Project project) async {
  final doc = pw.Document();
  pw.Widget kv(String k, String? v) => v == null || v.trim().isEmpty
      ? pw.SizedBox()
      : pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.SizedBox(width: 160, child: pw.Text(k, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: 11))),
          ]),
        );
  String fmt(DateTime? d) => d == null ? '-' : d.toLocal().toString().split(' ').first;
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (c) => [
        pw.Text('Project ${project.id}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(project.name, style: const pw.TextStyle(fontSize: 14)),
        pw.SizedBox(height: 12),
        pw.Text('Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        kv('Status', project.status.name),
        kv('Phase', project.phase > 0 ? '${project.phase}' : null),
  kv('Deadline', _fmtDeadlineValue(project.financials['deadline'])),
        pw.SizedBox(height: 8),
        pw.Text('Details', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        kv('Gram Panchayat', project.preliminaryDescription.gramPanchayat),
        kv('Sarpanch', _namePhone(project.preliminaryDescription.sarpanchName, project.preliminaryDescription.sarpanchMobile)),
        kv('Secretary', _namePhone(project.preliminaryDescription.secretaryName, project.preliminaryDescription.secretaryMobile)),
        kv('Sub Engineer', _namePhone(project.preliminaryDescription.subEngineerName, project.preliminaryDescription.subEngineerMobile)),
        pw.SizedBox(height: 8),
        pw.Text('Allotments', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        kv('Installment 1', _installment(project.allotmentDetails.installment1)),
        kv('Installment 2', _installment(project.allotmentDetails.installment2)),
        kv('Installment 3', _installment(project.allotmentDetails.installment3)),
        pw.SizedBox(height: 8),
        pw.Text('Bank', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        kv('Bank', _bank(project.allotmentDetails.bankDetails)),
        pw.SizedBox(height: 12),
        pw.Text('Generated on ${fmt(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
      ],
    ),
  );
  final bytes = await doc.save();
  final fileName = '${project.id}_completed.pdf';
  await Printing.sharePdf(bytes: bytes, filename: fileName);
}

void _showMap(BuildContext context, Project project) {
  final gp = project.location;
  if (gp == null) return;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final pos = ll.LatLng(gp.latitude, gp.longitude);
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: FlutterMap(
          options: MapOptions(initialCenter: pos, initialZoom: 14),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.app'),
            MarkerLayer(markers: [
              Marker(point: pos, child: const Icon(CupertinoIcons.location_solid, color: Colors.red, size: 28)),
            ]),
          ],
        ),
      );
    },
  );
}

Widget _attachmentsList(BuildContext context, StorageService storage, Project project) {
  final all = <String>[
    ...project.documentUrls,
    ...project.photoUrls,
    ...project.workDescription.measurementBookUrls,
    ...project.workDescription.testReportUrls,
    ...project.workDescription.workReportUrls,
    ...project.workDescription.certificateUrls,
  ];
  if (all.isEmpty) return const Text('No attachments');
  List<Widget> items = [];
  for (final path in all) {
    final name = path.split('/').last;
    items.add(
      FutureBuilder<String>(
        future: storage.getDownloadURL(path),
        builder: (context, snap) {
          final url = snap.data;
          final hasError = snap.hasError;
          return ListTile(
            dense: true,
            leading: Icon(_iconForName(name), size: 20),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: hasError ? const Text('Failed to load link', style: TextStyle(color: Colors.red)) : null,
            trailing: FilledButton.tonal(
              onPressed: (url == null)
                  ? null
                  : () async {
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
              child: const Text('Download'),
            ),
          );
        },
      ),
    );
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
}

IconData _iconForName(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return CupertinoIcons.doc_plaintext;
  if (n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png')) return CupertinoIcons.photo;
  return CupertinoIcons.doc;
}

// Shared date formatting helpers
String _fmtDate(DateTime? d) => d == null ? '-' : d.toLocal().toString().split(' ').first;
String _fmtDeadlineValue(dynamic v) {
  try {
    if (v == null) return '-';
    if (v is DateTime) return _fmtDate(v);
    if (v is String) return _fmtDate(DateTime.tryParse(v));
    if (v is Timestamp) return _fmtDate(v.toDate());
    if (v is Map && v['seconds'] != null) {
      final secs = (v['seconds'] as num).toInt();
      return _fmtDate(DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true));
    }
  } catch (_) {}
  return '-';
}
