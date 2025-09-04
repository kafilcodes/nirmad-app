import 'dart:collection';

class MemoryCache<V> {
  final int maxEntries;
  final Duration ttl;

  final _values = LinkedHashMap<String, _Entry<V>>();

  MemoryCache({this.maxEntries = 200, this.ttl = const Duration(minutes: 5)});

  V? get(String key) {
    final e = _values[key];
    if (e == null) return null;
    if (DateTime.now().isAfter(e.expiresAt)) {
      _values.remove(key);
      return null;
    }
    // LRU: reinsert at end
    _values.remove(key);
    _values[key] = e;
    return e.value;
  }

  void set(String key, V value, {Duration? customTtl}) {
    if (_values.length >= maxEntries) {
      _values.remove(_values.keys.first);
    }
    _values[key] = _Entry(value, DateTime.now().add(customTtl ?? ttl));
  }

  void remove(String key) => _values.remove(key);
  void clear() => _values.clear();
}

class _Entry<V> {
  final V value;
  final DateTime expiresAt;
  _Entry(this.value, this.expiresAt);
}
