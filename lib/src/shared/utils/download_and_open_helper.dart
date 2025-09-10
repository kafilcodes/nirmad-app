import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'file_open_helper.dart';

class DownloadAndOpenHelper {
  static Future<void> downloadAndOpen({
    required String url,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    final dio = Dio();
    final response = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 2),
      ),
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );
    final bytes = response.data ?? const <int>[];
    await FileOpenHelper.saveAndOpen(bytes: bytes, fileName: fileName);
  }
}
