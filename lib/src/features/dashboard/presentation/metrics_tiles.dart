import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

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
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              SizedBox(width: 240, child: _tile('Total', total, Colors.blue, () => onTap?.call('all'))),
              SizedBox(width: 240, child: _tile('In progress', inProgress, Colors.orange, () => onTap?.call('in_progress'))),
              SizedBox(width: 240, child: _tile('Completed', completed, Colors.green, () => onTap?.call('completed'))),
              SizedBox(width: 240, child: _tile('Delayed 30d', delayed30, Colors.redAccent, () => onTap?.call('delayed_30'))),
              SizedBox(width: 240, child: _tile('Delayed 60d', delayed60, Colors.red, () => onTap?.call('delayed_60'))),
            ],
          ),
        );
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(width: 240, child: _tile('Total', total, Colors.blue, () => onTap?.call('all'))),
          SizedBox(width: 240, child: _tile('In progress', inProgress, Colors.orange, () => onTap?.call('in_progress'))),
          SizedBox(width: 240, child: _tile('Completed', completed, Colors.green, () => onTap?.call('completed'))),
          SizedBox(width: 240, child: _tile('Delayed 30d', delayed30, Colors.redAccent, () => onTap?.call('delayed_30'))),
          SizedBox(width: 240, child: _tile('Delayed 60d', delayed60, Colors.red, () => onTap?.call('delayed_60'))),
        ],
      ),
    );
  }

  Widget _tile(String label, int value, Color color, VoidCallback? onTap) {
    return Card(
  color: color.withValues(alpha: 0.1),
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 4),
            Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
          ],
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
    DateTime? due;
    if (deadline is Timestamp) {
      due = deadline.toDate();
    } else if (deadline is DateTime) {
      due = deadline;
    } else if (deadline is String) {
      due = DateTime.tryParse(deadline);
    } else if (deadline is Map && deadline['seconds'] != null) {
      final secs = (deadline['seconds'] as num).toInt();
      due = DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true).toLocal();
    }
    if (due != null && due.isBefore(cutoff)) count++;
  }
  return count;
}
