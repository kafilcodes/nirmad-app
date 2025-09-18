import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../projects/domain/project.dart';
import 'nodal_dashboard_list_page.dart' show nodalOverdueDaysFilterProvider, nodalStatusFilterProvider, blockFilterProvider, nodalStageFilterProvider, gramPanchayatFilterProvider;
import 'dart:math' as math;

// Required charts for dashboard:
// - Pie (outlined) of project count by block (left/top-left)
// - Radar chart of project count by stage (right/top-right)
// - Bar chart of Completed/Cancelled/In-progress with numeric stats on top
// All charts are responsive; 0 counts now show an explicit placeholder (–) in labels.

class ProjectsCharts extends ConsumerWidget {
  final Query<Map<String, dynamic>>? query;
  final bool isWide;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;
  final bool isSubNodal; // when true, render sub-nodal specific charts
  final VoidCallback? onNavigateToProjects;
  const ProjectsCharts({super.key, this.query, this.isWide = true, this.docs, this.isSubNodal = false, this.onNavigateToProjects});

  // Helper for child widgets to trigger navigation without tight coupling.
  static void navigateToProjects(BuildContext context) {
    // Bubble up a notification? For now rely on ancestor providing callback via InheritedElement.
    // This static is a placeholder; actual navigation handled by onNavigateToProjects closure in build tree.
    // Intentionally left minimal since direct context->callback lookup is not implemented here.
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If docs are provided, avoid building another stream
    if (docs != null) {
      return _buildCharts(context, ref, docs!, onNavigateToProjects);
    }
    final stream = (query ?? FirebaseFirestore.instance.collection('projects').orderBy('updatedAt', descending: true))
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          // Shimmer skeleton while loading
          return const _ChartsLoadingSkeleton();
        }
        final docs = snap.data!.docs;
        return _buildCharts(context, ref, docs, onNavigateToProjects);
      },
    );
  }

  Widget _buildCharts(BuildContext context, WidgetRef ref, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, VoidCallback? onNavigate) {
    // Build aggregations
    int completed = 0, inProgress = 0, cancelled = 0;
    final byBlock = <String, int>{};
    final byStage = <String, int>{};
    final byGram = <String, int>{}; // villageId
    final byGp = <String, int>{}; // Gram Panchayat from prelim
    for (final d in docs) {
      final m = d.data();
      final st = (m['status'] as String?) ?? 'in_progress';
      if (st == 'completed') {
        completed++;
      } else if (st == 'cancelled') {
        cancelled++;
      } else {
        inProgress++;
      }
      final block = (m['blockId'] as String?)?.trim();
      if (block != null && block.isNotEmpty) {
        byBlock[block] = (byBlock[block] ?? 0) + 1;
      }
      final gram = (m['villageId'] as String?)?.trim();
      final gramKey = (gram == null || gram.isEmpty) ? 'Unknown' : gram;
      byGram[gramKey] = (byGram[gramKey] ?? 0) + 1;
      final prelim = (m['preliminaryDescription'] as Map<String, dynamic>?) ?? const {};
      final gp = (prelim['gramPanchayat'] as String?)?.trim();
      final gpKey = (gp == null || gp.isEmpty) ? 'Unknown' : gp;
      byGp[gpKey] = (byGp[gpKey] ?? 0) + 1;
      final wd = (m['workDescription'] as Map<String, dynamic>?) ?? const {};
      var stage = (wd['stage'] as String?) ?? 'unknown';
      stage = stage.trim().toLowerCase();
      // If status is completed, coerce stage to completed for accurate charting
      if (st == 'completed') stage = 'completed';
      byStage[stage] = (byStage[stage] ?? 0) + 1;
    }
    // Sort groups for readability
    final blockEntries = byBlock.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topBlocks = blockEntries.take(7).toList();
    final gpEntries = byGp.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topGps = gpEntries.take(7).toList();
    // Stage list dynamically from observed keys; ensure stable order when present
    final preferred = <String>['layout', 'plinth', 'lintel', 'finishing', 'completed', 'unknown'];
    // Include any unexpected stages too
    final observed = byStage.keys.toSet();
    final order = <String>[
      ...preferred.where((s) => observed.contains(s)),
      ...observed.where((s) => !preferred.contains(s)).toList()..sort(),
    ];
    final stageEntries = [for (final s in order) MapEntry(s, byStage[s] ?? 0)];

  final selectedStage = ref.watch(nodalStageFilterProvider);
  final selectedBlock = ref.watch(blockFilterProvider);
  final selectedStatus = ref.watch(nodalStatusFilterProvider);
  return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 720;
      final veryNarrow = c.maxWidth < 360;
      final half = (c.maxWidth - 12) / (narrow ? 1 : 2);
      // Further responsive adjustments: treat ultra narrow and short cards differently.
      final isAndroid = Theme.of(context).platform == TargetPlatform.android;
      final isSmallWidth = c.maxWidth < 420;
      // Heights tuned for overlap prevention; pie is a bit smaller on small screens,
      // while radar/bars are larger on small Android for better readability/tap targets.
      double pieHeight = isSmallWidth ? 206 : 272;
      double radarHeight = isSmallWidth ? 300 : 320;
      double barsHeight = veryNarrow ? 250 : 290;
      if (isAndroid && isSmallWidth) {
        // Favor larger analytical charts on small Android
        radarHeight += 30;
        barsHeight += 30;
      }
      // Equalize pie and radar heights on wide (desktop) layouts for visual balance
      if (!narrow) {
        final equal = math.max(pieHeight, radarHeight);
        pieHeight = equal;
        radarHeight = equal;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Uniform vertical spacing: each chart card gets symmetric vertical padding
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (!isSubNodal) ...[
                SizedBox(
                  width: half,
                  // Responsive pie height (pie + legends)
                  height: pieHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: _SafeChart(
                          builder: () => _OutlinedPieByBlock(
                            blocks: topBlocks,
                            small: c.maxWidth < 420,
                            selectedBlock: selectedBlock,
                            onSelect: (label) {
                              if (label.trim().isEmpty) return;
                              ref.read(nodalStatusFilterProvider.notifier).state = null;
                              ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
                              ref.read(blockFilterProvider.notifier).state = label;
                              onNavigate?.call();
                            },
                          ),
                          fallbackLabel: 'Projects by block',
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: half,
                  // Responsive radar height
                  height: radarHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: _SafeChart(
                          builder: () => _RadarByStage(
                            entries: stageEntries,
                            small: c.maxWidth < 500,
                            selectedStage: selectedStage,
                            onSelectStage: (stage) {
                              if (stage.trim().isEmpty) return;
                              ref.read(nodalStageFilterProvider.notifier).state = stage;
                              ref.read(nodalStatusFilterProvider.notifier).state = null;
                              ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
                              onNavigate?.call();
                            },
                          ),
                          fallbackLabel: 'Projects by stage',
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: half,
                  // Sub-nodal pie height
                  height: pieHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: _SafeChart(
                          builder: () => _OutlinedPieByGroup(title: 'Projects by Gram Panchayat', entries: topGps, small: c.maxWidth < 420, onNavigate: onNavigate),
                          fallbackLabel: 'Projects by Gram Panchayat',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              SizedBox(
                width: c.maxWidth,
                height: barsHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            children: [
                              _StatChip(
                                color: Colors.green,
                                label: 'Completed',
                                value: completed,
                                icon: CupertinoIcons.check_mark_circled,
                                selected: selectedStatus == ProjectStatus.completed,
                                onTap: () {
                                  ref.read(nodalStatusFilterProvider.notifier).state = ProjectStatus.completed;
                                  ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
                                  onNavigate?.call();
                                },
                              ),
                              _StatChip(
                                color: Colors.orange,
                                label: 'In progress',
                                value: inProgress,
                                icon: CupertinoIcons.time,
                                selected: selectedStatus == ProjectStatus.in_progress,
                                onTap: () {
                                  ref.read(nodalStatusFilterProvider.notifier).state = ProjectStatus.in_progress;
                                  ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
                                  onNavigate?.call();
                                },
                              ),
                              _StatChip(
                                color: Colors.redAccent,
                                label: 'Cancelled',
                                value: cancelled,
                                icon: CupertinoIcons.xmark_octagon,
                                selected: selectedStatus == ProjectStatus.cancelled,
                                onTap: () {
                                  ref.read(nodalStatusFilterProvider.notifier).state = ProjectStatus.cancelled;
                                  ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
                                  onNavigate?.call();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: _StatusBars(
                              completed: completed.toDouble(),
                              inProgress: inProgress.toDouble(),
                              cancelled: cancelled.toDouble(),
                              realCompleted: completed,
                              realInProgress: inProgress,
                              realCancelled: cancelled,
                              onSelect: (idx) {
                                if (idx == 0) {
                                  ref.read(nodalStatusFilterProvider.notifier).state = ProjectStatus.completed;
                                } else if (idx == 1) {
                                  ref.read(nodalStatusFilterProvider.notifier).state = ProjectStatus.in_progress;
                                } else if (idx == 2) {
                                  ref.read(nodalStatusFilterProvider.notifier).state = ProjectStatus.cancelled;
                                }
                                ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
                                onNavigate?.call();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

// _ScatterByGram removed per requirement: sub-nodal dashboard should only show
// 'Projects by Gram Panchayat' and the Progress Bar.

class _OutlinedPieByGroup extends ConsumerWidget {
  final String title;
  final List<MapEntry<String, int>> entries;
  final bool small;
  final VoidCallback? onNavigate;
  const _OutlinedPieByGroup({required this.title, required this.entries, this.small = false, this.onNavigate});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = entries.fold<int>(0, (p, e) => p + e.value);
    final cs = Theme.of(context).colorScheme;
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final colors = [
      Colors.blue, Colors.orange, Colors.green, Colors.purple, Colors.cyan, Colors.teal, Colors.indigo
    ];
    if (entries.isEmpty || total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Expanded(child: _ChartFallback(label: title)),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Expanded(
          child: PieChart(
            PieChartData(
              startDegreeOffset: -90,
              centerSpaceRadius: (MediaQuery.of(context).size.width < 360)
                  ? 30.0
                  : (small ? 36.0 : 46.0) - (isAndroid && small ? 4.0 : 0.0),
              sectionsSpace: (MediaQuery.of(context).size.width < 360) ? 3 : (small ? 2 : 2),
              borderData: FlBorderData(show: false),
              pieTouchData: PieTouchData(
                enabled: true,
                touchCallback: (event, response) {
                  final i = response?.touchedSection?.touchedSectionIndex;
                  if (i != null && i >= 0 && i < entries.length && event is FlTapUpEvent) {
                    final label = entries[i].key.trim();
                    if (label.isNotEmpty) {
                      ref.read(gramPanchayatFilterProvider.notifier).state = label.toLowerCase();
                      // Clear mutually exclusive filters that would conflict conceptually.
                      ref.read(nodalStatusFilterProvider.notifier).state = null;
                      ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
                      // Navigate to projects list via inherited callback using Notification (decouple from direct dependency)
                      onNavigate?.call();
                    }
                  }
                },
              ),
              sections: [
                for (int i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].value.toDouble(),
                    color: colors[i % colors.length],
                    radius: (MediaQuery.of(context).size.width < 360)
                        ? 42.0
                        : (small ? 46.0 : 54.0) - (isAndroid && small ? 4.0 : 0.0),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
                    title: () {
                      final totalLocal = total == 0 ? 1 : total;
                      final pct = entries[i].value / totalLocal;
                      final veryNarrow = MediaQuery.of(context).size.width < 360;
                      // Hide tiny slice labels on very narrow screens to avoid overlaps
                      if (veryNarrow && (pct < 0.14 || entries.length > 5)) return '';
                      return '${(pct * 100).toStringAsFixed(0)}%';
                    }(),
                    titleStyle: TextStyle(
                      fontSize: (MediaQuery.of(context).size.width < 360) ? 7.5 : (small ? 8 : 10),
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimary,
                    ),
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 450),
          ),
        ),
  const SizedBox(height: 12), // increased spacing between chart and legends
        _AdaptiveLegends(
          entries: entries,
          colorForIndex: (i) => colors[i % colors.length],
          maxVisible: 7,
          labelBuilder: (e) => e.key,
          onTap: (e) {
            final label = e.key.trim();
            if (label.isEmpty) return;
            ref.read(gramPanchayatFilterProvider.notifier).state = label.toLowerCase();
            ref.read(nodalStatusFilterProvider.notifier).state = null;
            ref.read(nodalOverdueDaysFilterProvider.notifier).state = null;
            onNavigate?.call();
          },
        ),
        ],
      ),
    );
  }
}

class _OutlinedPieByBlock extends StatelessWidget {
  final List<MapEntry<String, int>> blocks;
  final bool small;
  final void Function(String label)? onSelect;
  final String? selectedBlock;
  const _OutlinedPieByBlock({required this.blocks, this.small = false, this.onSelect, this.selectedBlock});
  @override
  Widget build(BuildContext context) {
    final total = blocks.fold<int>(0, (p, e) => p + e.value);
    final cs = Theme.of(context).colorScheme;
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final colors = [
      Colors.blue, Colors.orange, Colors.green, Colors.purple, Colors.cyan, Colors.teal, Colors.indigo
    ];
    if (blocks.isEmpty || total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Text('Projects by block', style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Expanded(child: _ChartFallback(label: 'Projects by block')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Projects by block', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
  Expanded(
          child: PieChart(
            PieChartData(
              startDegreeOffset: -90,
              centerSpaceRadius: (MediaQuery.of(context).size.width < 360)
                  ? 30.0
                  : (small ? 36.0 : 46.0) - (isAndroid && small ? 4.0 : 0.0),
              sectionsSpace: (MediaQuery.of(context).size.width < 360) ? 3 : (small ? 2 : 2),
              borderData: FlBorderData(show: false),
              pieTouchData: PieTouchData(
                enabled: onSelect != null,
                touchCallback: (event, response) {
                  final i = response?.touchedSection?.touchedSectionIndex;
                  if (i != null && i >= 0 && i < blocks.length && event is FlTapUpEvent) {
                    onSelect?.call(blocks[i].key);
                  }
                },
              ),
              sections: [
                for (int i = 0; i < blocks.length; i++)
                  PieChartSectionData(
                    value: blocks[i].value.toDouble(),
                    color: colors[i % colors.length],
                    radius: (MediaQuery.of(context).size.width < 360)
                        ? 42.0
                        : (small ? 46.0 : 54.0) - (isAndroid && small ? 4.0 : 0.0),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
                    title: () {
                      final veryNarrow = MediaQuery.of(context).size.width < 360;
                      final pct = total == 0 ? 0 : (blocks[i].value / total);
                      if (veryNarrow && (pct < 0.14 || blocks.length > 5)) return '';
                      return '${(pct * 100).toStringAsFixed(0)}%';
                    }(),
                    titleStyle: TextStyle(fontSize: (MediaQuery.of(context).size.width < 360) ? 7.5 : (small ? 9 : 11), fontWeight: FontWeight.w600, color: cs.onPrimary),
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 450),
          ),
        ),
  const SizedBox(height: 12), // increased spacing between chart and legends
        _AdaptiveLegends(
          entries: blocks,
          colorForIndex: (i) => colors[i % colors.length],
          maxVisible: 7,
          labelBuilder: (e) => e.key,
          onTap: (e) => onSelect?.call(e.key),
          isSelected: (e) => selectedBlock != null && selectedBlock == e.key,
        ),
      ],
    );
  }
}

class _RadarByStage extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final bool small;
  final void Function(String stage)? onSelectStage;
  final String? selectedStage;
  const _RadarByStage({required this.entries, this.small = false, this.onSelectStage, this.selectedStage});
  @override
  Widget build(BuildContext context) {
    final hasAny = entries.any((e) => e.value > 0);
    if (entries.isEmpty || !hasAny) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Projects by stage', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: Text('No stage data', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
            ),
          ),
        ],
      );
    }
    final maxVal = entries.fold<int>(0, (p, e) => e.value > p ? e.value : p);
    // Decide ring count based on max value for readable scale.
    int ringCount;
    if (maxVal <= 3) {
      ringCount = maxVal; // 1..3
    } else if (maxVal <= 6) {
      ringCount = 3;
    } else if (maxVal <= 10) {
      ringCount = 5;
    } else {
      ringCount = 5; // cap for large ranges; avoids clutter
    }
    ringCount = ringCount.clamp(1, 6);
    final step = maxVal == 0 || ringCount == 0 ? 1 : (maxVal / ringCount);
    final markers = [for (int i = 1; i <= ringCount; i++) (step * i).ceil().clamp(1, maxVal)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Projects by stage', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: RadarChart(
                  RadarChartData(
                    radarBorderData: const BorderSide(color: Colors.transparent),
                    gridBorderData: const BorderSide(color: Colors.black12),
                    radarBackgroundColor: Colors.transparent,
                    titleTextStyle: TextStyle(fontSize: small ? 9 : 11),
                    dataSets: [
                      RadarDataSet(
                        borderColor: Theme.of(context).colorScheme.primary,
                        fillColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                        entryRadius: 1.5,
                        dataEntries: [
                          for (final e in entries) RadarEntry(value: e.value.toDouble()),
                        ],
                      ),
                    ],
                    titlePositionPercentageOffset: small ? 0.22 : 0.18,
                    getTitle: (index, angle) => RadarChartTitle(text: _fmtStage(entries[index].key)),
                    radarShape: RadarShape.polygon,
                    ticksTextStyle: const TextStyle(fontSize: 8, color: Colors.black45),
                    tickCount: ringCount,
                  ),
                  duration: const Duration(milliseconds: 450),
                ),
              ),
              if (maxVal > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Scale: 0 • ${markers.take(ringCount - 1).join(' • ')}${ringCount > 1 ? ' • ' : ''}$maxVal',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StageLegends(entries: entries, onTap: onSelectStage, selectedStage: selectedStage),
      ],
    );
  }
}

class _StatusBars extends StatelessWidget {
  final double completed;
  final double inProgress;
  final double cancelled;
  final int realCompleted;
  final int realInProgress;
  final int realCancelled;
  final void Function(int index)? onSelect;
  const _StatusBars({
    required this.completed,
    required this.inProgress,
    required this.cancelled,
    this.realCompleted = 0,
    this.realInProgress = 0,
    this.realCancelled = 0,
    this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    final bars = [
      ('Completed', completed, Colors.green, realCompleted),
      ('In progress', inProgress, Colors.orange, realInProgress),
      ('Cancelled', cancelled, Colors.redAccent, realCancelled),
    ];
    final screenW = MediaQuery.of(context).size.width;
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final smallW = screenW < 420;
    final rodWidth = (isAndroid && smallW) ? 28.0 : 24.0;
  final maxValue = [realCompleted, realInProgress, realCancelled].fold<int>(0, (p, n) => n > p ? n : p);
  final total = realCompleted + realInProgress + realCancelled;
  // Removed ghost bar; zero values render no bar (only dash in top labels)
    return BarChart(
      BarChartData(
        barTouchData: BarTouchData(
          enabled: true,
            touchTooltipData: BarTouchTooltipData(
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final idx = group.x.toInt();
              if (idx < 0 || idx >= bars.length) return null;
              final title = bars[idx].$1;
              final value = bars[idx].$4;
              final pct = (total > 0 && value > 0) ? ' (${(value / total * 100).toStringAsFixed(0)}%)' : '';
              return BarTooltipItem('$title: $value$pct', const TextStyle(fontWeight: FontWeight.w600));
            },
          ),
          touchCallback: (event, response) {
            final i = response?.spot?.touchedBarGroupIndex;
            if (i != null && event is FlTapUpEvent) {
              onSelect?.call(i);
            }
          },
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= bars.length) return const SizedBox.shrink();
                final real = bars[i].$4;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(real > 0 ? '$real' : '–', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= bars.length) return const SizedBox.shrink();
                final full = bars[i].$1;
                final veryNarrow = MediaQuery.of(context).size.width < 360;
                final label = veryNarrow
                    ? (full == 'Completed'
                        ? 'Done'
                        : full == 'In progress'
                            ? 'In prog'
                            : full == 'Cancelled'
                                ? 'Cancel'
                                : full)
                    : full;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                );
              },
            ),
          ),
        ),
        maxY: (maxValue > 0 ? maxValue : 1).toDouble(),
        barGroups: [
          for (int i = 0; i < bars.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: bars[i].$4 > 0 ? bars[i].$2 : 0.0,
                  color: bars[i].$3.withValues(alpha: bars[i].$4 > 0 ? 1.0 : 0.15), // faint color retained though height zero
                  width: rodWidth,
                  borderRadius: BorderRadius.circular(8),
                ),
              ],
            ),
        ],
      ),
      duration: const Duration(milliseconds: 450),
    );
  }
}

