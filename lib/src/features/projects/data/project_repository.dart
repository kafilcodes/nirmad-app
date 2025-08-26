import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(FirebaseStorage.instance);
});
