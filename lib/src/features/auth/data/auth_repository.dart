import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/auth/session_service.dart';
import '../../../services/functions_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../core/prefs/shared_prefs.dart';
import '../../../shared/data/blocks_provider.dart';

import '../domain/app_user.dart';

class AuthRepository {
  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final SharedPreferences _prefs;

  late final SessionService _session = SessionService(_auth, _db);
  AuthRepository(this._auth, this._db, this._prefs);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionWatchSub;
  String? _currentWatchedSessionId;

  void _startSessionWatch(String sessionId) {
    final u = _auth.currentUser;
    if (u == null) return;
    // Cancel any existing watcher if sessionId changed
    if (_currentWatchedSessionId == sessionId && _sessionWatchSub != null) return;
    _sessionWatchSub?.cancel();
    _currentWatchedSessionId = sessionId;
    final ref = _db.collection('users').doc(u.uid).collection('sessions').doc('current');
    _sessionWatchSub = ref.snapshots().listen((snap) async {
      // Production resilience: avoid spurious sign-outs on refresh/offline/errors.
      // Only sign out on explicit mismatch where an active sessionId exists and differs.
      final data = snap.data();
      final activeId = data == null ? null : (data['sessionId'] as String?);
      if (activeId != null && activeId.isNotEmpty && activeId != _currentWatchedSessionId) {
        await signOut();
      }
      // When activeId is null or doc missing, do nothing; a later update will enforce if needed.
    }, onError: (e, st) async {
      // Do not sign out on transient listener errors; keep the watcher alive.
      // Intentionally no-op to prevent logout flicker on web refresh.
    });
  }

  Stream<AppUser?> authStateChanges() async* {
    await for (final user in _auth.authStateChanges()) {
      if (user == null) {
        // Clear cache
        await _prefs.remove('auth_cache');
        // Clear any lingering session doc optimistically
        try {
          final id = _prefs.getString('device_session_id');
          if (id != null && id.isNotEmpty) {
            await _session.clearSessionIfMatches(id);
          }
        } catch (_) {}
        // Stop watcher
        try { await _sessionWatchSub?.cancel(); } catch (_) {}
        _sessionWatchSub = null;
        _currentWatchedSessionId = null;
        yield null;
        continue;
      }
      // Enforce single-device + 6-month policy: if different device, sign out
      final deviceSessionId = await _ensureDeviceSessionId();
      try {
        final allowed = await _session.canUseCurrentDevice(deviceSessionId);
        if (!allowed) {
          await _auth.signOut();
          await _prefs.remove('auth_cache');
          yield null;
          continue;
        }
      } catch (_) {}
      final app = await _toAppUser(user);
      // Cache last user for faster cold start redirects
      try {
        _prefs.setString('auth_cache', jsonEncode(app.toJson()));
      } catch (_) {}
      // Register/update current session (sets 6-month hint expiry server-side)
      try { await _session.registerSession(deviceSessionId); } catch (_) {}
      // Begin real-time enforcement: if another device overwrites session, this device logs out immediately
      _startSessionWatch(deviceSessionId);
      yield app;
    }
  }