String _fmtStage(String id) {
  switch (id) {
    case 'layout':
      return 'Layout';
    case 'plinth':
      return 'Plinth';
    case 'lintel':
      return 'Lintel';
    case 'finishing':
      return 'Finishing';
    case 'completed':
      return 'Completed';
    case 'unknown':
      return 'Unknown';
    default:
      if (id.isEmpty) return '—';
      return id[0].toUpperCase() + id.substring(1);
  }
}

class _StatChip extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  const _StatChip({required this.color, required this.label, required this.value, this.icon, this.selected = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? color : color.withValues(alpha: 0.35), width: selected ? 1.3 : 1),
        color: selected ? color.withValues(alpha: 0.12) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null)
          Icon(icon, size: 13, color: color)
        else
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$value', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? color : null)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: selected ? color : null)),
      ]),
    );
    if (onTap == null) {
      return Semantics(label: '$label: $value projects', child: chip);
    }
    return Semantics(
      button: true,
      label: '$label: $value projects',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: chip,
      ),
    );
  }
}

/// Wraps charts to prevent UI crashes; renders a soft fallback when the child throws.
class _SafeChart extends StatelessWidget {
  final Widget Function() builder;
  final String fallbackLabel;
  const _SafeChart({required this.builder, required this.fallbackLabel});

