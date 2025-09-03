import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class BrandingFooter extends StatelessWidget {
  final EdgeInsets padding;
  const BrandingFooter({super.key, this.padding = const EdgeInsets.all(8)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(CupertinoIcons.checkmark_seal, size: 16),
          SizedBox(width: 6),
          Text('Dhamtari District Administration ®', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
