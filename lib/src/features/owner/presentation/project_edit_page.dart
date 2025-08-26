import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/data/auth_repository.dart';
import '../../projects/data/project_repository.dart';
import '../../projects/domain/project.dart';

class ProjectEditPage extends ConsumerStatefulWidget {
  const ProjectEditPage({super.key});

  @override
  ConsumerState<ProjectEditPage> createState() => _ProjectEditPageState();
}

class _ProjectEditPageState extends ConsumerState<ProjectEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  bool _saving = false;
  final _attachments = <String>[];

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (img == null) return;
    final file = File(img.path);
    await _upload(file, isPhoto: true);
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(withData: false);
    final path = res?.files.single.path;
    if (path == null) return;
    await _upload(File(path), isPhoto: false);
  }

  Future<void> _upload(File file, {required bool isPhoto}) async {
    final storage = ref.read(storageServiceProvider);
    // Temporary projectId placeholder for uploads before creation
    final tempId = 'tmp_${DateTime.now().millisecondsSinceEpoch}';
    final p = isPhoto
        ? await storage.uploadProjectPhoto(projectId: tempId, file: file)
        : await storage.uploadProjectDoc(projectId: tempId, file: file);
    setState(() => _attachments.add(p));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = await ref.read(authRepositoryProvider).currentUser();
    if (auth == null) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final project = Project(
        id: 'new',
        name: _name.text.trim(),
        description: _desc.text.trim(),
        ownerId: auth.uid,
        blockId: auth.blocks.isNotEmpty ? auth.blocks.first : '',
        villageId: auth.assignedVillage ?? '',
        status: ProjectStatus.draft,
        phase: 0,
        attachments: List.of(_attachments),
        createdAt: now,
        updatedAt: now,
      );
      final id = await ref.read(projectRepositoryProvider).create(project);
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Project')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Project name'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Add Photo'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Add Document'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_attachments.isNotEmpty) ...[
                const Text('Attachments:'),
                const SizedBox(height: 8),
                ..._attachments.map((p) => Text(p, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const CircularProgressIndicator() : const Text('Save Draft'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
