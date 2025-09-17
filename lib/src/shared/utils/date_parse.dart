import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:intl/intl.dart';

/// Robust, centralized date parsing.
///
/// Accepts:
/// - Firestore Timestamp
/// - DateTime
/// - Map with epoch seconds (`seconds` or `_seconds`)
/// - int/double epoch (seconds or millis; auto-detected)
/// - String in multiple formats (Y-M-D, D/M/Y, M/D/Y, `12 Jan 2025`, etc.)
/// Returns local DateTime or null on failure. Never throws.
DateTime? parseAnyDate(dynamic v) {
  try {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    if (v is Map) {
      final secs = v['seconds'] ?? v['_seconds'];
      if (secs is num) {
        final ms = _toMillis(secs);
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
      }
    }
    if (v is num) {
      final ms = _toMillis(v);
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return null;
      // Heuristic: if slash-delimited, decide D/M/Y vs M/D/Y by value > 12
      if (s.contains('/')) {
        final parts = s.split('/');
        if (parts.length == 3) {
          final a = int.tryParse(parts[0]);
          final b = int.tryParse(parts[1]);
          final c = int.tryParse(parts[2]);
          if (a != null && b != null && c != null) {
            final dmy = (a > 12) ? DateFormat('dd/MM/yyyy') : DateFormat('MM/dd/yyyy');
            try { return dmy.parseStrict(s); } catch (_) {}
          }
        }
      }
      // 3) Try common formats
      for (final f in const [
        'yyyy-MM-dd', 'dd/MM/yyyy', 'MM/dd/yyyy', 'dd.MM.yyyy', 'd MMM yyyy', 'd MMMM yyyy'
      ]) {
        try { return DateFormat(f).parseStrict(s); } catch (_) {}
      }
      // 4) Last resort
      try { return DateTime.parse(s); } catch (_) {}
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Format DateTime as `YYYY-MM-DD` (zero-padded).
String fmtYmd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}

int _toMillis(num epoch) {
  // Heuristic: seconds if < 1e11, else already millis
  if (epoch.abs() < 100000000000) {
    // seconds
    return (epoch.toDouble() * 1000).round();
  }
  return epoch.round();
}
