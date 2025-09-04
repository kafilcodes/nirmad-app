import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UpdatesRepository {
  UpdatesRepository(this._db);
  final FirebaseFirestore _db;

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
}

final updatesRepositoryProvider = Provider<UpdatesRepository>((ref) {
  return UpdatesRepository(FirebaseFirestore.instance);
});
