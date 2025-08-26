import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'project.freezed.dart';

enum ProjectStatus { draft, in_progress, completed, cancelled }

@freezed
class Project with _$Project {
  const factory Project({
    required String id,
    required String name,
    String? description,
    required String ownerId,
    required String blockId,
    required String villageId,
    @Default(ProjectStatus.draft) ProjectStatus status,
    @Default(0) int phase,
    GeoPoint? location,
    @Default({}) Map<String, dynamic> landDetails,
    @Default({}) Map<String, dynamic> financials,
    @Default(<String>[]) List<String> attachments,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? completedAt,
  }) = _Project;

  const Project._();

  static Project fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    ProjectStatus status = ProjectStatus.draft;
    final s = data['status'] as String?;
    if (s != null) {
      status = ProjectStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => ProjectStatus.draft,
      );
    }
    return Project(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      description: data['description'] as String?,
      ownerId: (data['ownerId'] as String?) ?? '',
      blockId: (data['blockId'] as String?) ?? '',
      villageId: (data['villageId'] as String?) ?? '',
      status: status,
      phase: (data['phase'] as num?)?.toInt() ?? 0,
      location: data['location'] as GeoPoint?,
      landDetails: (data['landDetails'] as Map<String, dynamic>?) ?? const {},
      financials: (data['financials'] as Map<String, dynamic>?) ?? const {},
      attachments: ((data['attachments'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      createdAt: _toDateTime(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _toDateTime(data['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: _toDateTime(data['completedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'ownerId': ownerId,
      'blockId': blockId,
      'villageId': villageId,
      'status': status.name,
      'phase': phase,
      'location': location,
      'landDetails': landDetails,
      'financials': financials,
      'attachments': attachments,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'completedAt': completedAt == null ? null : Timestamp.fromDate(completedAt!),
    }..removeWhere((key, value) => value == null);
  }
}

DateTime? _toDateTime(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}
