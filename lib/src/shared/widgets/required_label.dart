import 'package:flutter/material.dart';

/// Reusable inline label with a red asterisk for required form fields.
class RequiredLabel extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const RequiredLabel(this.text, {super.key, this.style});
  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style.copyWith(color: Theme.of(context).textTheme.bodyMedium?.color);
    return RichText(text: TextSpan(children: [
      TextSpan(text: text, style: base),
      const TextSpan(text: ' *', style: TextStyle(color: Colors.red)),
    ]));
  }
}