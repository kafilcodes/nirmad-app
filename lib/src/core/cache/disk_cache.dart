import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight disk cache backed by SharedPreferences with optional TTL.
/// Stores values as JSON strings with metadata { data, ts, ttlMs }.
class DiskCache {
  final SharedPreferences _prefs;
  DiskCache(this._prefs);

  @visibleForTesting
  static String keyFor(String key) => 'disk_cache:$key';

  Future<void> setJson(String key, Object value, {Duration? ttl}) async {
    final wrapper = {
      'data': value,
      'ts': DateTime.now().millisecondsSinceEpoch,
      if (ttl != null) 'ttlMs': ttl.inMilliseconds,
    };
    await _prefs.setString(keyFor(key), jsonEncode(wrapper));
  }

  /// Returns the decoded JSON object if present and not expired, else null.
  T? getJson<T>(String key, T Function(Object? v) decode) {
    final raw = _prefs.getString(keyFor(key));
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ts = (map['ts'] as num?)?.toInt();
      final ttlMs = (map['ttlMs'] as num?)?.toInt();
      if (ts != null && ttlMs != null) {
        final expired = DateTime.now().millisecondsSinceEpoch > ts + ttlMs;
        if (expired) return null;
      }
      return decode(map['data']);
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) => _prefs.remove(keyFor(key));
}
