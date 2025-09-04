import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async' show scheduleMicrotask;

import '../../core/cache/memory_cache.dart';
import 'query_spec.dart';

typedef FromDoc<T> = T Function(DocumentSnapshot<Map<String, dynamic>> doc);

class FirestoreDao {
  final FirebaseFirestore _db;
  final MemoryCache<Object> _cache;
  final Map<String, Future<Object?>> _inflight = {};

  FirestoreDao(this._db, {MemoryCache<Object>? cache}) : _cache = cache ?? MemoryCache(maxEntries: 500, ttl: const Duration(minutes: 3));

  // Get a single document with cache and stale-while-revalidate.
  Future<T?> getDoc<T>({required String path, required FromDoc<T> fromDoc, Duration? ttl}) async {
    final key = 'doc:$path';
    final cached = _cache.get(key) as T?;
    if (cached != null) {
      // Revalidate in background
      _revalidate(() async {
        final snap = await _db.doc(path).get();
  if (snap.exists) _cache.set(key, fromDoc(snap) as Object, customTtl: ttl);
      });
      return cached;
    }
    return _coalesce(key, () async {
      final snap = await _db.doc(path).get();
      if (!snap.exists) return null;
      final v = fromDoc(snap);
  _cache.set(key, v as Object, customTtl: ttl);
      return v;
    }) as Future<T?>;
  }

  // Fetch a list result with cache; optional listen for realtime when needed.
  Future<List<T>> getList<T>({required QuerySpec spec, required Query<Map<String, dynamic>> Function(CollectionReference<Map<String, dynamic>> col) build,
    required FromDoc<T> fromDoc, Duration? ttl}) async {
    final key = 'list:${spec.key}';
    final cached = _cache.get(key) as List<T>?;
    if (cached != null) {
      _revalidate(() async {
        final q = build(_db.collection(spec.path));
        final s = await q.get();
        final v = s.docs.map(fromDoc).toList();
        _cache.set(key, v, customTtl: ttl);
      });
      return cached;
    }
    return _coalesce(key, () async {
      final q = build(_db.collection(spec.path));
      final s = await q.get();
      final v = s.docs.map(fromDoc).toList();
      _cache.set(key, v, customTtl: ttl);
      return v;
    }) as Future<List<T>>;
  }

  Future<void> create(String path, Map<String, dynamic> data) => _db.doc(path).set(data);
  Future<void> update(String path, Map<String, dynamic> data) => _db.doc(path).update(data);
  Future<void> delete(String path) => _db.doc(path).delete();

  Future<T> transaction<T>(Future<T> Function(Transaction tx) action) => _db.runTransaction(action);

  Future<void> batch(List<void Function(WriteBatch b)> ops) async {
    final b = _db.batch();
    for (final f in ops) { f(b); }
    await b.commit();
  }

  void invalidate(String keyPrefix) {
    // Naive invalidation for now: clear all
    _cache.clear();
  }

  void _revalidate(Future<void> Function() task) {
    // Best-effort background refresh
    scheduleMicrotask(() async { try { await task(); } catch (_) {} });
  }

  Future<Object?> _coalesce(String key, Future<Object?> Function() task) {
    final inFlight = _inflight[key];
    if (inFlight != null) return inFlight;
    final fut = task();
    _inflight[key] = fut;
    return fut.whenComplete(() => _inflight.remove(key));
  }
}
