import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Static fallback list (kept consistent with owner flow)
const _staticBlocks = ['Dhamtari', 'Kurud', 'Nagri', 'Magarlod'];

// Alias map (lowercased) to canonical display/ID used in project docs
const Map<String, String> _aliasToCanonicalLower = {
  'nagari': 'Nagri',
  'nagarí': 'Nagri',
  'dhamtari (town)': 'Dhamtari',
  'dhamtari town': 'Dhamtari',
};

// Proper-case alias variants per canonical to help whereIn match legacy docs
const Map<String, List<String>> _canonicalToAliases = {
  'Nagri': ['Nagari', 'Nagarí'],
  'Dhamtari': ['Dhamtari (town)', 'Dhamtari Town'],
};

/// Canonicalize user-facing block names to the IDs used in Firestore documents.
/// Handles common aliases like "Nagari" -> "Nagri" and "Dhamtari (town)" -> "Dhamtari".
String canonicalizeBlockId(String? input) {
  final raw = (input ?? '').trim();
  if (raw.isEmpty) return raw;
  final lower = raw.toLowerCase();
  if (_aliasToCanonicalLower.containsKey(lower)) return _aliasToCanonicalLower[lower]!;
  // Ensure case matches known list if possible
  for (final b in _staticBlocks) {
    if (b.toLowerCase() == lower) return b;
  }
  return raw; // fallback to original
}

/// Return the set of acceptable query keys for a given input block identifier.
/// Includes the canonical form and well-known aliases so legacy docs still match.
List<String> blockQueryKeys(String? input) {
  final keys = <String>{};
  final raw = (input ?? '').trim();
  if (raw.isEmpty) return const <String>[];
  // Always include the original
  keys.add(raw);
  final canonical = canonicalizeBlockId(raw);
  keys.add(canonical);
  // Include lowercase/uppercase variants to match legacy docs that used lowercase ids
  keys.add(canonical.toLowerCase());
  keys.add(canonical.toUpperCase());
  // If canonical is known, include reverse aliases that map to it
  final lowerCanonical = canonical.toLowerCase();
  for (final entry in _aliasToCanonicalLower.entries) {
    if (entry.value.toLowerCase() == lowerCanonical) {
      // Add the alias in preferred display/casing if we know it, else as-is
      final aliasLower = entry.key;
      // Try to match static blocks casing where possible
      final matchStatic = _staticBlocks.firstWhere(
        (b) => b.toLowerCase() == aliasLower,
        orElse: () => aliasLower,
      );
      keys.add(matchStatic);
      // Also include lowercase to catch fully-lowercased docs
      keys.add(matchStatic.toLowerCase());
      // And uppercase just in case
      keys.add(matchStatic.toUpperCase());
    }
  }
  // Add proper-case alias variants from canonical mapping
  final proper = _canonicalToAliases[canonical];
  if (proper != null) {
    keys.addAll(proper);
    for (final p in proper) {
      keys.add(p.toLowerCase());
      keys.add(p.toUpperCase());
    }
  }
  return keys.toList();
}

// Try to read blocks from a config doc or a dedicated collection.
final _dynamicBlocksProvider = FutureProvider<List<String>>((ref) async {
  try {
    final db = FirebaseFirestore.instance;
    // Option A: config/app doc has an array field 'blocks'
    final cfg = await db.collection('config').doc('app').get();
    final arr = ((cfg.data()?['blocks'] as List?) ?? const []).whereType<String>().toList();
    if (arr.isNotEmpty) return arr;
    // Option B: collection 'blocks' with docs of { id/name }
    final snap = await db.collection('blocks').get();
    final viaCol = snap.docs.map((d) => (d.data()['id'] as String?) ?? (d.data()['name'] as String?) ?? d.id).whereType<String>().toList();
    if (viaCol.isNotEmpty) return viaCol;
  } catch (_) {
    // ignore errors and fallback to static
  }
  return _staticBlocks;
});

// Synchronous consumer-friendly provider with dynamic-first, static fallback
final blocksListProvider = Provider<List<String>>((ref) {
  final dynamicVal = ref.watch(_dynamicBlocksProvider).maybeWhen(data: (v) => v, orElse: () => null);
  return dynamicVal ?? _staticBlocks;
});
