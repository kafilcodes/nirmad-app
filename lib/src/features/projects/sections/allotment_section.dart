import 'package:flutter/material.dart';

class AllotmentSection extends StatefulWidget {
  final bool readOnly;
  final Map<String, dynamic>? initial;
  final void Function(Map<String, dynamic> model)? onChanged;
  const AllotmentSection({super.key, this.readOnly = false, this.initial, this.onChanged});

  static bool validateCurrent(GlobalKey<FormState> formKey) => formKey.currentState?.validate() == true;

  @override
  State<AllotmentSection> createState() => _AllotmentSectionState();
}

class _AllotmentSectionState extends State<AllotmentSection> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: const SizedBox.shrink(),
    );
  }
}