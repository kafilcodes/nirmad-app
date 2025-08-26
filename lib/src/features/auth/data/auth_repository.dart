import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_user.dart';

class AuthRepository {
  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _db;

  AuthRepository(this._auth, this._db);

  Stream<AppUser?> authStateChanges() async* {
    await for (final user in _auth.authStateChanges()) {
      if (user == null) {
        yield null;
        continue;
      }
      yield await _toAppUser(user);
    }
  }

  Future<AppUser?> currentUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _toAppUser(user);
  }

  Future<void> signIn(String email, String password) => _auth.signInWithEmailAndPassword(email: email, password: password);
  Future<void> signOut() => _auth.signOut();

  Future<void> signUpAdmin(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    final uid = cred.user!.uid;
    await _db.collection('users').doc(uid).set({
      'email': email,
      'role': 'dev_admin',
      'blocks': <String>[],
      'displayName': cred.user!.displayName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<AppUser> _toAppUser(fb.User user) async {
    // Bootstrap super admin (requested): these IDs/emails are always dev_admin
    const bootstrapAdminUids = {
      'IckVUW6Mg4Ue1XNcVWsxTidSiBY2',
    };
    const bootstrapAdminEmails = {
      'kafilcodes@gmail.com',
    };
    final bool isWhitelistedAdmin =
        bootstrapAdminUids.contains(user.uid) || (user.email != null && bootstrapAdminEmails.contains(user.email!.toLowerCase()));

    UserRole? role;
    List<String> blocks = const [];
    String? assignedVillage;
    String? displayName = user.displayName;

    // Read users doc (cache-first for speed), then fallback to server
    final userDocRef = _db.collection('users').doc(user.uid);
    Map<String, dynamic>? data;
    try {
      final cache = await userDocRef.get(const GetOptions(source: Source.cache));
      data = cache.data();
    } catch (_) {}
  // Try server with a short timeout to avoid long stalls on web
    data ??= await userDocRef
        .get()
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => userDocRef.snapshots().firstWhere((_) => true),
        )
        .then((snap) => (snap).data())
        .catchError((_) => null);
    if (data != null) {
      role = UserRole.fromKey(data['role'] as String?);
      final v = data['blocks'];
      if (v is List) {
        blocks = v.whereType<String>().toList();
      }
      assignedVillage = data['assignedVillage'] as String?;
      displayName = (data['displayName'] as String?) ?? displayName;

      // Enforce dev_admin for whitelisted account (in-app only; avoid client writes under strict rules)
      if (isWhitelistedAdmin && role != UserRole.devAdmin) {
        role = UserRole.devAdmin;
      }
    } else {
      // Fast bootstrap without collection scan: whitelist => dev_admin else project_owner
      final assignedRoleKey = isWhitelistedAdmin ? 'dev_admin' : 'project_owner';
      role = UserRole.fromKey(assignedRoleKey);
    }

    return AppUser(
      uid: user.uid,
      email: user.email ?? '',
      role: role ?? UserRole.projectOwner,
      blocks: blocks,
      displayName: displayName,
      assignedVillage: assignedVillage,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(fb.FirebaseAuth.instance, FirebaseFirestore.instance);
});

final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.read(authRepositoryProvider).authStateChanges();
});
