import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'project_update.freezed.dart';

@freezed
class ProjectUpdate with _$ProjectUpdate {
  const factory ProjectUpdate({
    required String id,
    required String projectId,
    required int phase,
    String? comment,
    @Default(<String>[]) List<String> photos,
    @Default(<String>[]) List<String> documents,
    required String updatedBy,
    required DateTime createdAt,
  }) = _ProjectUpdate;

  const ProjectUpdate._();

  static ProjectUpdate fromDoc(String projectId, DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ProjectUpdate(
      id: doc.id,
      projectId: projectId,
      phase: (data['phase'] as num?)?.toInt() ?? 0,
      comment: data['comment'] as String?,
      photos: ((data['photos'] as List?) ?? const []).whereType<String>().toList(),
      documents: ((data['documents'] as List?) ?? const []).whereType<String>().toList(),
      updatedBy: (data['updatedBy'] as String?) ?? '',
      createdAt: _toDateTime(data['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'phase': phase,
      'comment': comment,
      'photos': photos,
      'documents': documents,
      'updatedBy': updatedBy,
      'createdAt': Timestamp.fromDate(createdAt),
    }..removeWhere((k, v) => v == null);
  }
}

DateTime? _toDateTime(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}
