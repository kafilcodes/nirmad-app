import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Required charts for dashboard:
// - Pie (outlined) of project count by block (left/top-left)
// - Radar chart of project count by stage (right/top-right)
// - Bar chart of Completed/Cancelled/In-progress with numeric stats on top
// All charts are responsive; 0 counts are rendered as 1 for visibility.

class ProjectsCharts extends ConsumerWidget {
  final Query<Map<String, dynamic>>? query;
  final bool isWide;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;
  final bool isSubNodal; // when true, render sub-nodal specific charts
  const ProjectsCharts({super.key, this.query, this.isWide = true, this.docs, this.isSubNodal = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  // If docs are provided, avoid building another stream
    if (docs != null) {
      return _buildCharts(context, docs!);
    }
    final stream = (query ?? FirebaseFirestore.instance.collection('projects').orderBy('updatedAt', descending: true))
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        return _buildCharts(context, docs);
      },
    );
  }

  Widget _buildCharts(BuildContext context, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
        // Build aggregations
  int safe(int v) => v == 0 ? 1 : v;
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
        final blockEntries = byBlock.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
        final topBlocks = blockEntries.take(7).toList();
        if (topBlocks.isEmpty) topBlocks.add(const MapEntry('No data', 1));
        final gramEntries = byGram.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
        final topGrams = gramEntries.take(12).toList();
        if (topGrams.isEmpty) topGrams.add(const MapEntry('No data', 1));
        final gpEntries = byGp.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
        final topGps = gpEntries.take(7).toList();
        if (topGps.isEmpty) topGps.add(const MapEntry('No data', 1));
        // Stage list dynamically from observed keys; ensure stable order when present
        final preferred = <String>['layout','plinth','lintel','finishing','completed','unknown'];
        // Include any unexpected stages too
        final observed = byStage.keys.toSet();
        final order = <String>[
          ...preferred.where((s) => observed.contains(s)),
          ...observed.where((s) => !preferred.contains(s)).toList()..sort(),
        ];
        final stageEntries = [for (final s in order) MapEntry(s, byStage[s] ?? 0)];
  // Total numbers (no longer used in UI chips)
  // final total = docs.isEmpty ? 1 : docs.length;

  // Layout: charts only (numeric chips removed; stats are shown in top section)
  return LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 720;
          final veryNarrow = c.maxWidth < 360;
          final shortBars = c.maxWidth < 420;
          final half = (c.maxWidth - 12) / (narrow ? 1 : 2);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Charts grid
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (!isSubNodal) ...[
                    SizedBox(
                      width: half,
                      height: veryNarrow ? 220 : 260,
                      child: Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: _SafeChart(
                            builder: () => _OutlinedPieByBlock(blocks: topBlocks, small: c.maxWidth < 420),
                            fallbackLabel: 'Projects by block',
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: half,
                      height: veryNarrow ? 220 : 260,
                      child: Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: _SafeChart(
                            builder: () => _RadarByStage(entries: stageEntries, small: c.maxWidth < 500),
                            fallbackLabel: 'Projects by stage',
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: half,
                      height: veryNarrow ? 220 : 260,
                      child: Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: _SafeChart(
                            builder: () => _OutlinedPieByGroup(title: 'Projects by Gram Panchayat', entries: topGps, small: c.maxWidth < 420),
                            fallbackLabel: 'Projects by Gram Panchayat',
                          ),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(
                    width: c.maxWidth,
                    height: veryNarrow ? 260 : 300,
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
                                _StatChip(color: Colors.green, label: 'Completed', value: completed),
                                _StatChip(color: Colors.orange, label: 'In progress', value: inProgress),
                                _StatChip(color: Colors.redAccent, label: 'Cancelled', value: cancelled),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: _StatusBars(
                                completed: safe(completed).toDouble(),
                                inProgress: safe(inProgress).toDouble(),
                                cancelled: safe(cancelled).toDouble(),
                                shortLabels: shortBars,
                                // Real values for tooltips/labels
                                realCompleted: completed,
                                realInProgress: inProgress,
                                realCancelled: cancelled,
                              ),
                            ),
                          ],
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

class _OutlinedPieByGroup extends StatelessWidget {
  final String title;
  final List<MapEntry<String, int>> entries;
  final bool small;
  const _OutlinedPieByGroup({required this.title, required this.entries, this.small = false});
  @override
  Widget build(BuildContext context) {
    final total = entries.fold<int>(0, (p, e) => p + e.value);
    final safeTotal = total == 0 ? 1 : total;
    final cs = Theme.of(context).colorScheme;
    final colors = [
      Colors.blue, Colors.orange, Colors.green, Colors.purple, Colors.cyan, Colors.teal, Colors.indigo
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
  const SizedBox(height: 8),
        Expanded(
          child: PieChart(
            PieChartData(
              startDegreeOffset: -90,
              centerSpaceRadius: small ? 44 : 54,
              sectionsSpace: small ? 1 : 2,
              borderData: FlBorderData(show: false),
              sections: [
                for (int i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: (entries[i].value == 0 ? 1 : entries[i].value).toDouble(),
                    color: colors[i % colors.length],
                    radius: small ? 48 : 56,
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
                    title: '${((entries[i].value / safeTotal) * 100).toStringAsFixed(0)}%',
                    titleStyle: TextStyle(fontSize: small ? 9 : 11, fontWeight: FontWeight.w600, color: cs.onPrimary),
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 450),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final wrapWidth = c.maxWidth;
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wrapWidth),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (int i = 0; i < entries.length; i++)
                  _legend(colors[i % colors.length], entries[i].key, entries[i].value),
              ],
            ),
          );
        })
      ],
    );
  }

  Widget _legend(Color color, String text, int v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$text ($v)'),
      ]),
    );
  }
}

