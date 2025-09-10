import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/data/auth_repository.dart';
import '../../projects/domain/project.dart';
import '../../projects/domain/project_update.dart';
import '../../projects/data/project_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../auth/domain/app_user.dart';

class PhaseUpdateStepperPage extends ConsumerStatefulWidget {
  final Project project;
  const PhaseUpdateStepperPage({super.key, required this.project});

  @override
  ConsumerState<PhaseUpdateStepperPage> createState() => _PhaseUpdateStepperPageState();
}

class _PhaseUpdateStepperPageState extends ConsumerState<PhaseUpdateStepperPage> {
  int _currentStep = 0;
  final _comments = <int, String>{};
  final _commentCtrls = <int, TextEditingController>{};
  final _commentWords = <int, int>{};
  final _photos = <int, List<String>>{};
  final _docs = <int, List<String>>{};
  final _types = <int, String>{}; // work|financial|details|status|request
  final _payloads = <int, Map<String, dynamic>>{}; // typed payload (e.g., amounts)
  final _skip = <int, bool>{};
  bool _saving = false;
  double? _lat;
  double? _lng;
  bool _locating = false;

  int _countWords(String s) => s.trim().isEmpty ? 0 : s.trim().split(RegExp(r"\s+")).where((e) => e.isNotEmpty).length;
  String _firstWords(String s, int n) {
    final words = s.trim().split(RegExp(r"\s+")).where((e) => e.isNotEmpty).toList();
    if (words.length <= n) return s.trim();
    return words.take(n).join(' ');
  }

  @override
  void dispose() {
    for (final c in _commentCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _confirmDisclaimer() async {
    final user = await ref.read(authRepositoryProvider).currentUser();
    if (user == null) return false;
    // Skip for dev admin
    if (user.role == UserRole.devAdmin) return true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm and proceed'),
        content: const Text(
          'I confirm the information provided is accurate to the best of my knowledge. '
          'Submitting false or misleading data may lead to rejection or action. '
          'Your update will be recorded with timestamp and may include your location.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('I understand')),
        ],
      ),
    );
    return accepted == true;
  }

