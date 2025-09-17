import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:tbib_downloader/tbib_downloader.dart';
import 'package:flutter/widgets.dart';
import 'package:downloadsfolder/downloadsfolder.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

class DownloadResult {
  final bool success;
  final String? path;
  final String? message;
  const DownloadResult({required this.success, this.path, this.message});
}

class DownloadService {
  static final DownloadService _i = DownloadService._();
  DownloadService._();
  factory DownloadService() => _i;

  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await TBIBDownloader().init();
    _initialized = true;
  }

  Future<DownloadResult> download(BuildContext context, String url, String fileName, {void Function(double progress)? onProgress}) async {
    try {
      if (kIsWeb) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return const DownloadResult(success: true, path: null);
      }
      await ensureInitialized();
      if (!context.mounted) {
        return const DownloadResult(success: false, message: 'Context not mounted');
      }
      // Use a safe subfolder name
      final safeDir = 'nirmad';
      final finalPath = await TBIBDownloader().downloadFile(
        context: context,
        url: url,
        fileName: fileName,
        directoryName: safeDir,
        onReceiveProgress: ({int? receivedBytes, int? totalBytes}) {
          if (receivedBytes != null && totalBytes != null && totalBytes > 0) {
            onProgress?.call(receivedBytes / totalBytes);
          }
        },
      );
      // Optionally copy into global Downloads folder too
      try {
        if (finalPath != null) {
          final file = File(finalPath);
          if (await file.exists()) {
            final copied = await copyFileIntoDownloadFolder(file.path, p.basename(file.path));
            if (copied == true) {
              // keep original path
            }
          }
        }
      } catch (_) {}
      return DownloadResult(success: true, path: finalPath);
    } catch (e) {
      return DownloadResult(success: false, message: e.toString());
    }
  }

  Future<void> view(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
