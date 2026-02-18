import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/projects/data/project_repository.dart';
import '../../data/firestore/query_spec.dart';
import '../providers/firebase_providers.dart';

/// Kicks off warmup for commonly used data right after login and on app start.
/// - Warms current user's Firestore doc and role/blocks.
/// - Warms owner's recent projects or nodal's first page projects.
/// - Stores a disk snapshot for immediate subsequent renders.
Future<void> _bootstrapPrefetch(Ref ref) async {
  final auth = await ref.read(authRepositoryProvider).currentUser();
  if (auth == null) return;
  final db = ref.read(firestoreProvider);
  final dao = ref.read(firestoreDaoProvider);
  final disk = ref.read(diskCacheProvider);

  // 1) Warm user doc - try server first, fall back gracefully
  final userRef = db.collection('users').doc(auth.uid);
  try {
    final snap = await userRef.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 8));
    if (snap.exists) {
      await disk.setJson('user:${auth.uid}', snap.data()!, ttl: const Duration(minutes: 10));
    }
  } catch (_) {
    // Server fetch failed, try cache or default
    try {
      final snap = await userRef.get();
      if (snap.exists) {
        await disk.setJson('user:${auth.uid}', snap.data()!, ttl: const Duration(minutes: 10));
      }
    } catch (_) {
      // ignore - not critical
    }
  }

  // 2) Warm list by role
  final projects = ref.read(projectRepositoryProvider);
  if (auth.role == UserRole.projectOwner) {
    try {
      final list = await projects.fetchOwnerProjectsCached(ownerId: auth.uid, limit: 50);
      // Store a minimal snapshot for fast cold start list render
      await disk.setJson(
        'ownerProjects:${auth.uid}',
        list
            .map((e) => {
                  'id': e.id,
                  'name': e.name,
                  'blockId': e.blockId,
                  'status': e.status.name,
                  'updatedAt': e.updatedAt.millisecondsSinceEpoch,
                })
            .toList(),
        ttl: const Duration(minutes: 5),
      );
    } catch (_) {}
  } else {
    // Nodal: warm first page. We use a generic query without filters; UI filters further
    try {
      Query<Map<String, dynamic>> build(
          CollectionReference<Map<String, dynamic>> col) {
        return col.orderBy('updatedAt', descending: true).limit(25);
      }
      final list = await dao.getList<Map<String, dynamic>>(
        spec: const QuerySpec(path: 'projects', limit: 25),
        build: build,
        fromDoc: (d) {
          final m = d.data() ?? <String, dynamic>{};
          return {'id': d.id, ...m};
        },
        ttl: const Duration(minutes: 3),
      );
      await disk.setJson('nodal:projects:first', list, ttl: const Duration(minutes: 3));
    } catch (_) {}
  }
}

final bootstrapPrefetchProvider = FutureProvider<void>(_bootstrapPrefetch);
