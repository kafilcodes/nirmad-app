import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/data/auth_repository.dart';
import '../../projects/data/project_repository.dart';
import '../../projects/domain/project.dart';
// import '../../../services/storage_service.dart';

class ProjectUpdateFormPage extends ConsumerStatefulWidget {
  final Project project;
  const ProjectUpdateFormPage({super.key, required this.project});

  @override
  ConsumerState<ProjectUpdateFormPage> createState() => _ProjectUpdateFormPageState();
}

class _ProjectUpdateFormPageState extends ConsumerState<ProjectUpdateFormPage> {
  final _formKey = GlobalKey<FormState>();
  bool _sendingRequest = false;
  bool _saving = false;

  // Basic fields
  String? _comment;
  String? _status; // in_progress | completed | cancelled
  WorkStage? _stage;
  ApramStatus? _apram;

  // Installments
  final _iAmt = <int, String?>{1: null, 2: null, 3: null};
  final _iDate = <int, DateTime?>{1: null, 2: null, 3: null};
  final _iRecAmt = <int, String?>{1: null, 2: null, 3: null};
  final _iRecDate = <int, DateTime?>{1: null, 2: null, 3: null};

  // Media
  final _photos = <String>[];
  final _docs = <String>[];

  // Location
  double? _lat;
  double? _lng;
  bool _locating = false;

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (img == null) return;
      final path = await ref.read(storageServiceProvider).uploadProjectPhoto(projectId: widget.project.id, file: File(img.path));
      setState(() => _photos.add(path));
    } catch (_) {}
  }

  Future<void> _pickDoc() async {
    try {
      final res = await FilePicker.platform.pickFiles(withData: false, type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg']);
      final filePath = res?.files.single.path;
      if (filePath == null) return;
      final path = await ref.read(storageServiceProvider).uploadProjectDoc(projectId: widget.project.id, file: File(filePath));
      setState(() => _docs.add(path));
    } catch (_) {}
  }

  Future<void> _getLocation() async {
    setState(() => _locating = true);
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) return;
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Map<String, dynamic> _buildPayload() {
    final payload = <String, dynamic>{};
    if (_status != null && _status!.isNotEmpty) payload['status'] = _status;
    if (_stage != null) payload['stage'] = _stage!.name;
    if (_apram != null) payload['apramStatus'] = _apram!.name;
    Map<String, dynamic> inst(int n) {
      final amt = _iAmt[n];
      final dt = _iDate[n];
      final ramt = _iRecAmt[n];
      final rdt = _iRecDate[n];
      return {
        if (amt != null && amt.trim().isNotEmpty) 'amount': num.tryParse(amt.trim()),
  if (dt != null) 'date': Timestamp.fromDate(dt),
        if (ramt != null && ramt.trim().isNotEmpty) 'receivedAmount': num.tryParse(ramt.trim()),
  if (rdt != null) 'receivedDate': Timestamp.fromDate(rdt),
      }..removeWhere((k, v) => v == null);
    }
    final i1 = inst(1);
    final i2 = inst(2);
    final i3 = inst(3);
    if (i1.isNotEmpty) payload['installment1'] = i1;
    if (i2.isNotEmpty) payload['installment2'] = i2;
    if (i3.isNotEmpty) payload['installment3'] = i3;
    return payload;
  }

  Future<void> _save() async {
    if (_saving) return;
    final payload = _buildPayload();
    final hasContent = payload.isNotEmpty || (_comment?.trim().isNotEmpty == true) || _photos.isNotEmpty || _docs.isNotEmpty || (_lat != null && _lng != null);
    if (!hasContent) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to submit')));
      return;
    }
    setState(() => _saving = true);
    try {
      final user = await ref.read(authRepositoryProvider).currentUser();
      if (user == null) return;
      final db = FirebaseFirestore.instance;
  // final repo = ref.read(projectRepositoryProvider);

      // Always create a project update doc for audit trail
      final updateRef = db.collection('projects').doc(widget.project.id).collection('updates').doc();
      await updateRef.set({
        'type': _sendingRequest ? 'request' : 'details',
        'payload': payload,
        'comment': _comment,
        'photos': _photos,
        'documents': _docs,
        'updatedBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        if (_lat != null && _lng != null) 'location': {'lat': _lat, 'lng': _lng},
      });

      // Create a global notification for nodals (triage if request)
      final notifRef = db.collection('updates').doc();
      await notifRef.set({
        'type': _sendingRequest ? 'request' : 'status',
        'title': _sendingRequest ? 'Request: Project update' : 'Project updated',
        'body': (_comment?.trim().isNotEmpty == true) ? _comment : 'Project fields updated',
        'projectId': widget.project.id,
        'projectName': widget.project.name,
        'ownerId': widget.project.ownerId,
        'blockId': widget.project.blockId,
        'targetRoles': ['super_nodal', 'sub_nodal'],
        'readBy': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updateId': updateRef.id,
        if (_sendingRequest) 'triageStatus': 'ack', // optional: auto-ack or leave null
      });

      // If not a request, apply changes immediately to the project document
      if (!_sendingRequest && payload.isNotEmpty) {
        final projRef = db.collection('projects').doc(widget.project.id);
        final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
        if (payload['status'] != null) {
          data['status'] = payload['status'];
          if (payload['status'] == 'completed') data['completedAt'] = FieldValue.serverTimestamp();
        }
        if (payload['stage'] != null || payload['apramStatus'] != null) {
          data['workDescription'] = {
            if (payload['stage'] != null) 'stage': payload['stage'],
            if (payload['apramStatus'] != null) 'apramStatus': payload['apramStatus'],
          };
        }
        Map<String, dynamic> instMerge(String key) {
          final v = payload[key] as Map<String, dynamic>?;
          if (v == null || v.isEmpty) return {};
          return {'allotmentDetails': {key: v}};
        }
        data.addAll(instMerge('installment1'));
        data.addAll(instMerge('installment2'));
        data.addAll(instMerge('installment3'));
        await projRef.set(data, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Update Project')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SwitchListTile(
              value: _sendingRequest,
              onChanged: (v) => setState(() => _sendingRequest = v),
              title: const Text('Send as request to Nodal (requires approval)'),
              subtitle: const Text('If enabled, changes are applied after nodal resolves the request.'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Comment (optional)'),
              maxLines: 3,
              onChanged: (v) => _comment = v,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Status'),
              value: _status,
              items: const [
                DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<WorkStage>(
              decoration: const InputDecoration(labelText: 'Work Stage'),
              value: _stage,
              items: WorkStage.values.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(),
              onChanged: (v) => setState(() => _stage = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ApramStatus>(
              decoration: const InputDecoration(labelText: 'Apram Status'),
              value: _apram,
              items: ApramStatus.values.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(),
              onChanged: (v) => setState(() => _apram = v),
            ),
            const Divider(height: 24),
            Text('Installments', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...[1,2,3].map((n) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Installment $n', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: TextFormField(
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) => _iAmt[n] = v,
                )),
                const SizedBox(width: 8),
                Expanded(child: _DateField(
                  label: 'Date',
                  value: _iDate[n],
                  onChanged: (d) => setState(() => _iDate[n] = d),
                )),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: TextFormField(
                  decoration: const InputDecoration(labelText: 'Received Amount'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) => _iRecAmt[n] = v,
                )),
                const SizedBox(width: 8),
                Expanded(child: _DateField(
                  label: 'Received Date',
                  value: _iRecDate[n],
                  onChanged: (d) => setState(() => _iRecDate[n] = d),
                )),
              ]),
              const SizedBox(height: 12),
            ])).toList(),
            const Divider(height: 24),
            Wrap(spacing: 8, children: [
              FilledButton.icon(onPressed: _pickPhoto, icon: const Icon(CupertinoIcons.camera), label: const Text('Add Photo')),
              FilledButton.icon(onPressed: _pickDoc, icon: const Icon(CupertinoIcons.paperclip), label: const Text('Add Document')),
              FilledButton.icon(onPressed: _locating ? null : _getLocation, icon: const Icon(CupertinoIcons.location), label: Text(_locating ? 'Locating…' : 'Use location')),
            ]),
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Photos:'),
              ..._photos.map((e) => Text(e, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            if (_docs.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Documents:'),
              ..._docs.map((e) => Text(e, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const CircularProgressIndicator() : const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  const _DateField({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 5),
        );
        onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value == null ? '-' : value!.toLocal().toString().split(' ').first),
      ),
    );
  }
}
