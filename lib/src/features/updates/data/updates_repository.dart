import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../data/firestore/firestore_dao.dart';
import '../../../data/firestore/query_spec.dart';

class UpdatesRepository {
  UpdatesRepository(this._db, this._dao);
  final FirebaseFirestore _db;
  final FirestoreDao _dao;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('updates');

  Future<void> addEventForOwner({
    required String projectId,
    required String projectName,
    required String ownerId,
    required String blockId,
    required String actorId,
    required String actorRole,
    required String action, // 'created' | 'updated'
  }) async {
    final title = 'Project $action';
    final body = '$projectName has been $action.';
    await _col.add({
      'type': 'event',
      'projectId': projectId,
      'projectName': projectName,
      'ownerId': ownerId,
      'blockId': blockId,
      'actorId': actorId,
      'actorRole': actorRole,
      'title': title,
      'body': body,
      'userId': ownerId, // target owner
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addEventForNodals({
    required String projectId,
    required String projectName,
    required String ownerId,
    required String blockId,
    required String actorId,
    required String actorRole,
    required String action,
  }) async {
    // Role-targeted doc; unread tracked via readBy array for nodal users.
    await _col.add({
      'type': 'event',
      'projectId': projectId,
      'projectName': projectName,
      'ownerId': ownerId,
      'blockId': blockId,
      'actorId': actorId,
      'actorRole': actorRole,
      'title': 'Project $action',
      'body': '$projectName has been $action.',
      'targetRoles': ['super_nodal', 'sub_nodal'],
      'readBy': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addCommentForOwner({
    required String projectId,
    required String projectName,
    required String ownerId,
    required String blockId,
    required String actorId,
    required String actorRole,
    required String comment,
  }) async {
    await _col.add({
      'type': 'comment',
      'projectId': projectId,
      'projectName': projectName,
      'ownerId': ownerId,
      'blockId': blockId,
      'actorId': actorId,
      'actorRole': actorRole,
      'title': 'New comment',
      'body': comment,
      'userId': ownerId, // target owner
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAsRead(DocumentReference<Map<String, dynamic>> ref, {required String uid, required bool targetedToUser}) async {
    if (targetedToUser) {
      await ref.set({'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } else {
      await ref.update({'readBy': FieldValue.arrayUnion([uid])});
    }
  }

  Future<void> markAllAsRead(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {required String uid}) async {
    final b = _db.batch();
    for (final d in docs) {
      final m = d.data();
      if (m['userId'] != null) {
        b.set(d.reference, {'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      } else {
        b.update(d.reference, {'readBy': FieldValue.arrayUnion([uid])});
      }
    }
    await b.commit();
  }

  /// Mark a mixed list of notifications as read using refs and targetedToUser flags.
  /// Use this when you already have document refs and know whether each is targeted to a single user.
  Future<void> markAllAsReadMixed(
    List<({DocumentReference<Map<String, dynamic>> ref, bool targetedToUser})> items, {
    required String uid,
  }) async {
    final b = _db.batch();
    for (final item in items) {
      if (item.targetedToUser) {
        b.set(item.ref, {'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      } else {
        b.update(item.ref, {'readBy': FieldValue.arrayUnion([uid])});
      }
    }
    await b.commit();
  }

  Future<void> hide(DocumentReference<Map<String, dynamic>> ref, {required String uid, required bool isUnread, required bool targetedToUser}) async {
    if (!isUnread) {
      await ref.set({'hiddenFor': FieldValue.arrayUnion([uid])}, SetOptions(merge: true));
      return;
    }
    await markAsRead(ref, uid: uid, targetedToUser: targetedToUser);
  }

  Future<void> delete(DocumentReference<Map<String, dynamic>> ref) async {
    await ref.delete();
  }

  Future<void> triageAck({
    required String projectId,
    required String updateId,
    required DocumentReference<Map<String, dynamic>> notifRef,
    required String uid,
  }) async {
    await _db.collection('projects').doc(projectId).collection('updates').doc(updateId).set({
      'triage': {
        'status': 'ack',
        'ackBy': uid,
        'ackAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
    await notifRef.set({
      'triageStatus': 'ack',
      'triageBy': uid,
      'triageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> triageDone({
    required String projectId,
    required String updateId,
    required DocumentReference<Map<String, dynamic>> notifRef,
    required String uid,
  }) async {
    await _db.collection('projects').doc(projectId).collection('updates').doc(updateId).set({
      'triage': {
        'status': 'done',
        'doneBy': uid,
        'doneAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
    await notifRef.set({
      'triageStatus': 'done',
      'triageBy': uid,
      'triageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // SWR-style list fetches (non-stream) for cache-first UX when needed
  Future<List<Map<String, dynamic>>> listForOwner({required String uid, int limit = 300, Duration ttl = const Duration(minutes: 10)}) async {
    final spec = QuerySpec(path: 'updates', filters: {'userId': uid, 'order': 'createdAt_desc', 'limit': limit}, limit: limit);
    final list = await _dao.getList<Map<String, dynamic>>(
      spec: spec,
      build: (col) => col.where('userId', isEqualTo: uid).orderBy('createdAt', descending: true).limit(limit),
      fromDoc: (doc) => {'id': doc.id, ...?doc.data()},
      ttl: ttl,
    );
    return list;
  }

  Future<List<Map<String, dynamic>>> listForSubNodal({required String blockId, int limit = 500, Duration ttl = const Duration(minutes: 10)}) async {
    if (blockId.isEmpty) return const [];
    final spec = QuerySpec(path: 'updates', filters: {'role': 'sub', 'blockId': blockId, 'order': 'createdAt_desc', 'limit': limit}, limit: limit);
    final list = await _dao.getList<Map<String, dynamic>>(
      spec: spec,
      build: (col) => col.where('targetRoles', arrayContains: 'sub_nodal').where('blockId', isEqualTo: blockId).orderBy('createdAt', descending: true).limit(limit),
      fromDoc: (doc) => {'id': doc.id, ...?doc.data()},
      ttl: ttl,
    );
    return list;
  }

  Future<List<Map<String, dynamic>>> listForSuperOrAdmin({int limit = 500, Duration ttl = const Duration(minutes: 10)}) async {
    final spec = const QuerySpec(path: 'updates', filters: {'role': 'super', 'order': 'createdAt_desc'}, limit: 500);
    final list = await _dao.getList<Map<String, dynamic>>(
      spec: spec,
      build: (col) => col.where('targetRoles', arrayContainsAny: ['super_nodal', 'sub_nodal']).orderBy('createdAt', descending: true).limit(limit),
      fromDoc: (doc) => {'id': doc.id, ...?doc.data()},
      ttl: ttl,
    );
    return list;
  }
}

final updatesRepositoryProvider = Provider<UpdatesRepository>((ref) {
  return UpdatesRepository(ref.watch(firestoreProvider), ref.watch(firestoreDaoProvider));
});
