import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';

/// Lightweight, centralized Firebase helpers to reduce boilerplate and keep
/// behavior consistent across the app. Wraps core SDKs and exposes small
/// convenience methods. Existing repositories/services can adopt this
/// incrementally without breaking public APIs.
class FirebaseClient {
  final fb.FirebaseAuth auth;
  final FirebaseFirestore db;
  final FirebaseStorage storage;
  FirebaseClient({fb.FirebaseAuth? auth, FirebaseFirestore? db, FirebaseStorage? storage})
      : auth = auth ?? fb.FirebaseAuth.instance,
        db = db ?? FirebaseFirestore.instance,
        storage = storage ?? FirebaseStorage.instance;

  // Auth shortcuts
  fb.User? get currentUser => auth.currentUser;
  Future<fb.User?> refreshIdToken() async {
    await currentUser?.getIdToken(true);
    return auth.currentUser;
  }

  // Firestore helpers
  DocumentReference<Map<String, dynamic>> userDoc(String uid) => db.collection('users').doc(uid);
  DocumentReference<Map<String, dynamic>> projectDoc(String id) => db.collection('projects').doc(id);
  CollectionReference<Map<String, dynamic>> projectUpdates(String projectId) => projectDoc(projectId).collection('updates');

  // Storage helpers
  Reference projectRoot(String projectId) => storage.ref().child('projects').child(projectId);
  Future<String> putBytes(Reference ref, List<int> bytes, {String? contentType, SettableMetadata? metadata}) async {
    final m = metadata ?? SettableMetadata(contentType: contentType);
    final task = await ref.putData(Uint8List.fromList(bytes), m);
    return task.ref.fullPath;
  }
}
