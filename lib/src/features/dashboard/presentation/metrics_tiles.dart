import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MetricsTiles extends StatelessWidget {
  const MetricsTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return StreamBuilder(
      stream: db.collection('projects').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final docs = (snapshot.data as QuerySnapshot<Map<String, dynamic>>).docs;
        final total = docs.length;
        final completed = docs.where((d) => d.data()['status'] == 'completed').length;
        final inProgress = docs.where((d) => d.data()['status'] == 'in_progress').length;
        final now = DateTime.now();
        int delayedCount(int days) {
          final cutoff = now.subtract(Duration(days: days));
          return docs.where((d) {
            final data = d.data();
            final ts = data['updatedAt'];
            final status = data['status'];
            if (status == 'completed') return false;
            if (ts is Timestamp) {
              return ts.toDate().isBefore(cutoff);
            }
            return false;
          }).length;
        }
        final delayed30 = delayedCount(30);
        final delayed60 = delayedCount(60);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              SizedBox(width: 240, child: _tile('Total', total, Colors.blue)),
              SizedBox(width: 240, child: _tile('In progress', inProgress, Colors.orange)),
              SizedBox(width: 240, child: _tile('Completed', completed, Colors.green)),
              SizedBox(width: 240, child: _tile('Delayed 30d', delayed30, Colors.redAccent)),
              SizedBox(width: 240, child: _tile('Delayed 60d', delayed60, Colors.red)),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(String label, int value, Color color) {
    return Card(
      color: color.withValues(alpha: 0.1),
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
    );
  }
}
