import 'package:cloud_firestore/cloud_firestore.dart';
// Storage service is provided via provider using normalized bucket
import '../../../utils/firebase_storage_bucket.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../domain/project.dart';
import '../domain/project_update.dart';
import '../../../services/storage_service.dart';

class ProjectRepository {
  ProjectRepository(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('projects');

  Query<Map<String, dynamic>> ownerQuery(String ownerId) => _col
      .where('ownerId', isEqualTo: ownerId)
      .orderBy('updatedAt', descending: true);

  Stream<List<Project>> watchOwnerProjects({required String ownerId, int limit = 20, DocumentSnapshot? startAfter}) {
    Query<Map<String, dynamic>> q = ownerQuery(ownerId).limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    return q.snapshots().map((s) => s.docs.map(Project.fromDoc).toList());
  }

  Future<Project?> getById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return Project.fromDoc(doc);
  }

  Future<String> create(Project project) async {
    final ref = await _col.add(project.toFirestore());
    return ref.id;
  }

  // Generates and returns the next sequential project code like DMTNY-1, DMTNY-2 ...
  Future<String> nextProjectCode() async {
    final counterRef = _db.collection('counters').doc('projects');
    return _db.runTransaction((tx) async {
      final snap = await tx.get(counterRef);
      int current = 0;
      if (snap.exists) {
        final data = snap.data();
        if (data != null) {
          current = (data['next'] as int?) ?? 0;
        }
      }
      final next = current + 1;
      tx.set(counterRef, {'next': next}, SetOptions(merge: true));
      return 'DMTNY-$next';
    });
  }

  Future<void> setProjectCode(String projectId, String code) async {
    await _col.doc(projectId).set({'projectCode': code}, SetOptions(merge: true));
  }

  Future<void> update(Project project) => _col.doc(project.id).update(project.toFirestore());

  // Updates subcollection
  CollectionReference<Map<String, dynamic>> _updatesCol(String projectId) => _col.doc(projectId).collection('updates');

  Stream<List<ProjectUpdate>> watchUpdates(String projectId) {
    return _updatesCol(projectId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => ProjectUpdate.fromDoc(projectId, d)).toList());
  }

  Future<String> addUpdate(String projectId, ProjectUpdate update) async {
    final ref = await _updatesCol(projectId).add(update.toFirestore());
    return ref.id;
  }
}

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(FirebaseFirestore.instance);
});

final ownerProjectsProvider = StreamProvider.autoDispose<List<Project>>((ref) {
  final auth = ref.watch(authStateProvider).value;
  if (auth == null) return const Stream.empty();
  return ref.read(projectRepositoryProvider).watchOwnerProjects(ownerId: auth.uid);
});

// Paged stream provider for owner's projects with adjustable limit
final ownerProjectsPagedProvider = StreamProvider.autoDispose.family<List<Project>, int>((ref, limit) {
  final auth = ref.watch(authStateProvider).value;
  if (auth == null) return const Stream.empty();
  final safeLimit = limit.clamp(5, 200);
  return ref.read(projectRepositoryProvider).watchOwnerProjects(ownerId: auth.uid, limit: safeLimit);
});

final storageServiceProvider = Provider<StorageService>((ref) {
  // Ensure we use the normalized bucket (env-driven on Web, platform config on mobile)
  return StorageService(storageForCurrentApp());
});
