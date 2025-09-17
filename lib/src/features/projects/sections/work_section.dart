import 'package:flutter/material.dart';

class WorkSection extends StatefulWidget {
  final bool readOnly;
  final Map<String, dynamic>? initial;
  final void Function(Map<String, dynamic> model)? onChanged;
  const WorkSection({super.key, this.readOnly = false, this.initial, this.onChanged});

  static bool validateCurrent(GlobalKey<FormState> formKey) => formKey.currentState?.validate() == true;

  @override
  State<WorkSection> createState() => _WorkSectionState();
}

class _WorkSectionState extends State<WorkSection> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: const SizedBox.shrink(),
    );
  }
}