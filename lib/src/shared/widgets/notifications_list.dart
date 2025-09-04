import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'dart:developer' as developer;
import 'package:flutter_slidable/flutter_slidable.dart';
import 'no_data.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/projects/presentation/project_detail_page.dart';
import '../../features/projects/domain/project.dart';

final _notifBlockFilterProvider = StateProvider<String?>((ref) => null);
final _notifSortNewestFirstProvider = StateProvider<bool>((ref) => true);
final _notifTriageOnlyProvider = StateProvider<bool>((ref) => false);

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
    final appUser = ref.watch(authStateProvider).value;
    final role = appUser?.role;
    final userBlocks = appUser?.blocks ?? const <String>[];
    final isOwner = role == UserRole.projectOwner;
    final isSuper = role == UserRole.superNodal || role == UserRole.devAdmin;
    final isSub = role == UserRole.subNodal;
  // Base query
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('updates').orderBy('createdAt', descending: true).limit(500);
    // Owners: only their targeted updates (userId == uid)
    if (isOwner) {
      q = FirebaseFirestore.instance
          .collection('updates')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(300);
    }
    // Sub nodal: role-targeted to sub_nodal and block in user's blocks
    else if (isSub) {
      if (userBlocks.isNotEmpty) {
        q = FirebaseFirestore.instance
            .collection('updates')
            .where('targetRoles', arrayContains: 'sub_nodal')
            .where('blockId', whereIn: userBlocks.take(10).toList()) // Firestore supports up to 10 for whereIn
            .orderBy('createdAt', descending: true)
            .limit(500);
      } else {
        // No blocks assigned, empty stream
        return const NoData(message: 'No updates', asset: 'assets/no_data.svg');
      }
    }
    // Super nodal (and dev admin): all role-targeted to nodals
    else if (isSuper) {
      q = FirebaseFirestore.instance
          .collection('updates')
          .where('targetRoles', arrayContainsAny: ['super_nodal', 'sub_nodal'])
          .orderBy('createdAt', descending: true)
          .limit(500);
    }
    // Apply triage-only filter on server when possible
    final triageOnly = ref.watch(_notifTriageOnlyProvider);
    if (!isOwner && triageOnly) {
      try {
        q = q.where('type', whereIn: ['financial', 'request']);
      } catch (_) {
        // whereIn not supported in current query composition; will filter client-side
      }
    }
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
          return const NoData(message: 'No updates', asset: 'assets/no_data.svg');
        }
        var docs = snap.data?.docs ?? const [];
        // Extra client filters for super nodal: by block and sort order
        if (isSuper) {
          final blockFilter = ref.watch(_notifBlockFilterProvider);
          if (blockFilter != null && blockFilter.isNotEmpty) {
            docs = docs.where((d) => (d.data()['blockId'] as String?) == blockFilter).toList(growable: false);
          }
          final newestFirst = ref.watch(_notifSortNewestFirstProvider);
          docs = docs.toList()
            ..sort((a, b) {
              final ta = (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
              final tb = (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
              return newestFirst ? tb.compareTo(ta) : ta.compareTo(tb);
            });
        }
        if (docs.isEmpty) {
          return const NoData(message: 'No updates', asset: 'assets/no_data.svg');
        }
        // Unread semantics: user-targeted uses readAt; role-targeted uses readBy array
        final unread = docs.where((d) {
          final m = d.data();
          if (m['userId'] != null) {
            return (m['readAt'] as Timestamp?) == null;
          }
          final readBy = ((m['readBy'] as List?) ?? const []).whereType<String>();
          return !(readBy.contains(uid));
        }).toList(growable: false);
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
                        final m = d.data();
                        if (m['userId'] != null) {
                          batch.set(d.reference, {'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                        } else {
                          batch.update(d.reference, {'readBy': FieldValue.arrayUnion([uid])});
                        }
                      }
                      await batch.commit();
                    },
                    child: Text('Mark all as read (${unread.length})'),
                  ),
                ),
              const SizedBox(height: 8),
              // Optional controls for super nodal: triage filter + block filter + sort order
              if (isSuper) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      selected: ref.watch(_notifTriageOnlyProvider),
                      label: const Text('Triage only'),
                      onSelected: (v) => ref.read(_notifTriageOnlyProvider.notifier).state = v,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Filter by block'),
                        initialValue: ref.watch(_notifBlockFilterProvider),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All blocks')),
                          ...{
                            for (final d in docs) d.data()['blockId'] as String?
                          }.whereType<String>().map((b) => DropdownMenuItem(value: b, child: Text(b))),
                        ],
                        onChanged: (v) => ref.read(_notifBlockFilterProvider.notifier).state = v,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<bool>(
                      // DropdownButton doesn't support initialValue; this is fine
                      value: ref.watch(_notifSortNewestFirstProvider),
                      items: const [
                        DropdownMenuItem(value: true, child: Text('Newest')),
                        DropdownMenuItem(value: false, child: Text('Oldest')),
                      ],
                      onChanged: (v) => ref.read(_notifSortNewestFirstProvider.notifier).state = v ?? true,
                    ),
                  ],
                ),
              ],
              if (isSub) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    selected: ref.watch(_notifTriageOnlyProvider),
                    label: const Text('Triage only'),
                    onSelected: (v) => ref.read(_notifTriageOnlyProvider.notifier).state = v,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data();
                    // Client-side triage-only filter if needed
                    if (!isOwner && ref.watch(_notifTriageOnlyProvider)) {
                      final t = data['type'] as String?;
                      final triageStatus = data['triageStatus'] as String?;
                      final isTriage = t == 'financial' || t == 'request';
                      if (!isTriage || triageStatus == 'done') {
                        return const SizedBox.shrink();
                      }
                    }
                    final title = (data['title'] as String?) ?? 'Update';
                    final body = (data['body'] as String?) ?? '';
                    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                    final rel = _relativeTime(createdAt);
                    final targetedToUser = data['userId'] != null;
                    final readAt = data['readAt'] as Timestamp?;
                    final readBy = ((data['readBy'] as List?) ?? const []).whereType<String>();
                    final isUnread = targetedToUser ? (readAt == null) : !(readBy.contains(uid));
                    final projectId = data['projectId'] as String?;
                    final updateId = data['updateId'] as String?;
                    final notifType = data['type'] as String?; // request | financial | status | event | comment
                    final triageStatus = data['triageStatus'] as String?; // ack | done
                    final tile = Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      margin: EdgeInsets.zero,
                      color: isUnread ? cs.surface : cs.surfaceContainerHighest,
                      child: ListTile(
                        onTap: () async {
                          if (isUnread) {
                            if (targetedToUser) {
                              await d.reference.set({'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                            } else if (uid != null) {
                              await d.reference.update({'readBy': FieldValue.arrayUnion([uid])});
                            }
                          }
                          if (projectId != null) {
                            // ignore: use_build_context_synchronously
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailPage(project: Project(id: projectId, name: data['projectName'] ?? '', ownerId: data['ownerId'] ?? '', blockId: data['blockId'] ?? '', villageId: '', createdAt: DateTime.now(), updatedAt: DateTime.now()))));
                          }
                        },
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        leading: isUnread
                            ? Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle))
                            : const SizedBox(width: 8),
                        title: Text(
                          title,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isUnread ? cs.onSurface : cs.onSurface.withValues(alpha: 0.75)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (body.isNotEmpty) Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                            if (rel.isNotEmpty) Text(rel, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor)),
                            if (notifType == 'financial' || notifType == 'request')
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Wrap(spacing: 8, children: [
                                  Chip(label: Text('type: $notifType')), 
                                  if (triageStatus != null) Chip(label: Text('triage: $triageStatus')),
                                ]),
                              ),
                            if (projectId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: FilledButton.tonal(
                                  onPressed: () {
                                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailPage(project: Project(id: projectId, name: data['projectName'] ?? '', ownerId: data['ownerId'] ?? '', blockId: data['blockId'] ?? '', villageId: '', createdAt: DateTime.now(), updatedAt: DateTime.now()))));
                                  },
                                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                  child: const Text('Open Project'),
                                ),
                              ),
                            if ((notifType == 'financial' || notifType == 'request') && (isSuper || isSub) && projectId != null && updateId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Row(children: [
                                  FilledButton.tonal(
                                    onPressed: () async {
                                      // Acknowledge triage: set on both global notif and project update doc
                                      final db = FirebaseFirestore.instance;
                                      try {
                                        await db.collection('projects').doc(projectId).collection('updates').doc(updateId).set({
                                          'triage': {
                                            'status': 'ack',
                                            'ackBy': uid,
                                            'ackAt': FieldValue.serverTimestamp(),
                                          }
                                        }, SetOptions(merge: true));
                                        await d.reference.set({
                                          'triageStatus': 'ack',
                                          'triageBy': uid,
                                          'triageAt': FieldValue.serverTimestamp(),
                                        }, SetOptions(merge: true));
                                      } catch (e) {
                                        // ignore: avoid_print
                                        print('Triage ack failed: $e');
                                      }
                                    },
                                    child: const Text('Acknowledge'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonal(
                                    onPressed: () async {
                                      final db = FirebaseFirestore.instance;
                                      try {
                                        await db.collection('projects').doc(projectId).collection('updates').doc(updateId).set({
                                          'triage': {
                                            'status': 'done',
                                            'doneBy': uid,
                                            'doneAt': FieldValue.serverTimestamp(),
                                          }
                                        }, SetOptions(merge: true));
                                        await d.reference.set({
                                          'triageStatus': 'done',
                                          'triageBy': uid,
                                          'triageAt': FieldValue.serverTimestamp(),
                                        }, SetOptions(merge: true));
                                      } catch (e) {
                                        // ignore: avoid_print
                                        print('Triage done failed: $e');
                                      }
                                    },
                                    child: const Text('Mark resolved'),
                                  ),
                                ]),
                              ),
                          ],
                        ),
                      ),
                    );

                    return Slidable(
                      key: ValueKey(d.id),
                      endActionPane: ActionPane(
                        motion: const DrawerMotion(),
                        extentRatio: 0.45,
                        children: [
                          SlidableAction(
                            onPressed: (_) async {
                              // Soft delete for user: hide via read flags
                              if (!isUnread) {
                                await d.reference.set({'hiddenFor': FieldValue.arrayUnion([uid])}, SetOptions(merge: true));
                              } else {
                                if (targetedToUser) {
                                  await d.reference.set({'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                                } else if (uid != null) {
                                  await d.reference.update({'readBy': FieldValue.arrayUnion([uid])});
                                }
                              }
                            },
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            icon: Icons.done_all,
                            label: isUnread ? 'Mark read' : 'Hide',
                          ),
                          SlidableAction(
                            onPressed: (_) async {
                              try {
                                await d.reference.delete();
                              } catch (e) {
                                // ignore: avoid_print
                                print('Delete failed: $e');
                              }
                            },
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            icon: Icons.delete,
                            label: 'Delete',
                          ),
                        ],
                      ),
                      child: tile,
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
