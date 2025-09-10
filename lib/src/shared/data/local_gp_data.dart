import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle, AssetBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GPRecord {
  final String name;
  final List<String> grams;
  final String sarpanch;
  final String secretary;
  const GPRecord({
    required this.name,
    required this.grams,
    required this.sarpanch,
    required this.secretary,
  });

  factory GPRecord.fromJson(Map<String, dynamic> j) => GPRecord(
        name: (j['gram_panchayat'] as String?)?.trim() ?? '',
        grams: ((j['grams'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        sarpanch: (j['sarpanch'] as String?)?.trim() ?? '',
        secretary: (j['secretary'] as String?)?.trim() ?? '',
      );
}

/// Loads Gram Panchayat dataset from bundled asset `local_data.json`.
final gramPanchayatDataProvider = FutureProvider<List<GPRecord>>((ref) async {
  Future<String> _loadAsset(AssetBundle bundle) async {
    // Try declared root asset first
    try {
      return await bundle.loadString('local_data.json');
    } catch (_) {
      // Fallback to common asset folder path in case of mis-declaration
      return await bundle.loadString('assets/local_data.json');
    }
  }

  try {
    final raw = await _loadAsset(rootBundle);
    final arr = jsonDecode(raw);
    if (arr is! List) return const <GPRecord>[];
    final list = arr
        .whereType<Map<String, dynamic>>()
        .map(GPRecord.fromJson)
        .where((r) => r.name.isNotEmpty)
        .toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  } catch (_) {
    return const <GPRecord>[];
  }
});

/// Convenience provider of just the GP names for dropdowns.
final gramPanchayatNamesProvider = Provider<List<String>>((ref) {
  final async = ref.watch(gramPanchayatDataProvider);
  return async.maybeWhen(
    data: (items) => items.map((e) => e.name).toList(),
    orElse: () => const <String>[],
  );
});

GPRecord? findGPByName(List<GPRecord> items, String? name) {
  final q = (name ?? '').trim().toLowerCase();
  if (q.isEmpty) return null;
  try {
    return items.firstWhere((e) => e.name.trim().toLowerCase() == q);
  } catch (_) {
    return null;
  }
}
