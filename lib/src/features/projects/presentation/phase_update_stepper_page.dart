import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/data/auth_repository.dart';
import '../../projects/domain/project.dart';
import '../../projects/domain/project_update.dart';
import '../../projects/data/project_repository.dart';

class PhaseUpdateStepperPage extends ConsumerStatefulWidget {
  final Project project;
  const PhaseUpdateStepperPage({super.key, required this.project});

  @override
  ConsumerState<PhaseUpdateStepperPage> createState() => _PhaseUpdateStepperPageState();
}

class _PhaseUpdateStepperPageState extends ConsumerState<PhaseUpdateStepperPage> {
  int _currentStep = 0;
  final _comments = <int, String>{};
  final _photos = <int, List<String>>{};
  final _docs = <int, List<String>>{};
  bool _saving = false;

  Future<void> _addPhoto() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (img == null) return;
  final path = await ref.read(storageServiceProvider).uploadProjectPhoto(projectId: widget.project.id, file: File(img.path));
    setState(() => _photos.putIfAbsent(_currentStep, () => []).add(path));
  }

  Future<void> _addDoc() async {
    final res = await FilePicker.platform.pickFiles(withData: false);
    final filePath = res?.files.single.path;
    if (filePath == null) return;
  final path = await ref.read(storageServiceProvider).uploadProjectDoc(projectId: widget.project.id, file: File(filePath));
    setState(() => _docs.putIfAbsent(_currentStep, () => []).add(path));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final user = await ref.read(authRepositoryProvider).currentUser();
      if (user == null) return;
      final repo = ref.read(projectRepositoryProvider);
      for (int step = 0; step <= _currentStep; step++) {
        final update = ProjectUpdate(
          id: 'new',
          projectId: widget.project.id,
          phase: widget.project.phase + step + 1,
          comment: _comments[step],
          photos: _photos[step] ?? const [],
          documents: _docs[step] ?? const [],
          updatedBy: user.uid,
          createdAt: DateTime.now(),
        );
        await repo.addUpdate(widget.project.id, update);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = List.generate(4, (index) => _step(index));
    return Scaffold(
      appBar: AppBar(title: const Text('Phase Updates')),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () => setState(() => _currentStep = (_currentStep + 1).clamp(0, steps.length - 1)),
        onStepCancel: () => setState(() => _currentStep = (_currentStep - 1).clamp(0, steps.length - 1)),
        steps: steps,
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const CircularProgressIndicator() : const Text('Submit Updates'),
        ),
      ),
    );
  }

  Step _step(int index) {
    return Step(
      title: Text('Phase ${widget.project.phase + index + 1}'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            decoration: const InputDecoration(labelText: 'Comment'),
            onChanged: (v) => _comments[index] = v,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            ElevatedButton.icon(onPressed: _addPhoto, icon: const Icon(Icons.camera_alt), label: const Text('Add Photo')),
            ElevatedButton.icon(onPressed: _addDoc, icon: const Icon(Icons.attach_file), label: const Text('Add Document')),
          ]),
          const SizedBox(height: 8),
          if ((_photos[index] ?? const []).isNotEmpty) ...[
            const Text('Photos:'),
            ...(_photos[index] ?? const []).map((p) => Text(p, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          if ((_docs[index] ?? const []).isNotEmpty) ...[
            const Text('Documents:'),
            ...(_docs[index] ?? const []).map((p) => Text(p, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ],
      ),
      isActive: true,
      state: StepState.indexed,
    );
  }
}
