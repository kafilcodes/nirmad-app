import 'package:firebase_core/firebase_core.dart' as fc;
import 'package:firebase_storage/firebase_storage.dart' as fs;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Return a FirebaseStorage instance tied to the current app and its configured bucket as-is.
// Some projects use buckets named like "<project>.firebasestorage.app"; do not coerce to appspot.com.
fs.FirebaseStorage storageForCurrentApp() {
  final app = fc.Firebase.app();
  // Prefer explicit env override across all platforms
  final envBucket = dotenv.maybeGet('FIREBASE_STORAGE_BUCKET');
  if (envBucket != null && envBucket.isNotEmpty) {
    return fs.FirebaseStorage.instanceFor(bucket: envBucket);
  }
  // Fallback to the app's configured bucket
  final bucket = app.options.storageBucket;
  if (bucket != null && bucket.isNotEmpty) {
    return fs.FirebaseStorage.instanceFor(bucket: bucket);
  }
  // Last resort: default instance
  return fs.FirebaseStorage.instance;
}