  @override
  Widget build(BuildContext context) {
    try {
      final w = builder();
      return w;
    } catch (_) {
      return _ChartFallback(label: fallbackLabel);
    }
  }
}

class _ChartFallback extends StatelessWidget {
  final String label;
  const _ChartFallback({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Center(
              child: Text('No data to display', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shimmer effect widget (self-contained, no external dependency).
class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final shimmerPosition = _c.value;
        return ShaderMask(
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment(-1 - shimmerPosition, 0),
              end: Alignment(1 + shimmerPosition, 0),
              colors: [
                cs.surfaceContainerHighest.withValues(alpha: 0.15),
                cs.surfaceContainerHighest.withValues(alpha: 0.45),
                cs.surfaceContainerHighest.withValues(alpha: 0.15),
              ],
              stops: const [0.15, 0.5, 0.85],
            ).createShader(rect);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

/// A simple rectangular skeleton block.
class _SkeletonBlock extends StatelessWidget {
  final double height;
  final double? width;
  final BorderRadius? radius;
  const _SkeletonBlock({required this.height, this.width, this.radius});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: radius ?? BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Skeleton layout replicating charts arrangement while loading stream.
class _ChartsLoadingSkeleton extends StatelessWidget {
  const _ChartsLoadingSkeleton();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 720;
      final veryNarrow = c.maxWidth < 360;
      final half = (c.maxWidth - 12) / (narrow ? 1 : 2);
      final cardRadius = BorderRadius.circular(12);
      Widget chartCard({required double width, required double height, int? legendLines}) {
        return SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SkeletonBlock(height: 14, width: 140, radius: BorderRadius.all(Radius.circular(4))),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: _SkeletonBlock(
                          height: (height - 80) * 0.8,
                          width: (height - 80) * 0.8,
                          radius: cardRadius,
                        ),
                      ),
                    ),
                    if (legendLines != null) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: List.generate(legendLines, (i) => const _SkeletonBlock(height: 20, width: 90)).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return Padding(
        // extra space to avoid Android bottom gesture/nav bar crowding on small screens
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  chartCard(width: half, height: veryNarrow ? 250 : 320, legendLines: 4),
                  if (!narrow) chartCard(width: half, height: veryNarrow ? 250 : 320, legendLines: 5),
                  if (narrow)
                    chartCard(width: half, height: veryNarrow ? 250 : 320, legendLines: 5),
                  SizedBox(
                    width: c.maxWidth,
                    height: veryNarrow ? 260 : 300,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                children: List.generate(3, (i) => const _SkeletonBlock(height: 26, width: 110, radius: BorderRadius.all(Radius.circular(20)))).toList(),
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (int i = 0; i < 3; i++) ...[
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: _SkeletonBlock(height: (veryNarrow ? 180 : 200) * (0.4 + i * 0.2), width: 30, radius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                      if (i < 2) const SizedBox(width: 12),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),),
        );
    });
  }
}

/// Adaptive legends for pie/group charts with overflow handling.
class _AdaptiveLegends extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final Color Function(int index) colorForIndex;
  final int maxVisible;
  final String Function(MapEntry<String, int>) labelBuilder;
  final void Function(MapEntry<String, int>)? onTap;
  final bool Function(MapEntry<String, int>)? isSelected;
  const _AdaptiveLegends({
    required this.entries,
    required this.colorForIndex,
    required this.maxVisible,
    required this.labelBuilder,
    this.onTap,
    this.isSelected,
  });
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final show = entries.take(maxVisible).toList();
    final overflow = entries.length - show.length;
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 360;
      final children = <Widget>[
        for (int i = 0; i < show.length; i++)
          _LegendChip(
            color: colorForIndex(i),
            label: labelBuilder(show[i]),
            value: show[i].value,
            dense: narrow,
            onTap: onTap == null ? null : () => onTap!(show[i]),
            selected: isSelected?.call(show[i]) ?? false,
          ),
        if (overflow > 0)
          _OverflowChip(count: overflow, onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (ctx) => _LegendOverflowSheet(
                entries: entries,
                colorForIndex: colorForIndex,
                labelBuilder: labelBuilder,
                onTap: onTap,
                isSelected: isSelected,
              ),
            );
          }),
      ];
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: c.maxWidth),
        child: Wrap(
          spacing: (c.maxWidth < 360) ? 3 : 6,
          runSpacing: (c.maxWidth < 360) ? 3 : 6,
          children: children,
        ),
      );
    });
  }
}

