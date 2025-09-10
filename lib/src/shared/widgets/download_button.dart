import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/file_open_helper.dart';

typedef UrlResolver = Future<String> Function();

class DownloadButton extends StatefulWidget {
  const DownloadButton({super.key, required this.resolveUrl, required this.fileName, this.iconOnly = false});
  final UrlResolver resolveUrl;
  final String fileName;
  // When true, renders an icon-only button instead of a text button
  final bool iconOnly;

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  double? _progress; // 0..1
  String? _error;
  bool _downloading = false;

  Future<void> _start() async {
    setState(() {
      _error = null;
      _progress = null;
      _downloading = true;
    });
    try {
      final url = await widget.resolveUrl();
      if (kIsWeb) {
        final uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        setState(() => _downloading = false);
        return;
      }
      final dio = Dio();
      final bytes = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes, followRedirects: true, receiveTimeout: const Duration(minutes: 2)),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            setState(() => _progress = received / total);
          }
        },
      ).then((r) => r.data ?? const <int>[]);
      if (!mounted) return;
      setState(() => _downloading = false);
      // Save to Downloads (Android) or temp and open with chooser
  await FileOpenHelper.saveAndOpen(bytes: bytes, fileName: widget.fileName);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_downloading) {
      if (widget.iconOnly) {
        return const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
      }
      return SizedBox(
        width: 120,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: LinearProgressIndicator(value: _progress),
            ),
            const SizedBox(width: 8),
            Text(_progress == null ? '...' : '${(_progress! * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
    }
    if (_error != null) {
      if (widget.iconOnly) {
        return IconButton(
          tooltip: 'Retry',
          onPressed: _start,
          icon: const Icon(Icons.refresh),
        );
      }
      return TextButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      );
    }
    if (widget.iconOnly) {
      return IconButton(
        tooltip: 'Download',
        onPressed: _start,
        icon: const Icon(Icons.download),
      );
    }
    return FilledButton.tonal(onPressed: _start, child: const Text('Download'));
  }
}
