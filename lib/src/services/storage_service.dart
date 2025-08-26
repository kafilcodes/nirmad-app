import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  StorageService(this._storage);
  final FirebaseStorage _storage;

  Future<String> uploadProjectPhoto({required String projectId, required File file}) async {
    final path = 'projects/$projectId/photos/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final ref = _storage.ref(path);
    final task = await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    if (task.state != TaskState.success) {
      throw Exception('Upload failed');
    }
    return path;
  }

  Future<String> uploadProjectDoc({required String projectId, required File file}) async {
    final path = 'projects/$projectId/docs/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final ref = _storage.ref(path);
    final task = await ref.putFile(file);
    if (task.state != TaskState.success) {
      throw Exception('Upload failed');
    }
    return path;
  }
}
