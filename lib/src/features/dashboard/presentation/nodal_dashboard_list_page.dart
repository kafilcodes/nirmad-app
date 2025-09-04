import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../projects/domain/project.dart';
// import 'package:url_launcher/url_launcher.dart';
// import '../../../services/functions_service.dart';
// import '../../../shared/ui/toast.dart';
import '../../../shared/widgets/no_data.dart';

final _statusFilterProvider = StateProvider<ProjectStatus?>((_) => null);
final _lastDocProvider = StateProvider<DocumentSnapshot<Map<String, dynamic>>?>((_) => null);
final _pageSize = 25;

class NodalDashboardListPage extends ConsumerWidget {
  const NodalDashboardListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(_statusFilterProvider);
    final auth = ref.watch(authStateProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      body: StreamBuilder(
        stream: _query(ref, auth?.blocks ?? const [], status: status, limit: _pageSize, startAfter: ref.watch(_lastDocProvider)).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final snap = snapshot.data as QuerySnapshot<Map<String, dynamic>>;
          final docs = snap.docs;
          if (docs.isEmpty) return const NoData(message: 'No projects');
          final items = docs.map(Project.fromDoc).toList();
          // Keep track of last doc
          if (docs.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ref.read(_lastDocProvider) != docs.last) {
                ref.read(_lastDocProvider.notifier).state = docs.last;
              }
            });
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = items[index];
              return ListTile(
                title: Text(p.name),
                subtitle: Text('${p.blockId} • ${p.status.name} • ${p.updatedAt.toLocal()}'),
                // Export ZIP removed; use Project Details to export PDF when applicable
              );
            },
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            const Text('Status:'),
            const SizedBox(width: 8),
            Flexible(
              child: DropdownButton<ProjectStatus?>(
                isExpanded: true,
                value: status,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ...ProjectStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.name, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) {
                  ref.read(_statusFilterProvider.notifier).state = v;
                  ref.read(_lastDocProvider.notifier).state = null; // reset pagination
                },
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => ref.read(_lastDocProvider.notifier).state = ref.read(_lastDocProvider),
              child: const Text('Load more'),
            ),
          ],
        ),
      ),
    );
  }

  Query<Map<String, dynamic>> _query(WidgetRef ref, List<String> blocks, {ProjectStatus? status, int limit = 50, DocumentSnapshot<Map<String, dynamic>>? startAfter}) {
    final db = FirebaseFirestore.instance;
    Query<Map<String, dynamic>> q = db.collection('projects').orderBy('updatedAt', descending: true).limit(limit);
    if (status != null) {
      q = q.where('status', isEqualTo: status.name);
    }
    if (blocks.isNotEmpty) {
      // filter by blocks for sub nodal; super nodal will ignore
      q = q.where('blockId', whereIn: blocks.take(10).toList());
    }
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    return q;
  }
}