  Future<void> _getLocation() async {
    setState(() => _locating = true);
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permission denied'),
              action: SnackBarAction(label: 'Settings', onPressed: () { openAppSettings(); }),
            ),
          );
        }
        return;
      }
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Turn on device location services to continue.')),
          );
        }
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
    // Enforce max 3 photos per step/update
    final current = _photos[_currentStep]?.length ?? 0;
    if (current >= 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 3 photos per update step')));
      }
      return;
    }
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
    final statuses = await Connectivity().checkConnectivity().catchError((_) => <ConnectivityResult>[]);
    if (statuses.isEmpty || statuses.every((s) => s == ConnectivityResult.none)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are offline. Please try again when back online.')));
      }
      return;
    }
    // Validate financial amounts (if provided) before proceeding
    const maxAllowed = 500000000; // 50 crores cap
    for (int step = 0; step <= _currentStep; step++) {
      if ((_types[step] ?? '') != 'financial') continue;
      final payload = _payloads[step] ?? const <String, dynamic>{};
      final String? expStr = payload['expenditure'] as String?;
      final String? recStr = payload['fundsReceived'] as String?;
      double? exp, rec;
      if (expStr != null && expStr.trim().isNotEmpty) {
        exp = double.tryParse(expStr.trim());
        if (exp == null || exp < 0 || exp > maxAllowed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid Expenditure at Phase ${widget.project.phase + step + 1}. Enter a number up to ₹50,00,00,000.')),
          );
          return;
        }
      }
      if (recStr != null && recStr.trim().isNotEmpty) {
        rec = double.tryParse(recStr.trim());
        if (rec == null || rec < 0 || rec > maxAllowed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid Funds Received at Phase ${widget.project.phase + step + 1}. Enter a number up to ₹50,00,00,000.')),
          );
          return;
        }
      }
    }
    setState(() => _saving = true);
    try {
  // Require explicit confirmation for non-admin roles
  final ok = await _confirmDisclaimer();
  if (!ok) return;
      // Soft prompt if submitting without location
      if (_lat == null || _lng == null) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Submit without location?'),
            content: const Text('Including your current location helps nodal officers verify work. You can still proceed without it.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Add location')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Proceed')),
            ],
          ),
        );
        if (proceed != true) return;
      }
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
      appBar: AppBar(
        title: const Text('Phase Updates'),
        actions: [
          TextButton.icon(onPressed: _saving ? null : _save, icon: const Icon(CupertinoIcons.paperplane), label: const Text('Submit')),
        ],
      ),
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
  // Bottom action bar removed to prevent overflows on small devices; use AppBar action instead
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
            controller: _commentCtrls.putIfAbsent(index, () {
              final c = TextEditingController(text: _comments[index]);
              c.addListener(() {
                final v = c.text;
                final w = _countWords(v);
                if (w <= 100) {
                  setState(() {
                    _comments[index] = v;
                    _commentWords[index] = w;
                  });
                } else {
                  final trimmed = _firstWords(v, 100);
                  if (trimmed != v) {
                    c.text = trimmed;
                    final end = trimmed.length;
                    c.selection = TextSelection.fromPosition(TextPosition(offset: end));
                  }
                  setState(() {
                    _comments[index] = trimmed;
                    _commentWords[index] = 100;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max 100 words allowed')));
                }
              });
              return c;
            }),
            textAlignVertical: TextAlignVertical.center,
            decoration: const InputDecoration(labelText: 'Comment'),
            maxLines: 3,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text('${_commentWords[index] ?? 0}/100 words', style: Theme.of(context).textTheme.labelSmall),
          ),
          if ((_types[index] ?? '') == 'financial') ...[
            const SizedBox(height: 8),
            TextFormField(
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(labelText: 'Expenditure Amount (optional)') ,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                _TwoDecimalNumberFormatter(),
              ],
              onChanged: (v) => setState(() {
                _payloads.putIfAbsent(index, () => <String, dynamic>{})['expenditure'] = v;
              }),
            ),
            Builder(builder: (context) {
              final s = (_payloads[index]?['expenditure'] as String?)?.trim() ?? '';
              final helper = _inrHelper(s);
              return helper == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(helper, style: Theme.of(context).textTheme.labelSmall),
                    );
            }),
            const SizedBox(height: 8),
            TextFormField(
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(labelText: 'Funds Received (optional)') ,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                _TwoDecimalNumberFormatter(),
              ],
              onChanged: (v) => setState(() {
                _payloads.putIfAbsent(index, () => <String, dynamic>{})['fundsReceived'] = v;
              }),
            ),
            Builder(builder: (context) {
              final s = (_payloads[index]?['fundsReceived'] as String?)?.trim() ?? '';
              final helper = _inrHelper(s);
              return helper == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Received: $helper', style: Theme.of(context).textTheme.labelSmall),
                    );
            }),
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
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(labelText: 'Request Title'),
              onChanged: (v) => _payloads.putIfAbsent(index, () => <String, dynamic>{})['title'] = v,
            ),
            const SizedBox(height: 8),
            TextFormField(
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(labelText: 'Request Details'),
              maxLines: 3,
              onChanged: (v) => _payloads.putIfAbsent(index, () => <String, dynamic>{})['details'] = v,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            ElevatedButton.icon(
              onPressed: _addPhoto,
              icon: const Icon(CupertinoIcons.camera),
              label: const Text('Add Photo'),
              style: ElevatedButton.styleFrom(
                alignment: Alignment.center,
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      height: 1.0,
                      leadingDistribution: TextLeadingDistribution.even,
                      textBaseline: TextBaseline.alphabetic,
                    ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _addDoc,
              icon: const Icon(CupertinoIcons.paperclip),
              label: const Text('Add Document'),
              style: ElevatedButton.styleFrom(
                alignment: Alignment.center,
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      height: 1.0,
                      leadingDistribution: TextLeadingDistribution.even,
                      textBaseline: TextBaseline.alphabetic,
                    ),
              ),
            ),
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

// INR helper utilities for showing money in Indian format and words
extension on _PhaseUpdateStepperPageState {
  String? _inrHelper(String s) {
    final norm = s.replaceAll(',', '').trim();
    if (norm.isEmpty) return null;
    final d = double.tryParse(norm);
    if (d == null) return null;
    final intR = d.floor();
    return '₹${_indianGrouping(intR)} (${_rupeesInWords(intR)})';
  }

  String _indianGrouping(int value) {
    final str = value.toString();
    if (str.length <= 3) return str;
    final last3 = str.substring(str.length - 3);
    String rest = str.substring(0, str.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }

  String _rupeesInWords(int n) {
    if (n == 0) return 'zero rupees';
    String two(int x) {
      const ones = ['zero','one','two','three','four','five','six','seven','eight','nine','ten','eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen'];
      const tens = ['', '', 'twenty','thirty','forty','fifty','sixty','seventy','eighty','ninety'];
      if (x < 20) return ones[x];
      final t = x ~/ 10, o = x % 10;
      return tens[t] + (o > 0 ? '-${ones[o]}' : '');
    }
    String three(int x) {
      final h = x ~/ 100; final r = x % 100;
      if (h == 0) return two(r);
      final head = '${two(h)} hundred';
      if (r == 0) return head;
      return '$head ${two(r)}';
    }
    final crore = n ~/ 10000000;
    final lakh = (n % 10000000) ~/ 100000;
    final thousand = (n % 100000) ~/ 1000;
    final hundred = n % 1000;
    final parts = <String>[];
    if (crore > 0) parts.add('${crore < 100 ? two(crore) : three(crore)} crore');
    if (lakh > 0) parts.add('${two(lakh)} lakh');
    if (thousand > 0) parts.add('${two(thousand)} thousand');
    if (hundred > 0) parts.add(three(hundred));
    return parts.join(' ') + ' rupees';
  }
}

class _TwoDecimalNumberFormatter extends TextInputFormatter {
  final RegExp _valid = RegExp(r'^[0-9]+(\.[0-9]{0,2})?$');
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (_valid.hasMatch(text)) return newValue;
    // Normalize: keep digits, single dot, and max 2 decimals
    final numeric = text.replaceAll(RegExp(r'[^0-9\.]'), '');
    final parts = numeric.split('.');
    String fixed;
    if (parts.length == 1) {
      fixed = parts[0];
    } else {
      final intPart = parts.first;
      final decPart = parts.skip(1).join('');
      final trimmedDec = decPart.replaceAll(RegExp(r'[^0-9]'), '');
      fixed = '$intPart.${trimmedDec.substring(0, trimmedDec.length.clamp(0, 2))}';
    }
    return TextEditingValue(text: fixed, selection: TextSelection.collapsed(offset: fixed.length));
  }
}
