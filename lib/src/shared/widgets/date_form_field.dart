import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:toastification/toastification.dart';

class DateFormField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? Function(String?)? validator;
  final FocusNode? focusNode;
  const DateFormField({super.key, required this.controller, required this.label, this.firstDate, this.lastDate, this.validator, this.focusNode});

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
        firstDate: widget.firstDate ?? DateTime(2000),
        lastDate: widget.lastDate ?? DateTime(now.year + 5),
        helpText: widget.label,
      );
      if (picked != null) {
        widget.controller.text = _fmt(picked);
      }
    } catch (_) {
      // ignore: use_build_context_synchronously
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

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DateTime? _parse(String s) { try { if (s.trim().isEmpty) return null; return DateTime.parse(s.trim()); } catch (_) { return null; } }

  String? _defaultValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!re.hasMatch(s)) return 'Use YYYY-MM-DD';
    try { DateTime.parse(s); } catch (_) { return 'Invalid date'; }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
  focusNode: widget.focusNode,
      controller: widget.controller,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          icon: const Icon(CupertinoIcons.calendar),
          onPressed: _pick,
          tooltip: 'Pick date',
        ),
      ),
      keyboardType: TextInputType.datetime,
      textInputAction: TextInputAction.next,
      validator: widget.validator ?? _defaultValidator,
    );
  }
}