class _LegendChip extends StatefulWidget {
  final Color color;
  final String label;
  final int value;
  final bool dense;
  final VoidCallback? onTap;
  final bool selected;
  const _LegendChip({required this.color, required this.label, required this.value, this.dense = false, this.onTap, this.selected = false});
  @override
  State<_LegendChip> createState() => _LegendChipState();
}

class _LegendChipState extends State<_LegendChip> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  void _set(bool v) {
    if (_pressed == v) return; setState(() => _pressed = v);
  }
  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final dense = widget.dense;
    final color = widget.color;
    final value = widget.value;
    final selected = widget.selected;
    final text = label.length > (dense ? 12 : 20) ? '${label.substring(0, (dense ? 10 : 17))}…' : label;
    return Semantics(
      label: '$label: $value projects',
      button: widget.onTap != null,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTapDown: (_) => _set(true),
          onTapCancel: () => _set(false),
          onTapUp: (_) => _set(false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.94 : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 4 : 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? color : color.withValues(alpha: 0.45), width: selected ? 1.4 : 1),
                color: selected ? color.withValues(alpha: 0.14) : color.withValues(alpha: 0.06),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('$text ($value)', style: TextStyle(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600, color: selected ? color : null)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverflowChip extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  const _OverflowChip({required this.count, this.onTap});
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(CupertinoIcons.ellipsis, size: 16),
      label: Text('+$count more'),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }
}

