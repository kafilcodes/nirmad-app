import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../../shared/data/blocks_provider.dart';
import '../../../core/logging/app_logger.dart';

/// Shared, memoized stream of updates to avoid duplicate listeners and centralize role scoping.
final updatesStreamProvider =
    StreamProvider<QuerySnapshot<Map<String, dynamic>>>((ref) {
  final db = FirebaseFirestore.instance;
  final auth = ref.watch(authStateProvider).value;

  Query<Map<String, dynamic>> q = db
      .collection('updates')
      .orderBy('createdAt', descending: true)
      .limit(300);

  if (auth == null) return q.snapshots();

  switch (auth.role) {
    case UserRole.projectOwner:
      q = db
          .collection('updates')
          .where('userId', isEqualTo: auth.uid)
          .orderBy('createdAt', descending: true)
          .limit(300);
      break;
    case UserRole.subNodal:
      final keys = blockQueryKeys(auth.blockId);
      if (!kReleaseMode) AppLogger.i.d('updates stream: sub_nodal keys=${keys.join(', ')}');
      if (keys.isEmpty) {
        // Empty stream by querying an impossible condition
        q = db.collection('updates').where('blockId', isEqualTo: '__none__').limit(1);
      } else if (keys.length == 1) {
        q = db
            .collection('updates')
            .where('targetRoles', arrayContains: 'sub_nodal')
            .where('blockId', isEqualTo: keys.first)
            .orderBy('createdAt', descending: true)
            .limit(300);
      } else {
        q = db
            .collection('updates')
            .where('targetRoles', arrayContains: 'sub_nodal')
            .where('blockId', whereIn: keys.take(10).toList())
            .orderBy('createdAt', descending: true)
            .limit(300);
      }
      break;
    case UserRole.superNodal:
    case UserRole.devAdmin:
      q = db
          .collection('updates')
          .where('targetRoles', arrayContainsAny: ['super_nodal', 'sub_nodal'])
          .orderBy('createdAt', descending: true)
          .limit(300);
      break;
  }

  return q.snapshots();
});
