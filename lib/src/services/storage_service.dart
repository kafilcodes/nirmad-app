import 'dart:io';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:fire_storage_impl/data/data_sources/fire_storage_service_impl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

class StorageService {
  StorageService(this._storage);
  final FirebaseStorage _storage;

  // Limits (per file)
  static const maxPhotoBytes = 7 * 1024 * 1024; // 7MB per photo (section 2 allows up to 7MB)
  static const maxDocBytes = 20 * 1024 * 1024; // 20MB per doc
  static const maxVideoBytes = 20 * 1024 * 1024; // 20MB per video

  Stream<TaskSnapshot> uploadWithProgress({required String path, required File file, SettableMetadata? metadata}) {
    final ref = _storage.ref(path);
    final task = ref.putFile(file, metadata);
    return task.snapshotEvents;
  }

  // Streamed upload for in-memory bytes (used by offline DraftMediaStore pipeline)
  Stream<TaskSnapshot> uploadBytesWithProgress({required String path, required List<int> bytes, SettableMetadata? metadata}) {
    final ref = _storage.ref(path);
    final task = ref.putData(Uint8List.fromList(bytes), metadata);
    return task.snapshotEvents;
  }

  Future<String> uploadProjectPhoto({required String projectId, required File file}) async {
    final path = 'projects/$projectId/photos/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final ref = _storage.ref(path);
  final task = await ref.putFile(
      file,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
      // Used by Storage Security Rules to validate the uploader
      'uploaderId': fb.FirebaseAuth.instance.currentUser?.uid ?? '',
        },
      ),
    );
    if (task.state != TaskState.success) {
      throw Exception('Upload failed');
    }
    return path;
  }

  Future<String> uploadProjectDoc({required String projectId, required File file}) async {
    final path = 'projects/$projectId/docs/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final ref = _storage.ref(path);
  // Infer contentType; default to application/pdf
  final lower = file.path.toLowerCase();
  String contentType = 'application/pdf';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    contentType = 'image/jpeg';
  } else if (lower.endsWith('.png')) {
    contentType = 'image/png';
  } else if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
    contentType = 'image/heic';
  } else if (lower.endsWith('.xls')) {
    contentType = 'application/vnd.ms-excel';
  } else if (lower.endsWith('.xlsx')) {
    contentType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  } else if (lower.endsWith('.csv')) {
    contentType = 'text/csv';
  } else if (lower.endsWith('.doc')) {
    contentType = 'application/msword';
  } else if (lower.endsWith('.docx')) {
    contentType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  final task = await ref.putFile(
      file,
      SettableMetadata(
        contentType: contentType,
        customMetadata: {
      'uploaderId': fb.FirebaseAuth.instance.currentUser?.uid ?? '',
        },
      ),
    );
    if (task.state != TaskState.success) {
      throw Exception('Upload failed');
    }
    return path;
  }

  Future<String> uploadProjectVideo({required String projectId, required File file}) async {
    final path = 'projects/$projectId/videos/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final ref = _storage.ref(path);
  final task = await ref.putFile(
      file,
      SettableMetadata(
        contentType: 'video/mp4',
        customMetadata: {
      'uploaderId': fb.FirebaseAuth.instance.currentUser?.uid ?? '',
        },
      ),
    );
    if (task.state != TaskState.success) {
      throw Exception('Upload failed');
    }
    return path;
  }

  Future<String> uploadBytes({required String path, required List<int> bytes, SettableMetadata? metadata}) async {
    final ref = _storage.ref(path);
    final meta = (() {
      if (kIsWeb) {
        // Avoid custom metadata on web to minimize CORS preflight complexity
  return metadata ?? SettableMetadata();
      }
      return metadata ?? SettableMetadata(customMetadata: {
        'uploaderId': fb.FirebaseAuth.instance.currentUser?.uid ?? '',
      });
    })();
    final task = await ref.putData(Uint8List.fromList(bytes), meta);
    if (task.state != TaskState.success) {
      throw Exception('Upload failed');
    }
    return path;
  }

  // Resolve a storage path like 'projects/..../file.ext' to a signed download URL
  Future<String> getDownloadURL(String path) async {
    final ref = _storage.ref(path);
    final url = await ref.getDownloadURL();
    return url;
  }

  // Adapter: use fire_storage_impl with XFile when not on web; ensures our metadata (uploaderId)
  Future<String> uploadWithAdapter({
    required String path,
    required List<int> bytes,
    String? fileName,
    String? contentType,
    void Function(double progress)? onProgress,
  }) async {
    final uid = fb.FirebaseAuth.instance.currentUser?.uid ?? '';
    final meta = <String, String>{'uploaderId': uid};
    // On Web, or when we prefer in-memory, use native putData (respects rules and progress elsewhere)
    if (kIsWeb) {
      final ref = _storage.ref(path);
  // Drop customMetadata on web
  final task = ref.putData(Uint8List.fromList(bytes), SettableMetadata(contentType: contentType));
      await for (final s in task.snapshotEvents) {
        if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
      }
      if (task.snapshot.state != TaskState.success) throw Exception('Upload failed');
      return path;
    }
    // Non-web: write to temp and call FireStorageServiceImpl (which uses putData under the hood as well)
    final name = fileName ?? p.basename(path);
    final xf = XFile.fromData(Uint8List.fromList(bytes), name: name, mimeType: contentType);
    // The package’s service builds its own path from category/collection/fullName; we pass full path via collectionPath.
    // We’ll split our path to category + collectionPath + fileName to avoid double slashes.
    final segments = path.split('/');
    final fullName = segments.isNotEmpty ? segments.last : name;
    final category = segments.isNotEmpty ? segments.first : null;
    final collectionPath = segments.length > 2 ? segments.sublist(1, segments.length - 1).join('/') : null;
    final svc = FireStorageServiceImpl(fireStorage: _storage);
    final url = await svc.uploadFile(
      file: xf,
      fileName: p.basenameWithoutExtension(fullName),
      category: category,
      collectionPath: collectionPath,
      metadata: meta,
      onProgress: onProgress,
    );
    if (url == null) throw Exception('Upload failed');
    return path; // We return the storage path used; caller may resolve URL separately if needed
  }
}