class _StageLegends extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final void Function(String stage)? onTap;
  final String? selectedStage;
  const _StageLegends({required this.entries, this.onTap, this.selectedStage});
  IconData _iconFor(String key) {
    switch (key) {
      case 'layout':
        return CupertinoIcons.map;
      case 'plinth':
        return Icons.foundation;
      case 'lintel':
        return Icons.architecture;
      case 'finishing':
        return Icons.brush;
      case 'completed':
        return CupertinoIcons.check_mark_circled;
      default:
        return CupertinoIcons.question_circle;
    }
  }
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 400;
      // compute max for shade scaling
      final maxVal = entries.fold<int>(0, (p, e) => e.value > p ? e.value : p);
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (int i = 0; i < entries.length; i++)
            _StageLegendChip(
              stage: entries[i].key,
              value: entries[i].value,
              icon: _iconFor(entries[i].key),
              selected: selectedStage == entries[i].key,
              narrow: narrow,
              onTap: onTap,
              shadeFactor: maxVal == 0 ? 0.3 : (entries[i].value / maxVal),
            ),
        ],
      );
    });
  }
}

class _StageLegendChip extends StatefulWidget {
  final String stage;
  final int value;
  final IconData icon;
  final bool selected;
  final bool narrow;
  final void Function(String stage)? onTap;
  final double? shadeFactor; // 0..1 influencing color lightness
  const _StageLegendChip({required this.stage, required this.value, required this.icon, required this.selected, required this.narrow, this.onTap, this.shadeFactor});
  @override
  State<_StageLegendChip> createState() => _StageLegendChipState();
}

