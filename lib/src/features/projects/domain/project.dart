import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'project.freezed.dart';

// ignore: constant_identifier_names
enum ProjectStatus { draft, in_progress, completed, cancelled }

// Work stages for project progression
enum WorkStage { layout, plinth, lintel, finishing, completed }

// Apram status options
enum ApramStatus { incomplete, workStopped, preBuilt, others }

@freezed
class PreliminaryDescription with _$PreliminaryDescription {
  const factory PreliminaryDescription({
    String? sarpanchName,
    String? sarpanchMobile,
    String? gramPanchayat,
    String? secretaryName,
    String? secretaryMobile,
    String? subEngineerName,
    String? subEngineerMobile,
  }) = _PreliminaryDescription;

  const PreliminaryDescription._();

  factory PreliminaryDescription.fromMap(Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return PreliminaryDescription(
      sarpanchName: d['sarpanchName'] as String?,
      sarpanchMobile: d['sarpanchMobile'] as String?,
      gramPanchayat: d['gramPanchayat'] as String?,
      secretaryName: d['secretaryName'] as String?,
      secretaryMobile: d['secretaryMobile'] as String?,
      subEngineerName: d['subEngineerName'] as String?,
      subEngineerMobile: d['subEngineerMobile'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'sarpanchName': sarpanchName,
        'sarpanchMobile': sarpanchMobile,
        'gramPanchayat': gramPanchayat,
        'secretaryName': secretaryName,
        'secretaryMobile': secretaryMobile,
        'subEngineerName': subEngineerName,
        'subEngineerMobile': subEngineerMobile,
      }..removeWhere((k, v) => v == null);
}

@freezed
class SanctionCompliance with _$SanctionCompliance {
  const factory SanctionCompliance({
    String? sanctioningDepartmentId,
    String? sanctioningDepartmentName,
    String? technicalApprovalNo,
    DateTime? technicalApprovalDate,
    String? adminApprovalNo,
    DateTime? adminApprovalDate,
    String? schemeId,
    String? schemeName,
    String? itemId,
    String? itemName,
    String? planHeadId,
    String? planHeadName,
    num? approvedAmount,
    // document references
    @Default(<String>[]) List<String> approvalDocumentUrls,
  }) = _SanctionCompliance;

  const SanctionCompliance._();

  factory SanctionCompliance.fromMap(Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return SanctionCompliance(
      sanctioningDepartmentId: d['sanctioningDepartmentId'] as String?,
      sanctioningDepartmentName: d['sanctioningDepartmentName'] as String?,
      technicalApprovalNo: d['technicalApprovalNo'] as String?,
      technicalApprovalDate: _toDateTime(d['technicalApprovalDate']),
      adminApprovalNo: d['adminApprovalNo'] as String?,
      adminApprovalDate: _toDateTime(d['adminApprovalDate']),
      schemeId: d['schemeId'] as String?,
      schemeName: d['schemeName'] as String?,
      itemId: d['itemId'] as String?,
      itemName: d['itemName'] as String?,
      planHeadId: d['planHeadId'] as String?,
      planHeadName: d['planHeadName'] as String?,
      approvedAmount: d['approvedAmount'] as num?,
      approvalDocumentUrls: ((d['approvalDocumentUrls'] as List?) ?? const []).whereType<String>().toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'sanctioningDepartmentId': sanctioningDepartmentId,
        'sanctioningDepartmentName': sanctioningDepartmentName,
        'technicalApprovalNo': technicalApprovalNo,
        'technicalApprovalDate': technicalApprovalDate == null ? null : Timestamp.fromDate(technicalApprovalDate!),
        'adminApprovalNo': adminApprovalNo,
        'adminApprovalDate': adminApprovalDate == null ? null : Timestamp.fromDate(adminApprovalDate!),
        'schemeId': schemeId,
        'schemeName': schemeName,
        'itemId': itemId,
        'itemName': itemName,
        'planHeadId': planHeadId,
        'planHeadName': planHeadName,
        'approvedAmount': approvedAmount,
        'approvalDocumentUrls': approvalDocumentUrls,
      }..removeWhere((k, v) => v == null);
}

@freezed
class Installment with _$Installment {
  const factory Installment({
    num? amount,
    DateTime? date,
    num? receivedAmount,
    DateTime? receivedDate,
  }) = _Installment;

  const Installment._();

  factory Installment.fromMap(Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return Installment(
      amount: d['amount'] as num?,
      date: _toDateTime(d['date']),
      receivedAmount: d['receivedAmount'] as num?,
      receivedDate: _toDateTime(d['receivedDate']),
    );
  }

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'date': date == null ? null : Timestamp.fromDate(date!),
        'receivedAmount': receivedAmount,
        'receivedDate': receivedDate == null ? null : Timestamp.fromDate(receivedDate!),
      }..removeWhere((k, v) => v == null);
}

@freezed
class BankDetails with _$BankDetails {
  const factory BankDetails({
    String? bankId,
    String? bankName,
    String? accountNumber,
    String? branch,
    String? ifsc,
  }) = _BankDetails;

  const BankDetails._();

  factory BankDetails.fromMap(Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return BankDetails(
      bankId: d['bankId'] as String?,
      bankName: d['bankName'] as String?,
      accountNumber: d['accountNumber'] as String?,
      branch: d['branch'] as String?,
      ifsc: d['ifsc'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'bankId': bankId,
        'bankName': bankName,
        'accountNumber': accountNumber,
        'branch': branch,
        'ifsc': ifsc,
      }..removeWhere((k, v) => v == null);
}

@freezed
class AllotmentDetails with _$AllotmentDetails {
  const factory AllotmentDetails({
    Installment? installment1,
    Installment? installment2,
    Installment? installment3,
    BankDetails? bankDetails,
  }) = _AllotmentDetails;

  const AllotmentDetails._();

  factory AllotmentDetails.fromMap(Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    return AllotmentDetails(
      installment1: Installment.fromMap(d['installment1'] as Map<String, dynamic>?),
      installment2: Installment.fromMap(d['installment2'] as Map<String, dynamic>?),
      installment3: Installment.fromMap(d['installment3'] as Map<String, dynamic>?),
      bankDetails: BankDetails.fromMap(d['bankDetails'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toMap() => {
        'installment1': installment1?.toMap(),
        'installment2': installment2?.toMap(),
        'installment3': installment3?.toMap(),
        'bankDetails': bankDetails?.toMap(),
      }..removeWhere((k, v) => v == null);
}

@freezed
class WorkDescription with _$WorkDescription {
  const factory WorkDescription({
    DateTime? startDate,
    WorkStage? stage,
    ApramStatus? apramStatus,
    @Default(<String>[]) List<String> measurementBookUrls,
    @Default(<String>[]) List<String> testReportUrls,
    @Default(<String>[]) List<String> workReportUrls,
    @Default(<String>[]) List<String> certificateUrls,
  }) = _WorkDescription;

  const WorkDescription._();

  factory WorkDescription.fromMap(Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    WorkStage? stage;
    final ss = d['stage'] as String?;
    if (ss != null) {
      stage = WorkStage.values.firstWhere(
        (e) => e.name == ss,
        orElse: () => WorkStage.layout,
      );
    }
    ApramStatus? apram;
    final as = d['apramStatus'] as String?;
    if (as != null) {
      apram = ApramStatus.values.firstWhere(
        (e) => e.name == as,
        orElse: () => ApramStatus.incomplete,
      );
    }
    return WorkDescription(
      startDate: _toDateTime(d['startDate']),
      stage: stage,
      apramStatus: apram,
      measurementBookUrls: ((d['measurementBookUrls'] as List?) ?? const []).whereType<String>().toList(),
      testReportUrls: ((d['testReportUrls'] as List?) ?? const []).whereType<String>().toList(),
      workReportUrls: ((d['workReportUrls'] as List?) ?? const []).whereType<String>().toList(),
      certificateUrls: ((d['certificateUrls'] as List?) ?? const []).whereType<String>().toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'startDate': startDate == null ? null : Timestamp.fromDate(startDate!),
        'stage': stage?.name,
        'apramStatus': apramStatus?.name,
        'measurementBookUrls': measurementBookUrls,
        'testReportUrls': testReportUrls,
        'workReportUrls': workReportUrls,
        'certificateUrls': certificateUrls,
      }..removeWhere((k, v) => v == null);
}

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
    String? address,
    String? geohash,
    String? mapSnapshotUrl,
    @Default({}) Map<String, dynamic> landDetails,
    @Default({}) Map<String, dynamic> financials,

    // Preliminary Description (Section 1)
    @Default(PreliminaryDescription()) PreliminaryDescription preliminaryDescription,

    // Sanction & Compliance (Section 2)
    @Default(SanctionCompliance()) SanctionCompliance sanctionCompliance,

    // Allotment Amount Details (Section 3)
    @Default(AllotmentDetails()) AllotmentDetails allotmentDetails,

    // Work Description (Section 4)
    @Default(WorkDescription()) WorkDescription workDescription,

    // Media manifests
    @Default(<String>[]) List<String> photoUrls,
    @Default(<String>[]) List<String> documentUrls,
    @Default(<String>[]) List<String> videoUrls,
    // Immutable originals captured at creation (ids/urls)
    @Default(<String>[]) List<String> originalPhotoUrls,

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
      address: data['address'] as String?,
      geohash: data['geohash'] as String?,
      mapSnapshotUrl: data['mapSnapshotUrl'] as String?,
      landDetails: (data['landDetails'] as Map<String, dynamic>?) ?? const {},
      financials: (data['financials'] as Map<String, dynamic>?) ?? const {},

      // New sections
      preliminaryDescription: PreliminaryDescription.fromMap(data['preliminaryDescription'] as Map<String, dynamic>?),
      sanctionCompliance: SanctionCompliance.fromMap(data['sanctionCompliance'] as Map<String, dynamic>?),
      allotmentDetails: AllotmentDetails.fromMap(data['allotmentDetails'] as Map<String, dynamic>?),
      workDescription: WorkDescription.fromMap(data['workDescription'] as Map<String, dynamic>?),

      photoUrls: ((data['photoUrls'] as List?) ?? const []).whereType<String>().toList(),
      documentUrls: ((data['documentUrls'] as List?) ?? const []).whereType<String>().toList(),
      videoUrls: ((data['videoUrls'] as List?) ?? const []).whereType<String>().toList(),
      originalPhotoUrls: ((data['originalPhotoUrls'] as List?) ?? const []).whereType<String>().toList(),
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
      'address': address,
      'geohash': geohash,
      'mapSnapshotUrl': mapSnapshotUrl,
      'landDetails': landDetails,
      'financials': financials,

      // New sections
      'preliminaryDescription': preliminaryDescription.toMap(),
      'sanctionCompliance': sanctionCompliance.toMap(),
      'allotmentDetails': allotmentDetails.toMap(),
      'workDescription': workDescription.toMap(),

      'photoUrls': photoUrls,
      'documentUrls': documentUrls,
      'videoUrls': videoUrls,
      'originalPhotoUrls': originalPhotoUrls,
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
