import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/firestore/firestore_dao.dart';
import '../cache/disk_cache.dart';
import '../../utils/firebase/firebase_client.dart';
import '../prefs/shared_prefs.dart';

final firebaseClientProvider = Provider<FirebaseClient>((ref) {
  return FirebaseClient();
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final firestoreDaoProvider = Provider<FirestoreDao>((ref) {
  return FirestoreDao(ref.watch(firestoreProvider));
});

final diskCacheProvider = Provider<DiskCache>((ref) {
  final SharedPreferences prefs = ref.watch(sharedPrefsProvider);
  return DiskCache(prefs);
});
