import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/utils/date_parse.dart';

typedef MetricsTapHandler = void Function(String filterKey);

class MetricsTiles extends ConsumerWidget {
  const MetricsTiles({super.key, this.query, this.onTap, this.docs});

  // Optional Firestore query to scope metrics (e.g., by role/blocks)
  final Query<Map<String, dynamic>>? query;
  // Optional tap handler: 'all' | 'in_progress' | 'completed' | 'delayed_30' | 'delayed_60'
  final MetricsTapHandler? onTap;
  // Optional pre-fetched docs to avoid creating another listener
  final List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  if (docs != null) {
      return _buildFromDocs(docs!);
    }
    final Stream<QuerySnapshot<Map<String, dynamic>>> stream =
        query != null
            ? query!.snapshots()
            : FirebaseFirestore.instance.collection('projects').orderBy('updatedAt', descending: true).snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _MetricsSkeleton();
        final docs = snapshot.data!.docs;
        final total = docs.length;
  final completed = docs.where((d) => d.data()['status'] == 'completed').length;
  final cancelled = docs.where((d) => d.data()['status'] == 'cancelled').length;
  // Treat any non-completed, non-cancelled projects as in-progress
  final inProgress = total - completed - cancelled;
  int delayedCount(int days) => _delayedByDaysCountFromDocs(docs, days);
        final delayed30 = delayedCount(30);
        final delayed60 = delayedCount(60);
        return LayoutBuilder(builder: (context, c) {
          final maxW = c.maxWidth == double.infinity ? MediaQuery.of(context).size.width : c.maxWidth;
          final isNarrow = maxW < 680; // mobile-first: stack into two per row on small screens
          final compact = isNarrow || Theme.of(context).platform == TargetPlatform.android;
          final tileWidth = isNarrow ? (maxW - 12) / 2 : 240.0;
          final children = <Widget>[
SizedBox(width: tileWidth, child: _tile(context, 'Total', total, Colors.blue, () => onTap?.call('all'), compact: compact)),
SizedBox(width: tileWidth, child: _tile(context, 'In progress', inProgress, Colors.orange, () => onTap?.call('in_progress'), compact: compact)),
SizedBox(width: tileWidth, child: _tile(context, 'Completed', completed, Colors.green, () => onTap?.call('completed'), compact: compact)),
SizedBox(width: tileWidth, child: _tile(context, 'Delayed 30d', delayed30, Colors.redAccent, () => onTap?.call('delayed_30'), compact: compact)),
SizedBox(width: tileWidth, child: _tile(context, 'Delayed 60d', delayed60, Colors.red, () => onTap?.call('delayed_60'), compact: compact)),
          ];
          return Wrap(
            spacing: isNarrow ? 6 : 8,
            runSpacing: isNarrow ? 6 : 8,
            children: children,
          );
        });
      },
    );
  }

  Widget _buildFromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final total = docs.length;
    final completed = docs.where((d) => d.data()['status'] == 'completed').length;
    final cancelled = docs.where((d) => d.data()['status'] == 'cancelled').length;
    final inProgress = total - completed - cancelled;
  int delayedCount(int days) => _delayedByDaysCountFromDocs(docs, days);
    final delayed30 = delayedCount(30);
    final delayed60 = delayedCount(60);
    return LayoutBuilder(builder: (context, c) {
      final maxW = c.maxWidth == double.infinity ? MediaQuery.of(context).size.width : c.maxWidth;
      final isNarrow = maxW < 680;
      final compact = isNarrow || Theme.of(context).platform == TargetPlatform.android;
      final tileWidth = isNarrow ? (maxW - 12) / 2 : 240.0;
      final children = <Widget>[
SizedBox(width: tileWidth, child: _tile(context, 'Total', total, Colors.blue, () => onTap?.call('all'), compact: compact)),
SizedBox(width: tileWidth, child: _tile(context, 'In progress', inProgress, Colors.orange, () => onTap?.call('in_progress'), compact: compact)),
SizedBox(width: tileWidth, child: _tile(context, 'Completed', completed, Colors.green, () => onTap?.call('completed'), compact: compact)),
SizedBox(width: tileWidth, child: _tile(context, 'Delayed 30d', delayed30, Colors.redAccent, () => onTap?.call('delayed_30'), compact: compact)),
SizedBox(width: tileWidth, child: _tile(context, 'Delayed 60d', delayed60, Colors.red, () => onTap?.call('delayed_60'), compact: compact)),
      ];
      return Wrap(
        spacing: isNarrow ? 6 : 8,
        runSpacing: isNarrow ? 6 : 8,
        children: children,
      );
    });
  }

  Widget _tile(BuildContext context, String label, int value, Color color, VoidCallback? onTap, {bool compact = false}) {
    final cs = Theme.of(context).colorScheme;
    final icon = label == 'Total'
        ? Icons.layers
        : label == 'In progress'
            ? CupertinoIcons.time
            : label == 'Completed'
                ? CupertinoIcons.check_mark_circled
                : label.contains('30')
                    ? CupertinoIcons.calendar
                    : CupertinoIcons.exclamationmark_triangle;
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final minHeight = compact ? (isAndroid ? 84.0 : 80.0) : (isAndroid ? 96.0 : 88.0);
    final padH = compact ? 12.0 : 14.0;
    final padV = compact ? 10.0 : 12.0;
    final avatarSize = compact ? 38.0 : 44.0;
    final iconSize = compact ? 18.0 : 20.0;
    final gap = compact ? 10.0 : 12.0;
    final valueFontSize = compact ? 22.0 : 24.0;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          // Slightly larger min height on Android to improve touch target
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
            child: Row(
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, size: iconSize, color: color),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$value', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontSize: valueFontSize)),
                      const SizedBox(height: 2),
                      Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontSize: compact ? 12.5 : null)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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

class _MetricsSkeleton extends StatelessWidget {
  const _MetricsSkeleton();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final maxW = c.maxWidth == double.infinity ? MediaQuery.of(context).size.width : c.maxWidth;
      final isNarrow = maxW < 680;
      final tileWidth = isNarrow ? (maxW - 12) / 2 : 240.0;
      final tiles = List.generate(5, (i) => SizedBox(
            width: tileWidth,
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12),
                child: Row(
                  children: [
                    const _SkeletonBlock(height: 44, width: 44, radius: BorderRadius.all(Radius.circular(22))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          _SkeletonBlock(height: 24, width: 60, radius: BorderRadius.all(Radius.circular(6))),
                          SizedBox(height: 6),
                          _SkeletonBlock(height: 16, width: 100, radius: BorderRadius.all(Radius.circular(6))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ));
      return Wrap(spacing: 8, runSpacing: 8, children: tiles);
    });
  }
}

int _delayedByDaysCountFromDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, int days) {
  final today = DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final cutoff = startOfToday.subtract(Duration(days: days));
  int count = 0;
  for (final d in docs) {
    final data = d.data();
    final status = data['status'];
    if (status == 'completed') continue;
    final deadline = data['financials'] is Map ? (data['financials']['deadline']) : null;
    final due = parseAnyDate(deadline);
    if (due != null && due.isBefore(cutoff)) count++;
  }
  return count;
}
