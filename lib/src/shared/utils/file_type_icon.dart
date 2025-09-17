import 'package:flutter/cupertino.dart';

class FileTypeIconData {
  final IconData icon;
  final Color color;
  const FileTypeIconData(this.icon, this.color);
}

FileTypeIconData fileTypeIcon(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return const FileTypeIconData(CupertinoIcons.doc_richtext, Color(0xFFE55353));
  if (n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') || n.endsWith('.heic') || n.endsWith('.heif') || n.endsWith('.webp')) {
    return const FileTypeIconData(CupertinoIcons.photo_on_rectangle, Color(0xFF5148FB));
  }
  if (n.endsWith('.xls') || n.endsWith('.xlsx') || n.endsWith('.csv')) return const FileTypeIconData(CupertinoIcons.table, Color(0xFF5148FB));
  if (n.endsWith('.doc') || n.endsWith('.docx')) return const FileTypeIconData(CupertinoIcons.doc_text, Color(0xFF0EA5E9));
  if (n.endsWith('.zip') || n.endsWith('.tar') || n.endsWith('.gz')) return const FileTypeIconData(CupertinoIcons.archivebox, Color(0xFF9A9A9A));
  return const FileTypeIconData(CupertinoIcons.paperclip, Color(0xFF9A9A9A));
}
