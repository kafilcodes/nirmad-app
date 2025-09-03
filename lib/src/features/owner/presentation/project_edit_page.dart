import 'package:flutter/material.dart';

// Legacy create/edit page replaced by the new Create Project tab in OwnerShell.
class ProjectEditPage extends StatelessWidget {
  const ProjectEditPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('This page has moved. Use Owner > Create Project.')),
    );
  }
}