class _OutlinedPieByBlock extends StatelessWidget {
  final List<MapEntry<String, int>> blocks;
  final bool small;
  const _OutlinedPieByBlock({required this.blocks, this.small = false});
  @override
  Widget build(BuildContext context) {
    final total = blocks.fold<int>(0, (p, e) => p + e.value);
    final safeTotal = total == 0 ? 1 : total;
  final cs = Theme.of(context).colorScheme;
    final colors = [
      Colors.blue, Colors.orange, Colors.green, Colors.purple, Colors.cyan, Colors.teal, Colors.indigo
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Projects by block', style: TextStyle(fontWeight: FontWeight.w600)),
  const SizedBox(height: 8),
    Expanded(
          child: PieChart(
            PieChartData(
              startDegreeOffset: -90,
      centerSpaceRadius: small ? 44 : 54,
      sectionsSpace: small ? 1 : 2,
              borderData: FlBorderData(show: false),
              sections: [
                for (int i = 0; i < blocks.length; i++)
                  PieChartSectionData(
                    value: (blocks[i].value == 0 ? 1 : blocks[i].value).toDouble(),
                    color: colors[i % colors.length],
        radius: small ? 48 : 56,
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
        title: '${((blocks[i].value / safeTotal) * 100).toStringAsFixed(0)}%',
        titleStyle: TextStyle(fontSize: small ? 9 : 11, fontWeight: FontWeight.w600, color: cs.onPrimary),
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 450),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final wrapWidth = c.maxWidth;
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wrapWidth),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (int i = 0; i < blocks.length; i++)
                  _legend(colors[i % colors.length], blocks[i].key, blocks[i].value),
              ],
            ),
          );
        })
      ],
    );
  }

  Widget _legend(Color color, String text, int v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
  border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$text ($v)'),
      ]),
    );
  }
}

class _RadarByStage extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final bool small;
  const _RadarByStage({required this.entries, this.small = false});
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Projects by stage', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
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
                    for (final e in entries) RadarEntry(value: (e.value == 0 ? 1 : e.value).toDouble()),
                  ],
                ),
              ],
              titlePositionPercentageOffset: small ? 0.22 : 0.18,
              getTitle: (index, angle) => RadarChartTitle(text: _fmtStage(entries[index].key)),
              radarShape: RadarShape.polygon,
              ticksTextStyle: const TextStyle(fontSize: 8),
              tickCount: 3,
            ),
            duration: const Duration(milliseconds: 450),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final wrapWidth = c.maxWidth;
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wrapWidth),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in entries)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Text('${_fmtStage(e.key)} (${e.value})'),
                  ),
              ],
            ),
          );
        })
      ],
    );
  }
}

class _StatusBars extends StatelessWidget {
  final double completed;
  final double inProgress;
  final double cancelled;
  final bool shortLabels;
  final int realCompleted;
  final int realInProgress;
  final int realCancelled;
  const _StatusBars({
    required this.completed,
    required this.inProgress,
    required this.cancelled,
    this.shortLabels = false,
    this.realCompleted = 0,
    this.realInProgress = 0,
    this.realCancelled = 0,
  });
  @override
  Widget build(BuildContext context) {
    final bars = [
      ('Completed', completed, Colors.green),
      ('In progress', inProgress, Colors.orange),
      ('Cancelled', cancelled, Colors.redAccent),
    ];
  double clampBar(double v) => v == 0 ? 1.0 : v; // draw at least 1 when 0
  return BarChart(
      BarChartData(
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final labels = ['Completed', 'In progress', 'Cancelled'];
              final real = [realCompleted, realInProgress, realCancelled];
              final idx = group.x.toInt();
              final title = idx >= 0 && idx < labels.length ? labels[idx] : '';
              final value = idx >= 0 && idx < real.length ? real[idx] : 0;
              return BarTooltipItem('$title: $value', const TextStyle());
            },
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: shortLabels ? 26 : 24,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= bars.length) return const SizedBox.shrink();
                final full = bars[i].$1;
                final text = shortLabels
                    ? (full == 'Completed'
                        ? 'Comp'
                        : (full == 'In progress' ? 'Prog' : 'Canc'))
                    : full;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(text, style: TextStyle(fontSize: shortLabels ? 10 : 11), overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ),
        ),
  barGroups: [
          for (int i = 0; i < bars.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
      toY: clampBar(bars[i].$2),
                  color: bars[i].$3,
                  width: 22,
                  borderRadius: BorderRadius.circular(8),
                  rodStackItems: const [],
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
    default:
      return 'Unknown';
  }
}

class _StatChip extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  const _StatChip({required this.color, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label: $value'),
      ]),
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
