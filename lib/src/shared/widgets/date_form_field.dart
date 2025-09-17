import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:toastification/toastification.dart';
import '../../shared/utils/date_parse.dart';

class DateFormField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? Function(String?)? validator;
  final FocusNode? focusNode;
  final bool required;
  final bool enabled;
  final Widget? validationSuffix; // optional animated validation icon
  const DateFormField({
    super.key,
    required this.controller,
    required this.label,
    this.firstDate,
    this.lastDate,
    this.validator,
    this.focusNode,
    this.required = false,
    this.enabled = true,
    this.validationSuffix,
  });

  @override
  State<DateFormField> createState() => _DateFormFieldState();
}

class _DateFormFieldState extends State<DateFormField> {
  Future<void> _pick() async {
    final now = DateTime.now();
    final init = _parse(widget.controller.text) ?? now;
    // showDatePicker works on web and mobile; fallback to text if it fails
    try {
      final picked = await showDatePicker(
        context: context,
        initialDate: init,
        firstDate: widget.firstDate ?? now.subtract(const Duration(days: 365)),
        lastDate: widget.lastDate ?? now.add(const Duration(days: 365)),
        helpText: widget.label,
      );
      if (picked != null) {
        widget.controller.text = _fmt(picked);
      }
    } catch (_) {
      if (!mounted) return;
      toastification.show(
        context: context,
        title: const Text('Date picker unavailable'),
        description: const Text('Use manual entry: YYYY-MM-DD'),
        type: ToastificationType.info,
        style: ToastificationStyle.fillColored,
        autoCloseDuration: const Duration(seconds: 3),
        showProgressBar: false,
        icon: const Icon(CupertinoIcons.calendar),
      );
    }
  }

  String _fmt(DateTime d) => fmtYmd(d);
  DateTime? _parse(String s) => parseAnyDate(s);

  String? _defaultValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final d = parseAnyDate(s);
    if (d == null) return 'Invalid date';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final labelRich = RichText(text: TextSpan(children: [
      TextSpan(text: widget.label, style: DefaultTextStyle.of(context).style.copyWith(color: Theme.of(context).textTheme.bodyMedium?.color)),
      if (widget.required) const TextSpan(text: ' *', style: TextStyle(color: Colors.red)),
    ]));
    return TextFormField(
  focusNode: widget.focusNode,
  enabled: widget.enabled,
      controller: widget.controller,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        label: widget.required ? labelRich : null,
        labelText: widget.required ? null : widget.label,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.validationSuffix != null) widget.validationSuffix!,
            IconButton(
              icon: const Icon(CupertinoIcons.calendar),
              onPressed: _pick,
              tooltip: 'Pick date',
            ),
          ],
        ),
      ),
      keyboardType: TextInputType.datetime,
      textInputAction: TextInputAction.next,
      validator: widget.validator ?? _defaultValidator,
    );
  }
}
