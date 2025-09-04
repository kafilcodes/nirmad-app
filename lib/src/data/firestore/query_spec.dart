class QuerySpec {
  final String path;
  final Map<String, Object?> filters;
  final int? limit;

  const QuerySpec({required this.path, this.filters = const {}, this.limit});

  String get key {
    final f = Map<String, Object?>.from(filters)
      ..removeWhere((k, v) => v == null);
    final sortedKeys = f.keys.toList()..sort();
    final parts = [path];
    for (final k in sortedKeys) {
      parts.add('$k=${f[k]}');
    }
    if (limit != null) parts.add('limit=$limit');
    return parts.join('|');
  }
}
