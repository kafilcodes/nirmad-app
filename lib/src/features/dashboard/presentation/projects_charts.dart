import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Displays a bar chart and a donut pie chart for project statuses.
/// Expects raw counts and computes percentages internally.
class ProjectsCharts extends StatelessWidget {
  final int completed;
  final int inProgress;
  final int cancelled;
  final bool isWide;

  const ProjectsCharts({
    super.key,
    required this.completed,
    required this.inProgress,
    required this.cancelled,
    this.isWide = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = (completed + inProgress + cancelled).clamp(1, 1 << 30);
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 520;
      final medium = c.maxWidth < 840;
      final barHeight = narrow ? 180.0 : (medium ? 220.0 : 260.0);
      final pieHeight = narrow ? 180.0 : (medium ? 210.0 : 240.0);
      const barWidth = 18.0;
      final labelStyle = TextStyle(fontSize: narrow ? 9 : 10, color: cs.onSurfaceVariant);
      final green = Colors.green;
      final orange = Colors.orange;
      final red = Colors.redAccent;
      return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: barHeight,
          child: Card(
            color: cs.surface,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          const labels = ['Completed', 'In prog', 'Cancelled'];
                          final safeIdx = idx < 0 ? 0 : (idx > 2 ? 2 : idx);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(labels[safeIdx], style: labelStyle),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    BarChartGroupData(x: 0, barRods: [
                      BarChartRodData(
                        toY: completed.toDouble(),
                        color: green,
                        width: barWidth,
                        borderRadius: BorderRadius.circular(6),
                        rodStackItems: const [],
                      )
                    ]),
                    BarChartGroupData(x: 1, barRods: [
                      BarChartRodData(
                        toY: inProgress.toDouble(),
                        color: orange,
                        width: barWidth,
                        borderRadius: BorderRadius.circular(6),
                        rodStackItems: const [],
                      )
                    ]),
                    BarChartGroupData(x: 2, barRods: [
                      BarChartRodData(
                        toY: cancelled.toDouble(),
                        color: red,
                        width: barWidth,
                        borderRadius: BorderRadius.circular(6),
                        rodStackItems: const [],
                      )
                    ]),
                  ],
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: pieHeight,
          child: Card(
            color: cs.surface,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                startDegreeOffset: -90,
                sections: [
                  PieChartSectionData(
                    value: completed.toDouble(),
                    color: green,
                    title: '${((completed / total) * 100).toStringAsFixed(0)}%',
                    radius: narrow ? 48 : 60,
                  ),
                  PieChartSectionData(
                    value: inProgress.toDouble(),
                    color: orange,
                    title: '${((inProgress / total) * 100).toStringAsFixed(0)}%',
                    radius: narrow ? 48 : 60,
                  ),
                  PieChartSectionData(
                    value: cancelled.toDouble(),
                    color: red,
                    title: '${((cancelled / total) * 100).toStringAsFixed(0)}%',
                    radius: narrow ? 48 : 60,
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
            ),
          ),
        ),
      ],
    );
  });
  }
}
