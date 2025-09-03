import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

class DraftMediaItem {
  final String id;
  final String name;
  final String category; // photo, doc, video, sanction_*, work_*
  final String contentType;
  final int size;
  final Uint8List bytes;
  final DateTime createdAt;
  DraftMediaItem({
    required this.id,
    required this.name,
    required this.category,
    required this.contentType,
    required this.size,
    required this.bytes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'contentType': contentType,
        'size': size,
        'bytes': bytes,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };
  static DraftMediaItem fromMap(Map<dynamic, dynamic> m) => DraftMediaItem(
        id: m['id'] as String,
        name: m['name'] as String,
        category: m['category'] as String,
        contentType: m['contentType'] as String,
        size: m['size'] as int,
        bytes: (m['bytes'] as Uint8List),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      );
}

class DraftMediaStore {
  static const _boxName = 'draft_media';
  Box<dynamic>? _box;

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(0)) {
      // no custom adapters, just ensure Hive is ready
    }
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.initFlutter();
      _box = await Hive.openBox(_boxName);
    } else {
      _box = Hive.box(_boxName);
    }
  }

  bool get ready => _box != null && _box!.isOpen;

  Future<String> addFromXFile(XFile x, {required String category, String? overrideContentType, int? maxBytes}) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}_${x.name}';
    final bytes = await x.readAsBytes();
    if (maxBytes != null && bytes.length > maxBytes) {
      throw Exception('File too large');
    }
    final ct = overrideContentType ?? _inferContentType(x.name);
    final item = DraftMediaItem(
      id: id,
      name: x.name,
      category: category,
      contentType: ct,
      size: bytes.length,
      bytes: bytes,
      createdAt: DateTime.now(),
    );
    await _box!.put(id, item.toMap());
    return id;
  }

  // Add from PlatformFile (file_picker). Works on Web (uses bytes) and Mobile (delegates to XFile).
  Future<String> addFromPlatformFile(
    PlatformFile f, {
    required String category,
    String? overrideContentType,
    int? maxBytes,
  }) async {
    if (kIsWeb) {
      final bytes = f.bytes;
      if (bytes == null) {
        throw Exception('No bytes available from picker on Web. Enable withData: true when picking.');
      }
      if (maxBytes != null && bytes.length > maxBytes) {
        throw Exception('File too large');
      }
      final ct = overrideContentType ?? _inferContentType(f.name);
      final id = '${DateTime.now().microsecondsSinceEpoch}_${f.name}';
      final item = DraftMediaItem(
        id: id,
        name: f.name,
        category: category,
        contentType: ct,
        size: bytes.length,
        bytes: bytes,
        createdAt: DateTime.now(),
      );
      await _box!.put(id, item.toMap());
      return id;
    } else {
      // On mobile/desktop, prefer XFile from path for memory efficiency
      final path = f.path;
      if (path == null) {
        // Fallback to bytes if path is not available
        final bytes = f.bytes;
        if (bytes == null) {
          throw Exception('Picker returned neither path nor bytes');
        }
        if (maxBytes != null && bytes.length > maxBytes) {
          throw Exception('File too large');
        }
        final ct = overrideContentType ?? _inferContentType(f.name);
        final id = '${DateTime.now().microsecondsSinceEpoch}_${f.name}';
        final item = DraftMediaItem(
          id: id,
          name: f.name,
          category: category,
          contentType: ct,
          size: bytes.length,
          bytes: bytes,
          createdAt: DateTime.now(),
        );
        await _box!.put(id, item.toMap());
        return id;
      }
      return addFromXFile(XFile(path), category: category, overrideContentType: overrideContentType, maxBytes: maxBytes);
    }
  }

  DraftMediaItem? get(String id) {
    final m = _box!.get(id);
    if (m == null) return null;
    return DraftMediaItem.fromMap(m as Map);
  }

  Future<void> remove(String id) async => _box!.delete(id);
  Future<void> clear() async => _box!.clear();

  // List all media (optionally by category)
  List<DraftMediaItem> list({String? category}) {
    if (_box == null) return const [];
    final all = _box!.values
        .whereType<Map>()
        .map((m) => DraftMediaItem.fromMap(m))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (category == null) return all;
    return all.where((e) => e.category == category).toList();
  }

  // Remove all by category (used after successful save)
  Future<void> removeByCategory(String category) async {
    if (_box == null) return;
    final keysToDelete = <dynamic>[];
    for (final entry in _box!.toMap().entries) {
      final m = entry.value;
      if (m is Map && m['category'] == category) keysToDelete.add(entry.key);
    }
    if (keysToDelete.isNotEmpty) {
      await _box!.deleteAll(keysToDelete);
    }
  }

  static String _inferContentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }
}

final draftMediaStoreProvider = Provider<DraftMediaStore>((ref) {
  final s = DraftMediaStore();
  // lazy init; caller must await init()
  return s;
});
