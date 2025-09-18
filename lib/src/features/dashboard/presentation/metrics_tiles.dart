import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/utils/date_parse.dart';

typedef MetricsTapHandler = void Function(String filterKey);

class MetricsTiles extends ConsumerWidget {
  const MetricsTiles({super.key, this.query, this.onTap, this.docs});

  // Optional Firestore query to scope metrics (e.g., by role/blocks)
  final Query<Map<String, dynamic>>? query;
  // Optional tap handler: 'all' | 'in_progress' | 'completed' | 'delayed_30' | 'delayed_60'
  final MetricsTapHandler? onTap;
  // Optional pre-fetched docs to avoid creating another listener
  final List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  if (docs != null) {
      return _buildFromDocs(docs!);
    }
    final Stream<QuerySnapshot<Map<String, dynamic>>> stream =
        query != null
            ? query!.snapshots()
            : FirebaseFirestore.instance.collection('projects').orderBy('updatedAt', descending: true).snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final docs = snapshot.data!.docs;
        final total = docs.length;
  final completed = docs.where((d) => d.data()['status'] == 'completed').length;
  final cancelled = docs.where((d) => d.data()['status'] == 'cancelled').length;
  // Treat any non-completed, non-cancelled projects as in-progress
  final inProgress = total - completed - cancelled;
  int delayedCount(int days) => _delayedByDaysCountFromDocs(docs, days);
        final delayed30 = delayedCount(30);
        final delayed60 = delayedCount(60);
        return LayoutBuilder(builder: (context, c) {
          final maxW = c.maxWidth == double.infinity ? MediaQuery.of(context).size.width : c.maxWidth;
          final isNarrow = maxW < 680; // mobile-first: stack into two per row on small screens
          final tileWidth = isNarrow ? (maxW - 12) / 2 : 240.0;
          final children = <Widget>[
SizedBox(width: tileWidth, child: _tile(context, 'Total', total, Colors.blue, () => onTap?.call('all'))),
SizedBox(width: tileWidth, child: _tile(context, 'In progress', inProgress, Colors.orange, () => onTap?.call('in_progress'))),
SizedBox(width: tileWidth, child: _tile(context, 'Completed', completed, Colors.green, () => onTap?.call('completed'))),
SizedBox(width: tileWidth, child: _tile(context, 'Delayed 30d', delayed30, Colors.redAccent, () => onTap?.call('delayed_30'))),
SizedBox(width: tileWidth, child: _tile(context, 'Delayed 60d', delayed60, Colors.red, () => onTap?.call('delayed_60'))),
          ];
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: children,
          );
        });
      },
    );
  }

  Widget _buildFromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final total = docs.length;
    final completed = docs.where((d) => d.data()['status'] == 'completed').length;
    final cancelled = docs.where((d) => d.data()['status'] == 'cancelled').length;
    final inProgress = total - completed - cancelled;
  int delayedCount(int days) => _delayedByDaysCountFromDocs(docs, days);
    final delayed30 = delayedCount(30);
    final delayed60 = delayedCount(60);
    return LayoutBuilder(builder: (context, c) {
      final maxW = c.maxWidth == double.infinity ? MediaQuery.of(context).size.width : c.maxWidth;
      final isNarrow = maxW < 680;
      final tileWidth = isNarrow ? (maxW - 12) / 2 : 240.0;
      final children = <Widget>[
SizedBox(width: tileWidth, child: _tile(context, 'Total', total, Colors.blue, () => onTap?.call('all'))),
SizedBox(width: tileWidth, child: _tile(context, 'In progress', inProgress, Colors.orange, () => onTap?.call('in_progress'))),
SizedBox(width: tileWidth, child: _tile(context, 'Completed', completed, Colors.green, () => onTap?.call('completed'))),
SizedBox(width: tileWidth, child: _tile(context, 'Delayed 30d', delayed30, Colors.redAccent, () => onTap?.call('delayed_30'))),
SizedBox(width: tileWidth, child: _tile(context, 'Delayed 60d', delayed60, Colors.red, () => onTap?.call('delayed_60'))),
      ];
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: children,
      );
    });
  }

  Widget _tile(BuildContext context, String label, int value, Color color, VoidCallback? onTap) {
    final cs = Theme.of(context).colorScheme;
    final icon = label == 'Total'
        ? Icons.layers
        : label == 'In progress'
            ? CupertinoIcons.time
            : label == 'Completed'
                ? CupertinoIcons.check_mark_circled
                : label.contains('30')
                    ? CupertinoIcons.calendar
                    : CupertinoIcons.exclamationmark_triangle;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          // Slightly larger min height on Android to improve touch target
          constraints: BoxConstraints(minHeight: Theme.of(context).platform == TargetPlatform.android ? 96 : 88),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$value', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontSize: 24)),
                      const SizedBox(height: 2),
                      Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int _delayedByDaysCountFromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, int days) {
  final today = DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final cutoff = startOfToday.subtract(Duration(days: days));
  int count = 0;
  for (final d in docs) {
    final data = d.data();
    final status = data['status'];
    if (status == 'completed') continue;
    final deadline = data['financials'] is Map ? (data['financials']['deadline']) : null;
    final due = parseAnyDate(deadline);
    if (due != null && due.isBefore(cutoff)) count++;
  }
  return count;
}
