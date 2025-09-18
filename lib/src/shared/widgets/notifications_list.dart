import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_slidable/flutter_slidable.dart';
import 'no_data.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/projects/presentation/project_detail_page.dart';
import '../../features/projects/domain/project.dart';
import '../../core/providers/firebase_providers.dart';
import '../../features/updates/state/updates_stream_provider.dart';
import '../../features/updates/data/updates_repository.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import '../../shared/ui/progress.dart';

// Lightweight wrapper to unify cached and streamed notification docs
class _NotifDoc {
  final String id;
  final Map<String, dynamic> data;
  final DocumentReference<Map<String, dynamic>> ref;
  const _NotifDoc(this.id, this.data, this.ref);
}

final _notifSortNewestFirstProvider = StateProvider<bool>((ref) => true);
final _notifSearchProvider = StateProvider.autoDispose<String>((ref) => '');
// Per-notification toggle to show/hide long comments (default hidden)
final _commentExpandedProvider = StateProvider.family<bool, String>((ref, id) => false);

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
  final userBlockId = appUser?.blockId;
    final isOwner = role == UserRole.projectOwner;
    final isSuper = role == UserRole.superNodal || role == UserRole.devAdmin;
    final isSub = role == UserRole.subNodal;
  final disk = ref.watch(diskCacheProvider);
  // Base query is centralized in updatesStreamProvider.

  // Disk-first key by role/uid/blocks; UI filters apply client-side over cached too
  final roleKey = isOwner ? 'owner' : isSub ? 'sub' : 'super';
  final scopeKey = isSub ? (userBlockId ?? '') : isSuper ? 'all' : (uid ?? '');
  final cacheKey = 'updates:$roleKey:$scopeKey';

    // Helper wrapper to unify streamed and cached docs
  List<_NotifDoc> applyClientFilters(List<_NotifDoc> docs) {
      var filtered = docs;
      // Sort order only (newest/oldest)
      final newestFirst = ref.watch(_notifSortNewestFirstProvider);
      filtered = filtered.toList()
        ..sort((a, b) {
          final ta = (a.data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb = (b.data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          return newestFirst ? tb.compareTo(ta) : ta.compareTo(tb);
        });
      // Search filter across title/body/projectName
      final q = ref.watch(_notifSearchProvider).trim().toLowerCase();
      if (q.isNotEmpty) {
        filtered = filtered.where((d) {
          final m = d.data;
          final title = ((m['title'] as String?) ?? '').replaceFirst(RegExp(r'^\s*\[(?:SYSTEM|System|system)\]\s*'), '').toLowerCase();
          final body = ((m['body'] as String?) ?? '').replaceFirst(RegExp(r'^\s*\[(?:SYSTEM|System|system)\]\s*'), '').toLowerCase();
          final proj = (m['projectName'] as String?)?.toLowerCase() ?? '';
          return title.contains(q) || body.contains(q) || proj.contains(q);
        }).toList(growable: false);
      }
      return filtered;
    }

  Widget buildList(List<_NotifDoc> docs) {
      final updatesRepo = ref.read(updatesRepositoryProvider);
      final brightness = Theme.of(context).brightness;
      final q = ref.watch(_notifSearchProvider).trim();
      final isSearching = q.isNotEmpty;
      String sanitize(String s) => s.replaceFirst(RegExp(r'^\s*\[(?:SYSTEM|System|system)\]\s*'), '');
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        switchInCurve: Curves.easeIn,
        switchOutCurve: Curves.easeOut,
        child: KeyedSubtree(
          key: ValueKey('updates-theme-$brightness'),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                // Search + sort stays visible at all times
                Row(children: [
                  Expanded(
                    child: CupertinoSearchTextField(
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 8, 10),
                      placeholder: 'Search updates',
                      onChanged: (v) => ref.read(_notifSearchProvider.notifier).state = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SortToggle(
                    newestFirst: ref.watch(_notifSortNewestFirstProvider),
                    onChanged: (v) {
                      if (kDebugMode) debugPrint('updates: sort newestFirst=$v');
                      ref.read(_notifSortNewestFirstProvider.notifier).state = v;
                    },
                  ),
                ]),
                const SizedBox(height: 8),
Expanded(
                  child: docs.isEmpty
                      ? NoData(
                          message: isSearching ? 'No matching updates' : 'No updates',
                          asset: isSearching ? 'assets/search_projects.svg' : 'assets/no_updates.svg',
                        )
                      : ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final d = docs[i];
                  final data = d.data;
                  final title = sanitize((data['title'] as String?) ?? 'Update');
                  final body = sanitize((data['body'] as String?) ?? '');
                  final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                  final rel = _relativeTime(createdAt);
                  final targetedToUser = data['userId'] != null;
                  final readAt = data['readAt'] as Timestamp?;
                  final readBy = ((data['readBy'] as List?) ?? const []).whereType<String>();
                  final isUnread = targetedToUser ? (readAt == null) : !(readBy.contains(uid));
                  final projectId = data['projectId'] as String?;
                  final notifType = data['type'] as String?; // request | financial | status | event | comment
                  // final triageStatus = data['triageStatus'] as String?; // ack | done (no longer shown)
                  final cs = Theme.of(context).colorScheme;
                  IconData iconForType(String? t) {
                    switch (t) {
                      case 'financial':
                        return Icons.currency_rupee;
                      case 'request':
                        return CupertinoIcons.exclamationmark_bubble_fill;
                      case 'status':
                        return CupertinoIcons.flag_fill;
                      case 'event':
                        return CupertinoIcons.calendar_today;
                      case 'comment':
                        return CupertinoIcons.bubble_left_bubble_right_fill;
                      default:
                        return CupertinoIcons.bell_fill;
                    }
                  }
                  final leadingIcon = iconForType(notifType);
                  final brightness = Theme.of(context).brightness;
                  final expanded = ref.watch(_commentExpandedProvider(d.id));
          final tile = AnimatedContainer(
                    key: ValueKey('tile:${d.id}:$brightness:${isUnread ? 1 : 0}:${expanded ? 1 : 0}'),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    margin: EdgeInsets.zero,
                    decoration: BoxDecoration(
            // Standardize: same style for seen/unseen; only a dot indicator shows unread.
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            // Use a uniform border color to avoid the Flutter assert about non-uniform colors with borderRadius.
            border: Border.all(color: cs.outlineVariant, width: 1),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          final navigator = Navigator.of(context);
                          if (isUnread && uid != null) {
                            if (kDebugMode) debugPrint('updates: mark read ${d.id}');
                            await updatesRepo.markAsRead(d.ref, uid: uid, targetedToUser: targetedToUser);
                          }
                          if (projectId != null) {
                            navigator.push(MaterialPageRoute(builder: (_) => ProjectDetailPage(project: Project(id: projectId, name: data['projectName'] ?? '', ownerId: data['ownerId'] ?? '', blockId: data['blockId'] ?? '', villageId: '', createdAt: DateTime.now(), updatedAt: DateTime.now()))));
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                // Unread dot indicator (only visual difference)
                if (isUnread) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else
                  const SizedBox(width: 10),
                              // Main content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header: icon + title (and optional project name below)
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: cs.primary.withValues(alpha: 0.12),
                                          child: Icon(leadingIcon, size: 16, color: cs.primary),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                title,
                                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: cs.onSurface),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if ((data['projectName'] as String?)?.isNotEmpty == true)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2.0),
                                                  child: Text(
                                                    data['projectName'] as String,
                                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // Body (non-comment types only): show short preview
                                    if (notifType != 'comment' && body.isNotEmpty)
                                      Text(
                                        body,
                                        maxLines: MediaQuery.of(context).size.width < 420 ? 2 : 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                      ),
                                    // Comment (hidden by default; toggle to show without overflow)
                                    if (notifType == 'comment' && body.isNotEmpty) ...[
                                      if (!expanded)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: () => ref.read(_commentExpandedProvider(d.id).notifier).state = true,
                                            icon: const Icon(CupertinoIcons.bubble_left_bubble_right, size: 16),
                                            label: const Text('Show comment'),
                                            style: TextButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                          ),
                                        )
                                      else
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2.0, bottom: 2.0),
                                          child: ClipRRect(
                                            borderRadius: const BorderRadius.only(topRight: Radius.circular(6), bottomRight: Radius.circular(6)),
                                            child: Stack(
                                              children: [
                                                // Background container without borders to avoid non-uniform border + radius issue
                                                Container(
                                                  width: double.infinity,
                                                  color: cs.surfaceContainerLow,
                                                  child: Padding(
                                                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.format_quote, size: 14, color: cs.primary),
                                                            const SizedBox(width: 4),
                                                            Text('Comment', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          body,
                                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                                color: cs.onSurface,
                                                                fontStyle: FontStyle.italic,
                                                              ),
                                                        ),
                                                        Align(
                                                          alignment: Alignment.centerLeft,
                                                          child: TextButton.icon(
                                                            onPressed: () => ref.read(_commentExpandedProvider(d.id).notifier).state = false,
                                                            icon: const Icon(CupertinoIcons.chevron_up, size: 14),
                                                            label: const Text('Hide comment'),
                                                            style: TextButton.styleFrom(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                              visualDensity: VisualDensity.compact,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                // Left accent bar as an overlay (no border used)
                                                Positioned(
                                                  left: 0,
                                                  top: 0,
                                                  bottom: 0,
                                                  child: Container(width: 3, color: cs.primary),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                    const SizedBox(height: 6),
                                    // Footer: time on left, action on right
                                    Row(
                                      children: [
                                        if (rel.isNotEmpty)
                                          Text(rel, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                                        const Spacer(),
                                        if (projectId != null)
                                          IconButton(
                                            tooltip: 'Open project',
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => ProjectDetailPage(
                                                    project: Project(
                                                      id: projectId,
                                                      name: data['projectName'] ?? '',
                                                      ownerId: data['ownerId'] ?? '',
                                                      blockId: data['blockId'] ?? '',
                                                      villageId: '',
                                                      createdAt: DateTime.now(),
                                                      updatedAt: DateTime.now(),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                            icon: Icon(Icons.open_in_new_rounded, color: cs.primary),
                                            iconSize: 18,
                                            padding: const EdgeInsets.all(6),
                                            visualDensity: VisualDensity.compact,
                                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );

                  // Slidable can cause pointer/mouse tracker issues on some Flutter web builds.
                  // Disable on web to improve stability; fall back to plain tile.
                  if (kIsWeb) {
                    return tile;
                  }
                  return Slidable(
                    key: ValueKey(d.id),
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.45,
                      children: [
                        SlidableAction(
                          onPressed: projectId == null
                              ? null
                              : (_) async {
                                  if (isUnread && uid != null) {
                                    await updatesRepo.markAsRead(d.ref, uid: uid, targetedToUser: targetedToUser);
                                  }
                                  if (!context.mounted) return;
                                  final navigator = Navigator.of(context);
                                  await navigator.push(
                                    MaterialPageRoute(
                                      builder: (_) => ProjectDetailPage(
                                        project: Project(
                                          id: projectId,
                                          name: data['projectName'] ?? '',
                                          ownerId: data['ownerId'] ?? '',
                                          blockId: data['blockId'] ?? '',
                                          villageId: '',
                                          createdAt: DateTime.now(),
                                          updatedAt: DateTime.now(),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          icon: Icons.open_in_new,
                          label: 'Open',
                        ),
                        SlidableAction(
              onPressed: (_) async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete this notification?'),
                                content: const Text('This action cannot be undone.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                  FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true) {
                if (kDebugMode) debugPrint('updates: delete ${d.id}');
                              await updatesRepo.delete(d.ref);
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
          ),
        ),
      );
    }

    // Try cached data to use as an immediate fallback while stream connects
    final cachedList = disk.getJson<List<Map<String, dynamic>>>(cacheKey, (obj) {
      if (obj is List) {
        return obj.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return <Map<String, dynamic>>[];
    });
    final cachedDocs = <_NotifDoc>[
      if (cachedList != null && cachedList.isNotEmpty)
        ...cachedList.map((m) {
          final id = (m['id'] as String?) ?? '';
          final data = Map<String, dynamic>.from(m)..remove('id');
          // Rehydrate timestamps if millis were persisted
          final createdAtMs = data.remove('createdAtMs') as int?;
          final readAtMs = data.remove('readAtMs') as int?;
          if (createdAtMs != null) {
            data['createdAt'] = Timestamp.fromDate(DateTime.fromMillisecondsSinceEpoch(createdAtMs));
          }
          if (readAtMs != null) {
            data['readAt'] = Timestamp.fromDate(DateTime.fromMillisecondsSinceEpoch(readAtMs));
          }
          final refDoc = FirebaseFirestore.instance.collection('updates').doc(id);
          return _NotifDoc(id, data, refDoc);
        }),
    ];

    final updatesStream = ref.watch(updatesStreamProvider);
    return updatesStream.when(
      loading: () {
        if (cachedDocs.isNotEmpty) {
          return buildList(applyClientFilters(cachedDocs));
        }
        return const Center(child: AppLoadingIndicator());
      },
      error: (e, st) {
        // Show cache if present; otherwise soft empty state
        if (cachedDocs.isNotEmpty) {
          return buildList(applyClientFilters(cachedDocs));
        }
        // If Firestore requires an index, log the URL to console for quick creation
        try {
          final msg = e.toString();
          final m = RegExp(r'https://console\.firebase\.google\.com[^\s\)]*').firstMatch(msg);
          final url = m?.group(0);
          if (url != null) {
            // ignore: avoid_print
            print('Firestore index required (Updates): $url');
          }
        } catch (_) {}
        // Keep UI (search/actions) visible even on error by showing an empty results area
        return buildList(const <_NotifDoc>[]);
      },
      data: (snap) {
        final docsSnap = snap.docs;
        // Persist snapshot to disk (id + fields) with TTL
        try {
          // Serialize safely for Web/local storage: strict whitelist to avoid raw Timestamp or nested non-primitive types
          final toCache = <Map<String, dynamic>>[for (final d in docsSnap) _serializeNotif(d)];
          // Keep it lightweight; expire in ~20 minutes
          // ignore: unawaited_futures
          disk.setJson(cacheKey, toCache, ttl: const Duration(minutes: 20));
        } catch (_) {}

        final wrapped = docsSnap
            .map((d) => _NotifDoc(d.id, d.data(), d.reference))
            .toList(growable: false);
        final filtered = applyClientFilters(wrapped);
        return buildList(filtered);
      },
    );
  }
}

class _SortToggle extends StatelessWidget {
  final bool newestFirst;
  final ValueChanged<bool> onChanged;
  const _SortToggle({required this.newestFirst, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Oldest first',
          onPressed: () => onChanged(false),
          icon: Icon(CupertinoIcons.sort_up, color: !newestFirst ? cs.primary : cs.onSurfaceVariant),
        ),
        IconButton(
          tooltip: 'Newest first',
          onPressed: () => onChanged(true),
          icon: Icon(CupertinoIcons.sort_down, color: newestFirst ? cs.primary : cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

Map<String, dynamic> _serializeNotif(QueryDocumentSnapshot<Map<String, dynamic>> d) {
  final m = d.data();
  DateTime? toDt(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
  final createdAt = toDt(m['createdAt']);
  final readAt = toDt(m['readAt']);
  // Whitelist only primitive types for caching
  final allowed = <String, dynamic>{};
  void putIf<T>(String k) {
    final v = m[k];
    if (v == null) return;
    if (v is String || v is num || v is bool) {
      allowed[k] = v;
    }
  }
  for (final k in ['title', 'body', 'projectId', 'projectName', 'ownerId', 'blockId', 'type', 'userId']) {
    putIf(k);
  }
  return {
    'id': d.id,
    ...allowed,
    if (createdAt != null) 'createdAtMs': createdAt.millisecondsSinceEpoch,
    if (readAt != null) 'readAtMs': readAt.millisecondsSinceEpoch,
  };
}
