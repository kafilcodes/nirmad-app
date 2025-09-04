import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';

class NoData extends StatelessWidget {
  final String message;
  final String? title;
  final String asset;
  final double maxWidth;
  const NoData({super.key, required this.message, this.title, this.asset = 'assets/no_data.svg', this.maxWidth = 320});

  @override
  Widget build(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final screenW = MediaQuery.of(context).size.width;
  final targetWidth = screenW < 420 ? 240.0 : maxWidth;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: targetWidth),
            child: AspectRatio(
              aspectRatio: 1.2,
              child: SvgPicture.asset(
                asset,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const Gap(12),
          if (title != null) ...[
            Text(title!, style: Theme.of(context).textTheme.titleMedium),
            const Gap(6),
          ],
          Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.outline), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
