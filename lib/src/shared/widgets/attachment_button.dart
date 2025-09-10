import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../utils/download_and_open_helper.dart';

typedef AttachmentUrlResolver = Future<String> Function();

class AttachmentButton extends StatefulWidget {
  const AttachmentButton({super.key, required this.resolveUrl, required this.fileName, this.showPreview = true});
  final AttachmentUrlResolver resolveUrl;
  final String fileName;
  final bool showPreview;

  @override
  State<AttachmentButton> createState() => _AttachmentButtonState();
}

class _AttachmentButtonState extends State<AttachmentButton> {
  bool _busy = false;
  double? _progress;

  bool _isImage(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') || n.endsWith('.heic') || n.endsWith('.heif') || n.endsWith('.webp');
  }

  Future<void> _preview(String url) async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Future<void> _open() async {
    setState(() { _busy = true; _progress = null; });
    try {
      final url = await widget.resolveUrl();
      await DownloadAndOpenHelper.downloadAndOpen(
        url: url,
        fileName: widget.fileName,
        onProgress: (p) => setState(() => _progress = p),
      );
    } catch (_) {
      // swallow errors; UX remains minimal
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isImage = _isImage(widget.fileName);
    if (_busy) {
      return SizedBox(
        width: 120,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(child: LinearProgressIndicator(value: _progress)),
            const SizedBox(width: 8),
            Text(_progress == null ? '...' : '${(_progress! * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    return Wrap(spacing: 4, children: [
  if (widget.showPreview && isImage)
        IconButton(
          tooltip: 'Preview',
          onPressed: () async {
            final url = await widget.resolveUrl();
            if (!mounted) return;
            await _preview(url);
          },
          icon: const Icon(CupertinoIcons.eye, color: Color(0xFFF6C445)),
        ),
      IconButton(
        tooltip: 'Open',
        onPressed: _open,
        icon: const Icon(CupertinoIcons.square_arrow_down, color: Color(0xFF2EB85C)),
      ),
    ]);
  }
}
