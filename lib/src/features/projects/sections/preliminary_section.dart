import 'package:flutter/material.dart';

class PreliminarySection extends StatefulWidget {
  final bool readOnly;
  final Map<String, dynamic>? initial;
  final void Function(Map<String, dynamic> model)? onChanged;
  const PreliminarySection({super.key, this.readOnly = false, this.initial, this.onChanged});

  static bool validateCurrent(GlobalKey<FormState> formKey) => formKey.currentState?.validate() == true;

  @override
  State<PreliminarySection> createState() => _PreliminarySectionState();
}

class _PreliminarySectionState extends State<PreliminarySection> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    // Placeholder wrapper: real fields remain in page for now; this module provides API surface.
    return Form(
      key: _formKey,
      child: const SizedBox.shrink(),
    );
  }
}