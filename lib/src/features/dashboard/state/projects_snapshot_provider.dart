import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../../shared/data/blocks_provider.dart';
import '../../../core/logging/app_logger.dart';

/// Shared, memoized stream of projects for dashboard widgets to avoid duplicate listeners.
final dashboardProjectsStreamProvider = StreamProvider<QuerySnapshot<Map<String, dynamic>>>((ref) {
  final db = FirebaseFirestore.instance;
  final auth = ref.watch(authStateProvider).value;
  // Cap results to avoid heavy realtime fanout on web. Client-side paging handles more.
  Query<Map<String, dynamic>> base = db.collection('projects').orderBy('updatedAt', descending: true).limit(300);
  if (auth == null) return base.snapshots();
  switch (auth.role) {
    case UserRole.projectOwner:
      base = base.where('ownerId', isEqualTo: auth.uid);
      break;
    case UserRole.subNodal:
      // Sub Nodal: filter strictly by block, but be alias-aware.
      final keys = blockQueryKeys(auth.blockId);
  AppLogger.i.d('projects stream: sub_nodal keys=${keys.join(', ')}');
      if (keys.isEmpty) {
        base = db.collection('projects').where('blockId', isEqualTo: '__none__');
      } else if (keys.length == 1) {
        base = db.collection('projects').where('blockId', isEqualTo: keys.first);
      } else {
        base = db.collection('projects').where('blockId', whereIn: keys.take(10).toList());
      }
      // Full server-side sort (requires composite index)
      base = base.orderBy('updatedAt', descending: true).limit(300);
      break;
    case UserRole.superNodal:
    case UserRole.devAdmin:
      // all projects
      break;
  }
  return base.snapshots();
});
