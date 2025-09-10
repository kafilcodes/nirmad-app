import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mime/mime.dart' as mime;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class FileOpenHelper {
  /// Save bytes with a fileName and open using OS 'open with' picker where available.
  /// - On Web: throws (caller should open URL directly).
  /// - On Android: saves to public Downloads when possible, else app cache.
  /// - On iOS/Mac/Windows/Linux: saves to temp/cache and opens.
  static Future<String> saveAndOpen({required List<int> bytes, required String fileName}) async {
    if (kIsWeb) {
      throw UnsupportedError('saveAndOpen is not supported on Web.');
    }
    final contentType = mime.lookupMimeType(fileName) ?? 'application/octet-stream';
    final path = await _save(bytes: bytes, fileName: fileName);
    // On Android, use OpenFilex to trigger chooser based on MIME
    final res = await OpenFilex.open(path, type: contentType);
    if (res.type != ResultType.done) {
      // Best-effort: some devices require no explicit type
      await OpenFilex.open(path);
    }
    return path;
  }

  static Future<String> _save({required List<int> bytes, required String fileName}) async {
    // Try Downloads on Android; otherwise, cache dir
    Directory dir;
    try {
      if (Platform.isAndroid) {
        // path_provider exposes getDownloadsDirectory on Android (API 29+ via SAF). Fallback to external storage dir or app cache.
        dir = (await getDownloadsDirectory()) ?? await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      } else {
        dir = await getTemporaryDirectory();
      }
    } catch (_) {
      dir = await getTemporaryDirectory();
    }
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
    return file.path;
  }
}
