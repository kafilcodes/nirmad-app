import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'dart:developer' as developer;
import 'no_data.dart';

class NotificationsList extends ConsumerWidget {
  const NotificationsList({super.key});

  String _relativeTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final d = time;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    final q = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true);
    return StreamBuilder(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          final err = snap.error;
          // Parse known cases but avoid exposing raw error text to users
          if (err is FirebaseException) {
            final msg = err.message ?? '';
            final idx = RegExp(r'https://console\.firebase\.google\.com[^\s\)]*').firstMatch(msg)?.group(0);
            if (idx != null) {
              // ignore: avoid_print
              print('Firestore index required (notifications list). Open: $idx');
              developer.log('Firestore index required', name: 'notifications', error: msg);
            } else if (err.code == 'permission-denied') {
              developer.log('Permission denied reading notifications', name: 'notifications');
            } else {
              developer.log('Notifications error', name: 'notifications', error: msg);
            }
          } else {
            developer.log('Notifications error (unknown)', name: 'notifications', error: err);
          }
          // Show soft empty state instead of error details
          return const NoData(message: 'No notifications');
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const NoData(message: 'No notifications');
        }
        final unread = docs.where((d) => (d.data()['readAt'] as Timestamp?) == null).toList(growable: false);
        final cs = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              if (unread.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final batch = FirebaseFirestore.instance.batch();
                      for (final d in unread) {
                        batch.set(d.reference, {'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                      }
                      await batch.commit();
                    },
                    child: Text('Mark all as read (${unread.length})'),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data();
                    final title = (data['title'] as String?) ?? 'Notification';
                    final body = (data['body'] as String?) ?? '';
                    final readAt = data['readAt'] as Timestamp?;
                    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                    final rel = _relativeTime(createdAt);
                    final isUnread = readAt == null;
                    return Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () async {
                          if (isUnread) {
                            await d.reference.set({'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isUnread)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 6, right: 10),
                                  decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (rel.isNotEmpty)
                                          Text(
                                            rel,
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                                          ),
                                      ],
                                    ),
                                    if (body.isNotEmpty) const SizedBox(height: 4),
                                    if (body.isNotEmpty)
                                      Text(
                                        body,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
