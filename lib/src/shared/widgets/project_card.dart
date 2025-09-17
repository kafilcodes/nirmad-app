import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../features/projects/domain/project.dart';
import '../utils/date_parse.dart';

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
        cs.primary.withValues(alpha: 0.55),
        cs.primary.withValues(alpha: 0.85),
      ],
    );
    return InkWell(
      onTap: onOpen,
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Ink(
          decoration: BoxDecoration(gradient: gradient),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.building_2_fill, color: cs.onPrimaryContainer, size: 34),
                const SizedBox(height: 8),
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
                const SizedBox(height: 6),
                // Location hierarchy (Block → GP → Gram)
                _LocationHierarchy(project: project),
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

class _LocationHierarchy extends StatelessWidget {
  final Project project;
  const _LocationHierarchy({required this.project});
  @override
  Widget build(BuildContext context) {
    final gp = project.preliminaryDescription.gramPanchayat?.trim();
    final gram = project.villageId.trim().isEmpty ? null : project.villageId.trim();
    final entries = <_LocPart>[
      _LocPart(icon: CupertinoIcons.location_solid, label: project.blockId),
      if (gp != null && gp.isNotEmpty) _LocPart(icon: CupertinoIcons.building_2_fill, label: gp),
      if (gram != null && gram.isNotEmpty) _LocPart(icon: CupertinoIcons.house_fill, label: gram),
    ];
    return LayoutBuilder(builder: (context, c) {
      final maxPer = c.maxWidth;
      return Wrap(
        spacing: 6,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: entries.map((e) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxPer / 1.2),
          child: _LocPill(icon: e.icon, label: e.label),
        )).toList(),
      );
    });
  }
}

class _LocPart { final IconData icon; final String label; const _LocPart({required this.icon, required this.label}); }

class _LocPill extends StatelessWidget {
  final IconData icon; final String label; const _LocPill({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: Colors.white),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
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
  final d = parseAnyDate(v);
  if (d == null) return '';
  return fmtYmd(d);
}

bool _isLate(dynamic v) {
  final d = parseAnyDate(v);
  if (d == null) return false;
  final today = DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  return d.isBefore(startOfToday);
}
