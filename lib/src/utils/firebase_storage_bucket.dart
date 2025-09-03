import 'package:firebase_core/firebase_core.dart' as fc;
import 'package:firebase_storage/firebase_storage.dart' as fs;

// Normalize bucket values: developers sometimes copy the download domain
// like "<project>.firebasestorage.app", but Firebase SDKs expect the
// bucket ID in the form "<project>.appspot.com".
String normalizeStorageBucket(String? bucket) {
  if (bucket == null || bucket.isEmpty) return '';
  if (bucket.endsWith('.firebasestorage.app')) {
    return bucket.replaceFirst('.firebasestorage.app', '.appspot.com');
  }
  return bucket;
}

// Get a FirebaseStorage instance tied to the current app with a normalized bucket.
fs.FirebaseStorage storageForCurrentApp() {
  final app = fc.Firebase.app();
  final normalized = normalizeStorageBucket(app.options.storageBucket);
  if (normalized.isNotEmpty) {
    return fs.FirebaseStorage.instanceFor(bucket: normalized);
  }
  return fs.FirebaseStorage.instance;
}
