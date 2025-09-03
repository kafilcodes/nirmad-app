import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SimpleRef {
  final String id;
  final String name;
  const SimpleRef({required this.id, required this.name});
}

final blocksProvider = StreamProvider.autoDispose<List<SimpleRef>>((ref) {
  final db = FirebaseFirestore.instance;
  final q = db.collection('blocks').orderBy('name');
  return q.snapshots().map((s) => s.docs.map((d) {
        final data = d.data();
        final name = (data['name'] as String?)?.trim();
        return SimpleRef(id: d.id, name: (name == null || name.isEmpty) ? d.id : name);
      }).toList());
});

final villagesByBlockProvider = StreamProvider.autoDispose.family<List<SimpleRef>, String>((ref, blockId) {
  if (blockId.isEmpty) return const Stream<List<SimpleRef>>.empty();
  final db = FirebaseFirestore.instance;
  // Expect village docs to have a blockId field; if not, this may return empty.
  final q = db.collection('villages').where('blockId', isEqualTo: blockId).orderBy('name');
  return q.snapshots().map((s) => s.docs.map((d) {
        final data = d.data();
        final name = (data['name'] as String?)?.trim();
        return SimpleRef(id: d.id, name: (name == null || name.isEmpty) ? d.id : name);
      }).toList());
});

// New reference data providers

// Gram Panchayats by Block
final gramPanchayatsByBlockProvider =
    StreamProvider.autoDispose.family<List<SimpleRef>, String>((ref, blockId) {
  if (blockId.isEmpty) return const Stream<List<SimpleRef>>.empty();
  final db = FirebaseFirestore.instance;
  final q = db
      .collection('gram_panchayats')
      .where('blockId', isEqualTo: blockId)
      .orderBy('name');
  return q.snapshots().map((s) => s.docs.map((d) {
        final data = d.data();
        final name = (data['name'] as String?)?.trim();
        return SimpleRef(id: d.id, name: (name == null || name.isEmpty) ? d.id : name);
      }).toList());
});

// Sanctioning Departments (all)
final sanctioningDepartmentsProvider =
    StreamProvider.autoDispose<List<SimpleRef>>((ref) {
  final db = FirebaseFirestore.instance;
  final q = db.collection('sanctioning_departments').orderBy('name');
  return q.snapshots().map((s) => s.docs.map((d) {
        final data = d.data();
        final name = (data['name'] as String?)?.trim();
        return SimpleRef(id: d.id, name: (name == null || name.isEmpty) ? d.id : name);
      }).toList());
});

// Schemes by Department
final schemesByDepartmentProvider =
    StreamProvider.autoDispose.family<List<SimpleRef>, String>((ref, deptId) {
  if (deptId.isEmpty) return const Stream<List<SimpleRef>>.empty();
  final db = FirebaseFirestore.instance;
  final q = db
      .collection('schemes')
      .where('departmentId', isEqualTo: deptId)
      .orderBy('name');
  return q.snapshots().map((s) => s.docs.map((d) {
        final data = d.data();
        final name = (data['name'] as String?)?.trim();
        return SimpleRef(id: d.id, name: (name == null || name.isEmpty) ? d.id : name);
      }).toList());
});

// Items by Scheme
final itemsBySchemeProvider =
    StreamProvider.autoDispose.family<List<SimpleRef>, String>((ref, schemeId) {
  if (schemeId.isEmpty) return const Stream<List<SimpleRef>>.empty();
  final db = FirebaseFirestore.instance;
  final q = db
      .collection('items')
      .where('schemeId', isEqualTo: schemeId)
      .orderBy('name');
  return q.snapshots().map((s) => s.docs.map((d) {
        final data = d.data();
        final name = (data['name'] as String?)?.trim();
        return SimpleRef(id: d.id, name: (name == null || name.isEmpty) ? d.id : name);
      }).toList());
});

// Plan Heads (all)
final planHeadsProvider = StreamProvider.autoDispose<List<SimpleRef>>((ref) {
  final db = FirebaseFirestore.instance;
  final q = db.collection('plan_heads').orderBy('name');
  return q.snapshots().map((s) => s.docs.map((d) {
        final data = d.data();
        final name = (data['name'] as String?)?.trim();
        return SimpleRef(id: d.id, name: (name == null || name.isEmpty) ? d.id : name);
      }).toList());
});

// Banks (all)
final banksProvider = StreamProvider.autoDispose<List<SimpleRef>>((ref) {
  final db = FirebaseFirestore.instance;
  final q = db.collection('banks').orderBy('name');
  return q.snapshots().map((s) => s.docs.map((d) {
        final data = d.data();
        final name = (data['name'] as String?)?.trim();
        return SimpleRef(id: d.id, name: (name == null || name.isEmpty) ? d.id : name);
      }).toList());
});