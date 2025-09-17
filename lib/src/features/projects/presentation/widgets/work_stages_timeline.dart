import 'package:flutter/material.dart';
import 'package:timelines_plus/timelines_plus.dart';
import '../../domain/project.dart';

/// Public reusable timeline widget for project work stages with start/end date panels.
class WorkStagesTimeline extends StatelessWidget {
  final WorkStage? current;
  final DateTime? start;
  final DateTime? end;
  const WorkStagesTimeline({super.key, required this.current, required this.start, required this.end});

  int _currentIndex(List<WorkStage> stages) => current == null ? -1 : stages.indexOf(current!);

  @override
  Widget build(BuildContext context) {
    final stages = WorkStage.values;
    final cs = Theme.of(context).colorScheme;
    final accent = cs.secondary; // current stage highlight
    final idx = _currentIndex(stages);
    final startLabel = start == null ? 'Start' : _fmtDate(start!);
    final endLabel = end == null ? 'End' : _fmtDate(end!);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Stages', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final timeline = _buildTimeline(context, stages, idx, cs, accent);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 88,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Start', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.outline)),
              const SizedBox(height: 4),
              Text(startLabel, style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
            ]),
          ),
          Expanded(child: timeline),
          SizedBox(
            width: 88,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('End', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.outline)),
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerRight, child: Text(endLabel, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.right, maxLines: 2)),
            ]),
          ),
        ]);
      }),
    ]);
  }

  Widget _buildTimeline(BuildContext context, List<WorkStage> stages, int currentIndex, ColorScheme cs, Color accent) {
    final activeColor = cs.primary;
    final currentColor = accent;
    final inactive = cs.outlineVariant;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: stages.length * 120),
        child: Timeline.tileBuilder(
          theme: TimelineThemeData(
            direction: Axis.horizontal,
            connectorTheme: ConnectorThemeData(color: inactive, thickness: 3),
            indicatorTheme: IndicatorThemeData(color: inactive, size: 20),
          ),
          builder: TimelineTileBuilder.connected(
            connectionDirection: ConnectionDirection.before,
            itemExtentBuilder: (_, __) => 120,
            itemCount: stages.length,
            indicatorBuilder: (context, index) {
              final reached = currentIndex >= index && currentIndex >= 0;
              final isCurrent = currentIndex == index;
              final color = isCurrent ? currentColor : (reached ? activeColor : inactive);
              return _AnimatedIndicator(color: color, active: reached, isCurrent: isCurrent);
            },
            connectorBuilder: (context, index, type) {
              final reached = currentIndex >= index && currentIndex >= 0;
              final color = reached ? activeColor : inactive.withValues(alpha: 0.5);
              return DecoratedLineConnector(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.withValues(alpha: 0.2), color]),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
            contentsBuilder: (context, index) {
              final stage = stages[index];
              final isCurrent = currentIndex == index;
              final reached = currentIndex >= index && currentIndex >= 0;
              final color = isCurrent ? currentColor : (reached ? activeColor : cs.outline);
              return Padding(
                padding: const EdgeInsets.only(top: 42.0),
                child: SizedBox(
                  width: 120,
                  child: Text(stage.name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnimatedIndicator extends StatefulWidget {
  final Color color; final bool active; final bool isCurrent;
  const _AnimatedIndicator({required this.color, required this.active, required this.isCurrent});
  @override
  State<_AnimatedIndicator> createState() => _AnimatedIndicatorState();
}

class _AnimatedIndicatorState extends State<_AnimatedIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true); }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final base = widget.isCurrent ? 22.0 : 18.0;
    final pulse = widget.isCurrent ? (1 + 0.18 * CurvedAnimation(parent: _c, curve: Curves.easeInOut).value) : 1.0;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: base * pulse,
        height: base * pulse,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
color: widget.active ? widget.color : widget.color.withValues(alpha: 0.15),
          border: Border.all(color: widget.color, width: widget.isCurrent ? 3 : 2),
boxShadow: widget.isCurrent ? [BoxShadow(color: widget.color.withValues(alpha: 0.45), blurRadius: 10, spreadRadius: 1)] : null,
        ),
      ),
    );
  }
}

String _fmtDate(DateTime d) => d.toLocal().toString().split(' ').first;
