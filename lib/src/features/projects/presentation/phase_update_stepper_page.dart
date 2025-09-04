import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/data/auth_repository.dart';
import '../../projects/domain/project.dart';
import '../../projects/domain/project_update.dart';
import '../../projects/data/project_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

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
  final _types = <int, String>{}; // work|financial|details|status|request
  final _payloads = <int, Map<String, dynamic>>{}; // typed payload (e.g., amounts)
  final _skip = <int, bool>{};
  bool _saving = false;
  double? _lat;
  double? _lng;
  bool _locating = false;

  Future<void> _getLocation() async {
    setState(() => _locating = true);
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (_) {
      // ignore errors; user can retry
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _addPhoto() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (img == null) return;
  final path = await ref.read(storageServiceProvider).uploadProjectPhoto(projectId: widget.project.id, file: File(img.path));
    setState(() => _photos.putIfAbsent(_currentStep, () => []).add(path));
  }

  Future<void> _addDoc() async {
    final res = await FilePicker.platform.pickFiles(
      withData: false,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg'],
    );
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
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      String? pendingStatusChange;
      for (int step = 0; step <= _currentStep; step++) {
        // honor skip toggle
        if (_skip[step] == true) continue;
        final hasContent = ((_comments[step] ?? '').trim().isNotEmpty) || (_photos[step]?.isNotEmpty == true) || (_docs[step]?.isNotEmpty == true) || (_types[step]?.isNotEmpty == true);
        if (!hasContent) continue; // nothing to write
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
        final updateId = await repo.addUpdate(widget.project.id, update);
        // Attach location to the update doc when available
        if (_lat != null && _lng != null) {
          try {
            await FirebaseFirestore.instance
                .collection('projects')
                .doc(widget.project.id)
                .collection('updates')
                .doc(updateId)
                .set({'location': {'lat': _lat, 'lng': _lng}}, SetOptions(merge: true));
          } catch (_) {}
        }
        // If typed update selected, persist metadata into the update doc
        final t = _types[step];
        final pl = _payloads[step];
        if (t != null || (pl != null && pl.isNotEmpty)) {
          try {
            await FirebaseFirestore.instance
                .collection('projects')
                .doc(widget.project.id)
                .collection('updates')
                .doc(updateId)
                .set({
                  if (t != null) 'type': t,
                  if (pl != null && pl.isNotEmpty) 'payload': pl,
                }, SetOptions(merge: true));
          } catch (_) {}
          if (t == 'status') {
            final newStatus = (pl?['status'] as String?)?.trim();
            if (newStatus != null && newStatus.isNotEmpty) pendingStatusChange = newStatus;
          }
        }
        // Also write a role-targeted notification for nodals
        final notifRef = db.collection('updates').doc();
        batch.set(notifRef, {
          'title': 'Phase ${update.phase} update',
          'body': (update.comment ?? '').isEmpty ? 'An update was submitted' : update.comment,
          'projectId': widget.project.id,
          'projectName': widget.project.name,
          'ownerId': widget.project.ownerId,
          'blockId': widget.project.blockId,
          'targetRoles': ['super_nodal', 'sub_nodal'],
          'createdAt': FieldValue.serverTimestamp(),
          'readBy': <String>[],
          'userId': null,
          'updateId': updateId,
          if (_lat != null && _lng != null) 'location': {'lat': _lat, 'lng': _lng},
          if (t != null) 'type': t,
        });
      }
      // Apply status change to project if any (merge)
      if (pendingStatusChange != null) {
        final projRef = db.collection('projects').doc(widget.project.id);
        final data = <String, dynamic>{'status': pendingStatusChange};
        if (pendingStatusChange == 'completed') {
          data['completedAt'] = FieldValue.serverTimestamp();
        }
        batch.set(projRef, data, SetOptions(merge: true));
      }
      await batch.commit();
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _lat == null || _lng == null
                        ? 'No location attached'
                        : 'Location attached (${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)})',
                  ),
                ),
                FilledButton.icon(
                  onPressed: _locating ? null : _getLocation,
                  icon: const Icon(CupertinoIcons.location),
                  label: Text(_locating ? 'Locating…' : 'Use location'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Stepper(
              currentStep: _currentStep,
              onStepContinue: () => setState(() => _currentStep = (_currentStep + 1).clamp(0, steps.length - 1)),
              onStepCancel: () => setState(() => _currentStep = (_currentStep - 1).clamp(0, steps.length - 1)),
              steps: steps,
            ),
          ),
        ],
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
    final isSkipped = _skip[index] == true;
    final hasContent = ((_comments[index] ?? '').trim().isNotEmpty) || (_photos[index]?.isNotEmpty == true) || (_docs[index]?.isNotEmpty == true) || (_types[index]?.isNotEmpty == true);
  final stepState = (isSkipped || hasContent) ? StepState.complete : StepState.indexed;
  return Step(
      title: Text('Phase ${widget.project.phase + index + 1}'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: _skip[index] == true,
            onChanged: (v) => setState(() => _skip[index] = v == true),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Skip this step (no update will be created)') ,
          ),
          // Update type selector (optional)
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Update Type (optional)') ,
            items: const [
              DropdownMenuItem(value: 'work', child: Text('Work Progress')),
              DropdownMenuItem(value: 'financial', child: Text('Financial Details')),
              DropdownMenuItem(value: 'details', child: Text('Project Details Change')),
              DropdownMenuItem(value: 'status', child: Text('Status Change')),
              DropdownMenuItem(value: 'request', child: Text('Request (items/funds/other)')),
            ],
            initialValue: _types[index],
            onChanged: (v) => setState(() {
              if (v == null) {
                _types.remove(index);
                _payloads.remove(index);
              } else {
                _types[index] = v;
                _payloads.putIfAbsent(index, () => <String, dynamic>{});
              }
            }),
          ),
          const SizedBox(height: 8),
          TextFormField(
            decoration: const InputDecoration(labelText: 'Comment'),
            onChanged: (v) => _comments[index] = v,
            maxLines: 3,
          ),
          if ((_types[index] ?? '') == 'financial') ...[
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Expenditure Amount (optional)') ,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) => _payloads.putIfAbsent(index, () => <String, dynamic>{})['expenditure'] = v,
            ),
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Funds Received (optional)') ,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) => _payloads.putIfAbsent(index, () => <String, dynamic>{})['fundsReceived'] = v,
            ),
          ],
          if ((_types[index] ?? '') == 'status') ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Status') ,
              items: const [
                DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              ],
              initialValue: _payloads[index]?['status'] as String?,
              onChanged: (v) => setState(() => _payloads.putIfAbsent(index, () => <String, dynamic>{})['status'] = v),
            ),
          ],
          if ((_types[index] ?? '') == 'request') ...[
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Request Title'),
              onChanged: (v) => _payloads.putIfAbsent(index, () => <String, dynamic>{})['title'] = v,
            ),
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Request Details'),
              maxLines: 3,
              onChanged: (v) => _payloads.putIfAbsent(index, () => <String, dynamic>{})['details'] = v,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            ElevatedButton.icon(onPressed: _addPhoto, icon: const Icon(CupertinoIcons.camera), label: const Text('Add Photo')),
            ElevatedButton.icon(onPressed: _addDoc, icon: const Icon(CupertinoIcons.paperclip), label: const Text('Add Document')),
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
  state: stepState,
    );
  }
}