  Future<AppUser?> currentUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _toAppUser(user);
  }

  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      // Enforce single-device strictly: check before registering and bail out if mismatch
      try {
        final id = await _ensureDeviceSessionId();
        final ok = await _session.canUseCurrentDevice(id);
        if (!ok) {
          // Revert sign-in and surface an error
          await _auth.signOut();
          throw StateError('This account is already active on another device. Please log out there first.');
        }
        await _session.registerSession(id);
      } catch (e) {
        rethrow;
      }
    } catch (e) {
      // ignore: avoid_print
      print('AuthRepository.signIn error: $e');
      rethrow;
    }
  }
  Future<void> sendPasswordResetEmail(String email) => _auth.sendPasswordResetEmail(email: email);
  Future<void> signOut() async {
  try {
    final id = _prefs.getString('device_session_id');
    if (id != null && id.isNotEmpty) {
      await _session.clearSessionIfMatches(id);
    }
  } catch (_) {}
  try { await _sessionWatchSub?.cancel(); } catch (_) {}
  _sessionWatchSub = null;
  _currentWatchedSessionId = null;
  await _auth.signOut();
    await _prefs.remove('auth_cache');
    // Clear per-user local drafts and caches
    try { await _prefs.remove('profile_draft'); } catch (_) {}
    try { await _prefs.remove('project_creation_draft'); } catch (_) {}
  // Riverpod provider invalidations (filters/search) executed via container if available
  // This repository does not own a ref, so UI layers should listen to authStateProvider null and clear UI state.
  }

  /// Force takeover the active session on another device after user confirmation.
  /// This signs in and immediately registers this device's sessionId, overwriting
  /// the previous session. Any active device watcher will sign out in real-time.
  Future<void> forceSignInTakeover(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    final id = await _ensureDeviceSessionId();
    await _session.registerSession(id);
    _startSessionWatch(id);
    // Best-effort: revoke tokens so previous device refresh tokens are invalidated immediately
    try {
      final region = dotenv.maybeGet('FIREBASE_FUNCTIONS_REGION') ?? 'us-central1';
      final fns = FirebaseFunctions.instanceFor(region: region);
      await FunctionsService(fns).revokeUserTokens();
    } catch (_) {}
  }

  Future<void> signUpAdmin(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    final uid = cred.user!.uid;
    await _db.collection('users').doc(uid).set({
      'email': email,
      'role': 'dev_admin',
  // Use single blockId model; dev_admin has access to all, so null
  'blockId': null,
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
  String? blockId;
  List<String> blocks = const [];
    String? assignedVillage;
    String? displayName = user.displayName;

    // Read users doc: try server quickly, then fallback to cache to avoid long stalls
    final userDocRef = _db.collection('users').doc(user.uid);
    Map<String, dynamic>? data;
    try {
      final server = await userDocRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 2));
      data = server.data();
    } catch (_) {
      try {
        final cache = await userDocRef.get(const GetOptions(source: Source.cache));
        data = cache.data();
      } catch (_) {}
    }
    if (data != null) {
      role = UserRole.fromKey(data['role'] as String?);
      // Prefer new single blockId; keep array and legacy keys for back-compat
      blockId = (data['blockId'] as String?)?.trim();
      // Legacy lowercase keys sometimes used in older user docs
      blockId ??= (data['blockid'] as String?)?.trim();
      blockId ??= (data['block'] as String?)?.trim();
      final v = data['blocks'];
      if (v is List) {
        blocks = v.whereType<String>().toList();
        // Fill blockId if missing
        blockId ??= blocks.isNotEmpty ? blocks.first : null;
      }
      // Canonicalize common aliases/casing (e.g., 'dhamtari' -> 'Dhamtari')
  if (blockId != null && blockId.isNotEmpty) {
        blockId = canonicalizeBlockId(blockId);
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
  blockId: blockId,
  blocks: blocks,
      displayName: displayName,
      assignedVillage: assignedVillage,
    );
  }

  // Persist a stable per-device session id in SharedPreferences
  Future<String> _ensureDeviceSessionId() async {
    const key = 'device_session_id';
    final existing = _prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _randomId();
    await _prefs.setString(key, id);
    return id;
  }

  String _randomId() {
    // Simple 22-char url-safe id
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final rnd = DateTime.now().microsecondsSinceEpoch ^ _prefs.hashCode;
    var x = rnd;
    final codeUnits = <int>[];
    for (int i = 0; i < 22; i++) {
      x = 1664525 * x + 1013904223; // LCG
      codeUnits.add(alphabet.codeUnitAt(x & 63));
    }
    return String.fromCharCodes(codeUnits);
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return AuthRepository(fb.FirebaseAuth.instance, FirebaseFirestore.instance, prefs);
});

// A fast boot cache for last known AppUser to accelerate splash->redirect.
// Returns null if no cache. This doesn't perform any auth; it’s only a hint for UI.
final cachedAppUserProvider = Provider<AppUser?>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  final raw = prefs.getString('auth_cache');
  if (raw == null || raw.isEmpty) return null;
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return AppUser.fromJson(map);
  } catch (_) {
    return null;
  }
});

// A derived fast redirect hint from the cached user.
final cachedRedirectPathProvider = Provider<String?>((ref) {
  final u = ref.watch(cachedAppUserProvider);
  if (u == null) return null;
  switch (u.role) {
    case UserRole.devAdmin:
    case UserRole.superNodal:
    case UserRole.subNodal:
      return '/dashboard';
    case UserRole.projectOwner:
      return '/owner';
  }
});

final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.read(authRepositoryProvider).authStateChanges();
});

// Realtime current user's Firestore doc snapshot (null stream when signed out)
final currentUserDocProvider = StreamProvider<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
  final user = fb.FirebaseAuth.instance.currentUser;
  if (user == null) return const Stream.empty();
  return FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
});

/// A unified, single source of truth for the current user's profile for UI use.
/// Combines FirebaseAuth user fields with Firestore `users/{uid}` document data.
class CurrentUserProfile {
  final String uid;
  final String email;
  final String displayName; // best-effort, may be empty
  final Map<String, dynamic> data; // raw Firestore user doc data
  final UserRole role;
  const CurrentUserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.data,
    required this.role,
  });
}

/// Unified profile stream combining authStateProvider (AppUser for role) and user doc.
final currentUserProfileProvider = Provider<CurrentUserProfile?>((ref) {
  final appUser = ref.watch(authStateProvider).value;
  final fbUser = fb.FirebaseAuth.instance.currentUser;
  if (appUser == null || fbUser == null) return null;
  final userDocSnap = ref.watch(currentUserDocProvider).value;
  final data = userDocSnap?.data() ?? const <String, dynamic>{};
  final displayName = ((data['displayName'] as String?) ?? (fbUser.displayName ?? '')).trim();
  return CurrentUserProfile(
    uid: appUser.uid,
    email: appUser.email,
    displayName: displayName,
    data: data,
    role: appUser.role,
  );
});
