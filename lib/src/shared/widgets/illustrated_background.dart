import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class IllustratedBackground extends StatelessWidget {
  const IllustratedBackground({super.key, required this.child, required this.asset, this.opacity = 0.18, this.alignment = Alignment.bottomRight});
  final Widget child;
  final String asset;
  final double opacity;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: opacity,
            child: Align(
              alignment: alignment,
              child: IgnorePointer(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    child: SvgPicture.asset(asset, alignment: alignment, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
