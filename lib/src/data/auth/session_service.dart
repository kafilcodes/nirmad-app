import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

class SessionService {
  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _db;
  SessionService(this._auth, this._db);

  // Call after login to register this device session. sessionId may be deviceId or randomly generated.
  Future<void> registerSession(String sessionId) async {
    final u = _auth.currentUser;
    if (u == null) return;
    final ref = _db.collection('users').doc(u.uid).collection('sessions').doc('current');
    await ref.set({
      'sessionId': sessionId,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': DateTime.now().add(const Duration(days: 180)), // 6 months client hint
    }, SetOptions(merge: true));
  }

  // Guard single-device: returns true if allowed, false if another active session exists.
  Future<bool> canUseCurrentDevice(String sessionId) async {
    final u = _auth.currentUser;
    if (u == null) return false;
    final ref = _db.collection('users').doc(u.uid).collection('sessions').doc('current');
    DocumentSnapshot<Map<String, dynamic>>? snap;
    // Prefer server to avoid stale cache after a just-completed logout.
    try {
      snap = await ref.get(const GetOptions(source: Source.server));
    } catch (_) {
      try { snap = await ref.get(const GetOptions(source: Source.cache)); } catch (_) {}
    }
    if (snap == null || !snap.exists) return true;
    final activeId = snap.data()?['sessionId'] as String?;
    return activeId == null || activeId == sessionId;
  }

  /// Delete session doc only if it matches the provided sessionId.
  Future<void> clearSessionIfMatches(String sessionId) async {
    final u = _auth.currentUser;
    if (u == null) return;
    final ref = _db.collection('users').doc(u.uid).collection('sessions').doc('current');
    try {
      final snap = await ref.get();
      final activeId = snap.data()?['sessionId'] as String?;
      if (activeId == sessionId) {
        await ref.delete().catchError((_) {});
      }
    } catch (_) {}
  }
}
