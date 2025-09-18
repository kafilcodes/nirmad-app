import 'package:cloud_firestore/cloud_firestore.dart';
// Storage service is provided via provider using normalized bucket
import '../../../utils/firebase_storage_bucket.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../domain/project.dart';
import '../domain/project_update.dart';
import '../../../services/storage_service.dart';
import '../../../data/firestore/firestore_dao.dart';
import '../../../data/firestore/query_spec.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/domain/app_user.dart';

// Lightweight DTO to carry update along with its raw payload and type for richer UIs
class UpdateWithPayload {
  final ProjectUpdate update;
  final String? type;
  final Map<String, dynamic>? payload;
  const UpdateWithPayload({required this.update, this.type, this.payload});
}

class ProjectRepository {
  ProjectRepository(this._db, {FirestoreDao? dao}) : _dao = dao ?? FirestoreDao(FirebaseFirestore.instance);
  final FirebaseFirestore _db;
  final FirestoreDao _dao;

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

  // Cached list fetch (SWR). Not realtime. Use on overview dashboards to cut reads.
  Future<List<Project>> fetchOwnerProjectsCached({required String ownerId, int limit = 20}) async {
    final spec = QuerySpec(path: 'projects', filters: {'ownerId': ownerId}, limit: limit);
    return _dao.getList<Project>(
      spec: spec,
      build: (col) => col.where('ownerId', isEqualTo: ownerId).orderBy('updatedAt', descending: true).limit(limit),
      fromDoc: Project.fromDoc,
      ttl: const Duration(minutes: 5),
    );
  }

  Future<Project?> getById(String id) async {
  // Cached fetch via DAO (stale-while-revalidate)
  return _dao.getDoc(path: 'projects/$id', fromDoc: Project.fromDoc);
  }

  Future<String> create(Project project) async {
    final ref = await _col.add(project.toFirestore());
    return ref.id;
  }

  // Pre-allocate a document ID without writing anything yet.
  String allocateId() {
    return _col.doc().id;
  }

  // Create a document at a specific ID. Useful for upload-first workflows.
  Future<void> createAt(String id, Project project, {Map<String, dynamic>? extra}) async {
    final data = project.toFirestore();
    if (extra != null && extra.isNotEmpty) {
      data.addAll(extra);
    }
    await _col.doc(id).set(data);
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

  Stream<List<UpdateWithPayload>> watchUpdatesWithPayload(String projectId) {
    return _updatesCol(projectId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) {
              final u = ProjectUpdate.fromDoc(projectId, d);
              final data = d.data();
              return UpdateWithPayload(
                update: u,
                type: data['type'] as String?,
                payload: (data['payload'] as Map?)?.cast<String, dynamic>(),
              );
            }).toList());
  }

  Future<String> addUpdate(String projectId, ProjectUpdate update) async {
    final ref = await _updatesCol(projectId).add(update.toFirestore());
    return ref.id;
  }
}

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(ref.watch(firestoreProvider), dao: ref.watch(firestoreDaoProvider));
});

final ownerProjectsProvider = StreamProvider.autoDispose<List<Project>>((ref) {
  final auth = ref.watch(authStateProvider).value;
  if (auth == null) return const Stream.empty();
  return ref.read(projectRepositoryProvider).watchOwnerProjects(ownerId: auth.uid);
});

// Cached owner projects provider: emits cached value immediately, then refreshes in background.
final ownerProjectsCachedProvider = FutureProvider.autoDispose<List<Project>>((ref) async {
  final auth = ref.watch(authStateProvider).value;
  if (auth == null) return const <Project>[];
  return ref.read(projectRepositoryProvider).fetchOwnerProjectsCached(ownerId: auth.uid, limit: 50);
});

/// Disk-first cached owner projects for instant UI, falls back to SWR fetch.
final ownerProjectsDiskFirstProvider = FutureProvider.autoDispose<List<Project>>((ref) async {
  final auth = ref.watch(authStateProvider).value;
  if (auth == null) return const <Project>[];
  final disk = ref.watch(diskCacheProvider);
  final key = 'ownerProjects:${auth.uid}';
  final cached = disk.getJson<List<Project>>(key, (v) {
    final list = (v as List?) ?? const [];
    return list.map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return Project(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        ownerId: auth.uid,
        blockId: (m['blockId'] as String?) ?? '',
        villageId: '',
        status: ProjectStatus.values.firstWhere(
          (s) => s.name == ((m['status'] as String? ?? 'in_progress') == 'draft' ? 'in_progress' : (m['status'] as String? ?? 'in_progress')),
          orElse: () => ProjectStatus.in_progress,
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updatedAt'] as num?)?.toInt() ?? 0),
      );
    }).toList();
  });
  if (cached != null && cached.isNotEmpty) return cached;
  return ref.read(projectRepositoryProvider).fetchOwnerProjectsCached(ownerId: auth.uid, limit: 50);
});

/// Disk-first generic nodal first-page list for immediate render; UI will filter.
final nodalFirstPageDiskFirstProvider = FutureProvider.autoDispose<List<Project>>((ref) async {
  final auth = ref.watch(authStateProvider).value;
  if (auth == null) return const <Project>[];
  if (auth.role == UserRole.projectOwner) return const <Project>[];
  final disk = ref.watch(diskCacheProvider);
  final cached = disk.getJson<List<Project>>('nodal:projects:first', (v) {
    final list = (v as List?) ?? const [];
    return list.map((e) {
      final m = (e as Map).cast<String, dynamic>();
  final statusKey = ((m['status'] as String?) ?? 'in_progress') == 'draft' ? 'in_progress' : ((m['status'] as String?) ?? 'in_progress');
      return Project(
        id: (m['id'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        description: m['description'] as String?,
        ownerId: (m['ownerId'] as String?) ?? '',
        blockId: (m['blockId'] as String?) ?? '',
        villageId: (m['villageId'] as String?) ?? '',
  status: ProjectStatus.values.firstWhere((s) => s.name == statusKey, orElse: () => ProjectStatus.in_progress),
        phase: (m['phase'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['createdAt'] as num?)?.toInt() ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updatedAt'] as num?)?.toInt() ?? 0),
      );
    }).toList();
  });
  return cached ?? const <Project>[];
});

/// Disk-first project detail by ID for instant re-open, then refreshes via DAO.
final projectByIdDiskFirstProvider = FutureProvider.autoDispose.family<Project?, String>((ref, id) async {
  final disk = ref.watch(diskCacheProvider);
  final cached = disk.getJson<Project>('project:detail:$id', (v) {
    final m = (v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{});
  final statusKey = ((m['status'] as String?) ?? 'in_progress') == 'draft' ? 'in_progress' : ((m['status'] as String?) ?? 'in_progress');
    return Project(
      id: id,
      name: (m['name'] as String?) ?? '',
      description: m['description'] as String?,
      ownerId: (m['ownerId'] as String?) ?? '',
      blockId: (m['blockId'] as String?) ?? '',
      villageId: (m['villageId'] as String?) ?? '',
  status: ProjectStatus.values.firstWhere((s) => s.name == statusKey, orElse: () => ProjectStatus.in_progress),
      phase: (m['phase'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch((m['createdAt'] as num?)?.toInt() ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updatedAt'] as num?)?.toInt() ?? 0),
    );
  });
  if (cached != null) return cached;
  return ref.read(projectRepositoryProvider).getById(id);
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