class _StageLegendChipState extends State<_StageLegendChip> {
  bool _pressed = false;
  void _set(bool v) { if (_pressed == v) return; setState(()=>_pressed=v);}  
  @override
  Widget build(BuildContext context) {
  final label = _fmtStage(widget.stage.contains(':') ? widget.stage.split(':').first : widget.stage);
  final base = Theme.of(context).colorScheme.primary;
  final f = (widget.shadeFactor ?? 1).clamp(0.0, 1.0);
  // lighter for lower values
  final bgBlend = Color.alphaBlend(base.withValues(alpha: 0.05 + 0.10 * f), Theme.of(context).colorScheme.surface);
  final borderColor = base.withValues(alpha: widget.selected ? 0.9 : (0.25 + 0.35 * f));
    return Semantics(
      label: '$label: ${widget.value} projects',
      button: widget.onTap != null,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: widget.onTap == null ? null : () => widget.onTap!(widget.stage),
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: EdgeInsets.symmetric(horizontal: widget.narrow ? 8 : 9, vertical: widget.narrow ? 4 : 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.selected ? base : borderColor,
                width: widget.selected ? 1.4 : 1,
              ),
              color: widget.selected ? base.withValues(alpha: 0.16) : bgBlend,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.icon, size: 14, color: widget.selected ? base : base.withValues(alpha: 0.85 * (0.4 + 0.6 * f))),
              const SizedBox(width: 6),
              Text(
                '$label (${widget.value})',
                style: TextStyle(
                  fontSize: widget.narrow ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  // Consistent text color: primary only when selected, otherwise default (no shaded accent variants)
                  color: widget.selected ? base : null,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _LegendOverflowSheet extends StatefulWidget {
  final List<MapEntry<String,int>> entries;  
  final Color Function(int index) colorForIndex;  
  final String Function(MapEntry<String,int>) labelBuilder;  
  final void Function(MapEntry<String,int>)? onTap;  
  final bool Function(MapEntry<String,int>)? isSelected;
  const _LegendOverflowSheet({required this.entries, required this.colorForIndex, required this.labelBuilder, this.onTap, this.isSelected});
  @override
  State<_LegendOverflowSheet> createState() => _LegendOverflowSheetState();
}

class _LegendOverflowSheetState extends State<_LegendOverflowSheet> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = _query.trim().isEmpty
        ? widget.entries
        : widget.entries.where((e) => widget.labelBuilder(e).toLowerCase().contains(_query.toLowerCase())).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(child: Text('All categories', style: Theme.of(context).textTheme.titleMedium)),
                  Text('${widget.entries.length}', style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(CupertinoIcons.search, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'Filter categories',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final e = filtered[i];
                  final color = widget.colorForIndex(widget.entries.indexOf(e));
                  final selected = widget.isSelected?.call(e) ?? false;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _LegendChip(
                      color: color,
                      label: widget.labelBuilder(e),
                      value: e.value,
                      dense: false,
                      selected: selected,
                      onTap: widget.onTap == null
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              widget.onTap!(e);
                            },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
