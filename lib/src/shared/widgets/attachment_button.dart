import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/download_service.dart';
import 'package:url_launcher/url_launcher.dart';

typedef AttachmentUrlResolver = Future<String> Function();

class AttachmentButton extends StatefulWidget {
  const AttachmentButton({super.key, required this.resolveUrl, required this.fileName});
  final AttachmentUrlResolver resolveUrl;
  final String fileName;
  @override
  State<AttachmentButton> createState() => _AttachmentButtonState();
}

class _AttachmentButtonState extends State<AttachmentButton> {
  bool _busy = false;
  double? _progress;

  Future<void> _open() async {
    setState(() { _busy = true; _progress = null; });
    try {
      final url = await widget.resolveUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (mounted) setState(() { _busy = false; });
  }

  Future<void> _downloadDirect() async {
    setState(() { _busy = true; _progress = null; });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await widget.resolveUrl();
      if (!mounted) return; // ensure context-safe usage below
      final svc = DownloadService();
      await svc.download(
        context,
        url,
        widget.fileName,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Download failed')));
      }
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_busy) {
      return SizedBox(
        width: 110,
        child: Row(children: [
          Expanded(child: LinearProgressIndicator(value: _progress)),
          const SizedBox(width: 6),
          Text(_progress == null ? '…' : '${(_progress! * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11)),
        ]),
      );
    }
    return Tooltip(
      message: 'Open (long-press to download)',
      child: GestureDetector(
        onLongPress: _downloadDirect,
        child: IconButton(
          tooltip: 'Open',
          onPressed: _open,
          icon: Icon(CupertinoIcons.arrow_up_right_square, color: cs.primary),
        ),
      ),
    );
  }
}
