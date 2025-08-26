import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class FunctionsService {
  final FirebaseFunctions _functions;
  FunctionsService(this._functions);

  Future<String> exportProjectZip(String projectId) async {
    final callable = _functions.httpsCallable('exportProjectZip');
    final res = await callable.call<String>({'projectId': projectId});
    return res.data;
  }

  Future<void> setUserClaims({required String email, required String role, List<String>? blocks}) async {
    final callable = _functions.httpsCallable('setUserClaims');
    await callable.call({
      'email': email,
      'role': role,
      if (blocks != null) 'blocks': blocks,
    });
  }

  Future<void> seedTestUsers({int owners = 5, int nodals = 2, String domain = 'example.com', List<String>? blockIds}) async {
    final callable = _functions.httpsCallable('seedTestUsers');
    await callable.call({
      'owners': owners,
      'nodals': nodals,
      'domain': domain,
      if (blockIds != null) 'blockIds': blockIds,
    });
  }

  Future<void> callBootstrapDevAdmin(String email, String password) async {
    final callable = _functions.httpsCallable('bootstrapDevAdmin');
    await callable.call({'email': email, 'password': password});
  }

  // Ensures the current signed-in user is promoted to dev_admin if whitelisted.
  // Expected callable: ensureDevAdminForWhitelisted
  Future<void> ensureDevAdminForWhitelisted() async {
    final callable = _functions.httpsCallable('ensureDevAdminForWhitelisted');
    await callable.call();
  }

  // Creates a Firebase Auth user with given email/password and role; optionally sets displayName.
  // Expected Cloud Function (callable): adminCreateUser
  // Payload: { email, password, role, displayName? }
  // Returns: { uid, email, role, displayName? }
  Future<Map<String, dynamic>> createAuthUser({
    required String email,
    required String password,
    required String role,
    String? displayName,
  }) async {
    final callable = _functions.httpsCallable('adminCreateUser');
    final res = await callable.call({
      'email': email,
      'password': password,
      'role': role,
      if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
    });
    final data = (res.data as Map).map((k, v) => MapEntry(k.toString(), v));
    return data;
  }

  // Bulk create auth users.
  // Expected callable: adminBulkCreateUsers
  // Payload: { users: [{ email, password, role, displayName? }, ...] }
  // Returns: { results: [{ email, uid, ok, error? }, ...] }
  Future<List<Map<String, dynamic>>> bulkCreateAuthUsers(List<Map<String, String>> users) async {
    final callable = _functions.httpsCallable('adminBulkCreateUsers');
    final res = await callable.call({'users': users});
    final list = (res.data is List) ? (res.data as List) : (res.data['results'] as List);
    return list.map<Map<String, dynamic>>((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v))).toList();
  }

  // Deletes a user from Firebase Auth and Firestore (and related data if backend supports).
  // Expected callable: adminDeleteUser
  // Payload: { uid }
  Future<void> adminDeleteUser({required String uid}) async {
    final callable = _functions.httpsCallable('adminDeleteUser');
    await callable.call({ 'uid': uid });
  }

  // Bulk delete users by uid.
  // Expected callable: adminBulkDeleteUsers
  // Payload: { uids: [uid1, uid2, ...] }
  // Returns: [{ uid, ok, error? }, ...]
  Future<List<Map<String, dynamic>>> adminBulkDeleteUsers(List<String> uids) async {
    final callable = _functions.httpsCallable('adminBulkDeleteUsers');
    final res = await callable.call({ 'uids': uids });
    final list = (res.data is List) ? (res.data as List) : (res.data['results'] as List);
    return list.map<Map<String, dynamic>>((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v))).toList();
  }
}

final functionsServiceProvider = Provider<FunctionsService>((ref) {
  final region = dotenv.maybeGet('FIREBASE_FUNCTIONS_REGION') ?? 'us-central1';
  final fns = FirebaseFunctions.instanceFor(region: region);
  final host = dotenv.maybeGet('FIREBASE_FUNCTIONS_EMULATOR_HOST');
  final portStr = dotenv.maybeGet('FIREBASE_FUNCTIONS_EMULATOR_PORT');
  if (host != null && portStr != null) {
    final port = int.tryParse(portStr);
    if (port != null) {
      // ignore: deprecated_member_use
      fns.useFunctionsEmulator(host, port);
    }
  }
  return FunctionsService(fns);
});
