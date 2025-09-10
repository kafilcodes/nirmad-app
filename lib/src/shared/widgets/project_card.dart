import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import '../../features/projects/domain/project.dart';

class ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onOpen;
  const ProjectCard({super.key, required this.project, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        cs.primary.withValues(alpha: 0.20),
        cs.primaryContainer.withValues(alpha: 0.60),
      ],
    );
    return InkWell(
      onTap: onOpen,
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Ink(
          decoration: BoxDecoration(gradient: gradient),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.building_2_fill, color: cs.onPrimaryContainer, size: 38),
                const SizedBox(height: 10),
                Text(
                  project.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('#${project.id}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                _buildChips(context),
                const SizedBox(height: 8),
                // Centered location row (moved from footer)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.location_solid, size: 14, color: Colors.white70),
                    const SizedBox(width: 4),
                    Flexible(child: Text(project.blockId, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChips(BuildContext context) {
    final statusLabel = project.status.name;
    Color statusColor; IconData statusIcon;
    switch (project.status) {
      case ProjectStatus.completed:
        statusColor = Colors.green; statusIcon = CupertinoIcons.check_mark_circled_solid; break;
      case ProjectStatus.cancelled:
        statusColor = Colors.grey; statusIcon = CupertinoIcons.xmark_circle_fill; break;
      case ProjectStatus.in_progress:
        statusColor = Colors.amber; statusIcon = CupertinoIcons.clock_solid; break;
    }
    final deadlineVal = project.financials['deadline'];
    final isLate = _isLate(deadlineVal);
  return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
    // Show single status chip only (remove duplicate color/status elsewhere)
      StatusChip(label: statusLabel, inverted: true, color: statusColor, icon: statusIcon),
  if (project.phase > 0) StatusChip(label: 'Financial Phase ${project.phase}', inverted: true, color: Colors.white70, icon: CupertinoIcons.number),
        if (deadlineVal != null)
          StatusChip(label: 'Due ${_fmtDeadline(deadlineVal)}', inverted: true, color: isLate ? Colors.redAccent : Colors.white70, icon: CupertinoIcons.calendar),
      ],
    );
  }
}

// FooterInfo removed to avoid duplicate status; status is already shown in chips and list items.

class StatusChip extends StatelessWidget {
  final String label;
  final bool inverted;
  final Color? color;
  final IconData? icon;
  const StatusChip({super.key, required this.label, this.inverted = false, this.color, this.icon});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = color ?? (inverted ? Colors.white : cs.primary);
    final bg = inverted ? Colors.white.withValues(alpha: 0.16) : base.withValues(alpha: 0.12);
    final border = inverted ? Colors.white24 : base.withValues(alpha: 0.24);
    final fg = inverted ? Colors.white : base;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

String _fmtDeadline(dynamic v) {
  if (v == null) return '';
  try {
    if (v is Timestamp) {
      final d = v.toDate();
      return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    }
    if (v is DateTime) {
      return '${v.year}-${v.month.toString().padLeft(2,'0')}-${v.day.toString().padLeft(2,'0')}';
    }
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    }
    if (v is Map && v['seconds'] != null) {
      final secs = (v['seconds'] as num).toInt();
      final d = DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true).toLocal();
      return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    }
  } catch (_) {}
  return '';
}

bool _isLate(dynamic v) {
  try {
    if (v == null) {
      return false;
    }
    DateTime? d;
    if (v is Timestamp) {
      d = v.toDate();
    } else if (v is DateTime) {
      d = v;
    } else if (v is String) {
      d = DateTime.tryParse(v);
    }
    else if (v is Map && v['seconds'] != null) {
      final secs = (v['seconds'] as num).toInt();
      d = DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true).toLocal();
    }
    if (d == null) {
      return false;
    }
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return d.isBefore(startOfToday);
  } catch (_) { return false; }
}
